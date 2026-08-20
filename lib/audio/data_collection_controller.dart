import 'dart:async';
import 'dart:typed_data';

import 'audio_constants.dart';
import 'clip_store.dart';
import 'collection_label.dart';
import 'mic_capture_service.dart';
import 'rolling_clip_buffer.dart';
import 'wav_writer.dart';

/// Snapshot of the current session's per-label counts plus whether a clip
/// exists to undo.
class CollectionTally {
  const CollectionTally({required this.counts, required this.canUndo});

  final Map<CollectionLabel, int> counts;
  final bool canUndo;

  int countFor(CollectionLabel label) => counts[label] ?? 0;

  static const empty = CollectionTally(counts: {}, canUndo: false);
}

/// Seam between the data-collection UI and real mic/filesystem plumbing, so
/// the screen can be widget-tested with a fake implementation -- same
/// pattern as [MicLevelController] (mic_level_controller.dart).
abstract class DataCollectionController {
  Stream<CollectionTally> get tally;
  CollectionTally get currentTally;
  bool get isCapturing;
  Future<void> start();
  Future<void> stop();
  Future<void> tag(CollectionLabel label);
  Future<void> undoLast();
}

class _PendingTap {
  _PendingTap({required this.label, required this.tapIndex, required this.timestamp});
  final CollectionLabel label;
  final int tapIndex;
  final DateTime timestamp;
}

class _ReadyClip {
  _ReadyClip({required this.label, required this.timestamp, required this.pcmBytes});
  final CollectionLabel label;
  final DateTime timestamp;
  final Uint8List pcmBytes;
}

class _WrittenClip {
  _WrittenClip({required this.label, required this.path});
  final CollectionLabel label;
  final String path;
}

/// Production implementation: keeps a rolling PCM buffer behind live
/// capture, and on each [tag] slices+writes a ready-to-train clip once its
/// post-roll audio has arrived (see [RollingClipBuffer]). No background
/// service -- this mode is only ever used foreground, with the screen open
/// (see the spec's Decisions section).
class LiveDataCollectionController implements DataCollectionController {
  LiveDataCollectionController({
    MicCaptureService? captureService,
    ClipStore? clipStore,
    this.preRoll = const Duration(milliseconds: 1500),
    this.postRoll = const Duration(milliseconds: 500),
    int sampleRate = micSampleRate,
  })  : _captureService = captureService ?? MicCaptureService(),
        _clipStore = clipStore ?? const FileClipStore(),
        _sampleRate = sampleRate;

  final MicCaptureService _captureService;
  final ClipStore _clipStore;
  final Duration preRoll;
  final Duration postRoll;
  final int _sampleRate;

  RollingClipBuffer? _buffer;
  StreamSubscription<Uint8List>? _captureSubscription;
  final List<_PendingTap> _pending = [];
  final List<_WrittenClip> _written = [];
  final Map<CollectionLabel, int> _counts = {for (final l in CollectionLabel.values) l: 0};
  final StreamController<CollectionTally> _tallyController =
      StreamController<CollectionTally>.broadcast();

  @override
  bool get isCapturing => _captureService.isCapturing;

  @override
  Stream<CollectionTally> get tally => _tallyController.stream;

  @override
  CollectionTally get currentTally =>
      CollectionTally(counts: Map.of(_counts), canUndo: _written.isNotEmpty);

  @override
  Future<void> start() async {
    final granted = await _captureService.requestPermission();
    if (!granted) {
      throw StateError('Microphone permission denied.');
    }

    _buffer = RollingClipBuffer(sampleRate: _sampleRate, preRoll: preRoll, postRoll: postRoll);
    _pending.clear();
    final pcmStream = await _captureService.start();
    _captureSubscription = pcmStream.listen(_onChunk);
  }

  void _onChunk(Uint8List chunk) {
    final buffer = _buffer;
    if (buffer == null) return;
    buffer.append(chunk);
    final ready = _extractReady(buffer, force: false);
    if (ready.isNotEmpty) unawaited(_writeClips(ready));
  }

  @override
  Future<void> tag(CollectionLabel label) async {
    final buffer = _buffer;
    if (buffer == null) return; // not capturing -- screen disables the button, this is a guard
    _pending.add(_PendingTap(label: label, tapIndex: buffer.markTap(), timestamp: DateTime.now()));
  }

  @override
  Future<void> stop() async {
    await _captureSubscription?.cancel();
    _captureSubscription = null;
    await _captureService.stop();

    final buffer = _buffer;
    if (buffer != null) {
      final ready = _extractReady(buffer, force: true);
      await _writeClips(ready);
    }
    _buffer = null;
  }

  @override
  Future<void> undoLast() async {
    if (_written.isEmpty) return;
    final last = _written.removeLast();
    await _clipStore.deleteClip(last.path);
    _counts[last.label] = _counts[last.label]! - 1;
    _emitTally();
  }

  /// Synchronously extracts+removes every pending tap that's ready (or all
  /// of them, if [force] -- the Stop-flush case), slicing each one's clip
  /// bytes out of [buffer] immediately. Must stay synchronous end-to-end:
  /// the buffer keeps evicting old bytes as more audio arrives, so slicing
  /// has to happen before any `await` gives that eviction a chance to run.
  List<_ReadyClip> _extractReady(RollingClipBuffer buffer, {required bool force}) {
    final ready = <_ReadyClip>[];
    _pending.removeWhere((p) {
      if (!force && !buffer.isReady(p.tapIndex)) return false;
      ready.add(
        _ReadyClip(label: p.label, timestamp: p.timestamp, pcmBytes: buffer.sliceClip(p.tapIndex)),
      );
      return true;
    });
    return ready;
  }

  Future<void> _writeClips(List<_ReadyClip> readyClips) async {
    for (final clip in readyClips) {
      final wavBytes = writeWav(clip.pcmBytes, sampleRate: _sampleRate);
      final path = await _clipStore.writeClip(
        label: clip.label,
        wavBytes: wavBytes,
        timestamp: clip.timestamp,
      );
      _written.add(_WrittenClip(label: clip.label, path: path));
      _counts[clip.label] = _counts[clip.label]! + 1;
      _emitTally();
    }
  }

  void _emitTally() => _tallyController.add(currentTally);
}
