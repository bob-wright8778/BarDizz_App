import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hockey_shot_tracker/audio/collection_label.dart';
import 'package:hockey_shot_tracker/audio/clip_store.dart';
import 'package:hockey_shot_tracker/audio/data_collection_controller.dart';
import 'package:hockey_shot_tracker/audio/mic_capture_service.dart';

/// Stands in for [MicCaptureService], driven by a controllable PCM stream --
/// same pattern as mic_level_controller_test.dart's _FakeMicCaptureService.
class _FakeMicCaptureService extends MicCaptureService {
  final StreamController<Uint8List> _pcmController = StreamController<Uint8List>.broadcast();
  bool started = false;
  bool stopped = false;
  bool permissionGranted = true;

  @override
  Future<bool> requestPermission() async => permissionGranted;

  @override
  bool get isCapturing => started && !stopped;

  @override
  Future<Stream<Uint8List>> start() async {
    started = true;
    return _pcmController.stream;
  }

  @override
  Future<void> stop() async {
    stopped = true;
  }

  void emit(Uint8List chunk) => _pcmController.add(chunk);
}

class RecordedWrite {
  RecordedWrite(this.label, this.wavBytes, this.timestamp);
  final CollectionLabel label;
  final Uint8List wavBytes;
  final DateTime timestamp;
}

class FakeClipStore implements ClipStore {
  final List<RecordedWrite> writes = [];
  final List<String> deletedPaths = [];
  int _nextId = 0;

  @override
  Future<String> writeClip({
    required CollectionLabel label,
    required Uint8List wavBytes,
    required DateTime timestamp,
  }) async {
    writes.add(RecordedWrite(label, wavBytes, timestamp));
    return 'fake/${label.folderName}_${_nextId++}.wav';
  }

  @override
  Future<void> deleteClip(String path) async {
    deletedPaths.add(path);
  }
}

Uint8List _chunk(int sampleCount) => Uint8List(sampleCount * 2);

/// Flushes pending microtasks so a fire-and-forget clip write completes
/// before assertions run.
Future<void> _flush() => Future<void>.delayed(Duration.zero);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // AudioRecorder() (behind MicCaptureService, never touched by
  // _FakeMicCaptureService's overrides) eagerly calls 'create' on this
  // channel from its constructor -- mocked so merely constructing the fake
  // service doesn't throw MissingPluginException. Same as
  // mic_level_controller_test.dart.
  const recordChannel = MethodChannel('com.llfbandit.record/messages');

  late _FakeMicCaptureService captureService;
  late FakeClipStore clipStore;
  late LiveDataCollectionController controller;

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(recordChannel, (call) async => null);
    captureService = _FakeMicCaptureService();
    clipStore = FakeClipStore();
    controller = LiveDataCollectionController(
      captureService: captureService,
      clipStore: clipStore,
      preRoll: const Duration(milliseconds: 100),
      postRoll: const Duration(milliseconds: 100),
      sampleRate: 1000, // 100 samples/100ms, easy round numbers
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(recordChannel, null);
  });

  test('start() requests permission and begins capture', () async {
    await controller.start();

    expect(captureService.started, isTrue);
    expect(controller.isCapturing, isTrue);
  });

  test('start() throws when permission is denied', () async {
    captureService.permissionGranted = false;

    expect(() => controller.start(), throwsStateError);
  });

  test('tagging an event writes a clip once post-roll audio arrives, and updates the tally',
      () async {
    await controller.start();
    captureService.emit(_chunk(100)); // 100ms of pre-roll history
    await _flush();

    await controller.tag(CollectionLabel.barHit);
    expect(clipStore.writes, isEmpty, reason: 'post-roll has not arrived yet');

    captureService.emit(_chunk(100)); // 100ms post-roll arrives
    await _flush();

    expect(clipStore.writes, hasLength(1));
    expect(clipStore.writes.single.label, CollectionLabel.barHit);
    expect(controller.currentTally.countFor(CollectionLabel.barHit), 1);
  });

  test('stop() flushes a clip still waiting on post-roll using whatever arrived', () async {
    await controller.start();
    captureService.emit(_chunk(100));
    await _flush();
    await controller.tag(CollectionLabel.eww);
    captureService.emit(_chunk(30)); // only partial post-roll before Stop
    await _flush();

    await controller.stop();

    expect(clipStore.writes, hasLength(1));
    expect(clipStore.writes.single.label, CollectionLabel.eww);
    expect(controller.currentTally.countFor(CollectionLabel.eww), 1);
  });

  test('undoLast deletes the most recently written clip and decrements its tally', () async {
    await controller.start();
    captureService.emit(_chunk(100));
    await _flush();
    await controller.tag(CollectionLabel.shot);
    captureService.emit(_chunk(100));
    await _flush();
    expect(controller.currentTally.countFor(CollectionLabel.shot), 1);
    expect(controller.currentTally.canUndo, isTrue);

    await controller.undoLast();

    expect(clipStore.deletedPaths, hasLength(1));
    expect(controller.currentTally.countFor(CollectionLabel.shot), 0);
    expect(controller.currentTally.canUndo, isFalse);
  });

  test('undoLast is a no-op when nothing has been recorded yet', () async {
    await controller.start();

    await controller.undoLast();

    expect(clipStore.deletedPaths, isEmpty);
  });

  test('tagging two labels close together produces two independent clips', () async {
    await controller.start();
    captureService.emit(_chunk(100));
    await _flush();

    await controller.tag(CollectionLabel.barHit);
    captureService.emit(_chunk(30));
    await _flush();
    await controller.tag(CollectionLabel.eww);
    captureService.emit(_chunk(100));
    await _flush();

    expect(clipStore.writes.map((w) => w.label), [CollectionLabel.barHit, CollectionLabel.eww]);
  });
}
