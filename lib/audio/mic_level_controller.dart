import 'dart:async';
import 'dart:typed_data';

import 'classifier_detector.dart';
import 'mic_capture_service.dart';
import 'mic_foreground_task_handler.dart';

/// Seam between the debug UI and real mic/foreground-service plumbing, so
/// the UI can be widget-tested with a fake implementation instead of
/// touching platform channels.
abstract class MicLevelController {
  Stream<double> get levels;
  Stream<int> get shotCount;
  Stream<int> get barDownCount;
  bool get isCapturing;
  Future<void> start();
  Future<void> stop();
}

/// Production implementation: requests permission, starts the Android
/// foreground service, then starts raw PCM capture and drives one
/// [ClassifierDetector] over the stream, translating its classified events
/// into running shot/bar-down counts. Unlike the old amplitude+spectral-
/// template `ShotDetector`/`BarDownDetector` pair (two independent state
/// machines over the same stream), a single classifier window is open at a
/// time -- see `classifier_detector.dart`'s doc comment for why that's an
/// intentional simplification, not an oversight.
class LiveMicLevelController implements MicLevelController {
  LiveMicLevelController({
    MicCaptureService? captureService,
    ClassifierDetector? detector,
  })  : _captureService = captureService ?? MicCaptureService(),
        _detector = detector ?? ClassifierDetector();

  final MicCaptureService _captureService;
  final ClassifierDetector _detector;
  final StreamController<double> _levelController =
      StreamController<double>.broadcast();
  final StreamController<int> _shotCountController =
      StreamController<int>.broadcast();
  final StreamController<int> _barDownCountController =
      StreamController<int>.broadcast();
  StreamSubscription<double>? _levelSubscription;
  StreamSubscription<Uint8List>? _detectionSubscription;
  int _shotCount = 0;
  int _barDownCount = 0;

  @override
  Stream<double> get levels => _levelController.stream;

  @override
  Stream<int> get shotCount => _shotCountController.stream;

  @override
  Stream<int> get barDownCount => _barDownCountController.stream;

  @override
  bool get isCapturing => _captureService.isCapturing;

  @override
  Future<void> start() async {
    final granted = await _captureService.requestPermission();
    if (!granted) {
      throw StateError('Microphone permission denied.');
    }

    initMicForegroundTask();
    await ensureNotificationPermission();
    await startMicForegroundService();

    _shotCount = 0;
    _barDownCount = 0;
    final pcmStream = await _captureService.start();
    _levelSubscription =
        _captureService.amplitudeStream(pcmStream).listen(_levelController.add);
    _detectionSubscription = pcmStream.listen(_onChunk);
  }

  void _onChunk(Uint8List chunk) {
    final event = _detector.detect(chunk);
    if (event == null) return;

    switch (event) {
      case ClassifiedEvent.shot:
        _shotCount++;
        _shotCountController.add(_shotCount);
      case ClassifiedEvent.barDown:
        _barDownCount++;
        _barDownCountController.add(_barDownCount);
    }
    updateMicForegroundNotificationCounts(shots: _shotCount, barDowns: _barDownCount);
  }

  @override
  Future<void> stop() async {
    await _levelSubscription?.cancel();
    _levelSubscription = null;
    await _detectionSubscription?.cancel();
    _detectionSubscription = null;
    await _captureService.stop();
    await stopMicForegroundService();
  }
}
