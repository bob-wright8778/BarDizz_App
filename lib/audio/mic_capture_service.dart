import 'dart:async';
import 'dart:typed_data';

import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

import 'amplitude.dart';
import 'audio_constants.dart';

/// Continuously captures raw PCM16 mic audio and exposes it as both the raw
/// byte stream (for future shot-detection ticket) and a derived amplitude
/// stream (for the debug meter in this ticket).
class MicCaptureService {
  MicCaptureService({AudioRecorder? recorder})
      : _recorder = recorder ?? AudioRecorder();

  final AudioRecorder _recorder;
  StreamController<Uint8List>? _pcmController;
  StreamSubscription<Uint8List>? _recorderSubscription;

  /// Requests the OS microphone permission, returning whether it was granted.
  Future<bool> requestPermission() async {
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  bool get isCapturing => _pcmController != null;

  /// Starts continuous raw PCM16 capture. Safe to call once; call [stop]
  /// before starting again. Returns the raw PCM byte chunk stream.
  Future<Stream<Uint8List>> start() async {
    if (_pcmController != null) return _pcmController!.stream;

    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      throw StateError('Microphone permission not granted.');
    }

    final controller = StreamController<Uint8List>.broadcast();
    _pcmController = controller;

    final source = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: micSampleRate,
        numChannels: 1,
      ),
    );
    _recorderSubscription = source.listen(
      controller.add,
      onError: controller.addError,
      onDone: controller.close,
    );

    return controller.stream;
  }

  /// Raw PCM chunk stream mapped to a normalized 0.0-1.0 amplitude reading
  /// per chunk, for driving a live level meter.
  Stream<double> amplitudeStream(Stream<Uint8List> pcmStream) {
    return pcmStream.map(computeAmplitude);
  }

  Future<void> stop() async {
    await _recorderSubscription?.cancel();
    _recorderSubscription = null;
    await _pcmController?.close();
    _pcmController = null;
    await _recorder.stop();
  }

  Future<void> dispose() async {
    await stop();
    await _recorder.dispose();
  }
}
