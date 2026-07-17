import 'dart:async';
import 'dart:typed_data';

import 'calibration_profile_store.dart';
import 'mic_capture_service.dart';
import 'mic_foreground_task_handler.dart';
import 'shot_detector.dart';

/// Seam between the debug UI and real mic/foreground-service plumbing, so
/// the UI can be widget-tested with a fake implementation instead of
/// touching platform channels.
abstract class MicLevelController {
  Stream<double> get levels;
  Stream<int> get shotCount;
  bool get isCapturing;
  Future<void> start();
  Future<void> stop();
}

/// Production implementation: requests permission, starts the Android
/// foreground service, then starts raw PCM capture and derives amplitude
/// plus a running detected-shot count.
class LiveMicLevelController implements MicLevelController {
  LiveMicLevelController({
    MicCaptureService? captureService,
    ShotDetector? shotDetector,
    CalibrationProfileStore? profileStore,
  })  : _captureService = captureService ?? MicCaptureService(),
        _injectedShotDetector = shotDetector,
        _profileStore = profileStore ?? const CalibrationProfileStore();

  final MicCaptureService _captureService;
  final ShotDetector? _injectedShotDetector;
  final CalibrationProfileStore _profileStore;
  ShotDetector? _shotDetector;
  final StreamController<double> _levelController =
      StreamController<double>.broadcast();
  final StreamController<int> _shotCountController =
      StreamController<int>.broadcast();
  StreamSubscription<double>? _levelSubscription;
  StreamSubscription<Uint8List>? _shotSubscription;
  int _shotCount = 0;

  @override
  Stream<double> get levels => _levelController.stream;

  @override
  Stream<int> get shotCount => _shotCountController.stream;

  @override
  bool get isCapturing => _captureService.isCapturing;

  @override
  Future<void> start() async {
    final granted = await _captureService.requestPermission();
    if (!granted) {
      throw StateError('Microphone permission denied.');
    }

    if (_injectedShotDetector != null) {
      _shotDetector = _injectedShotDetector;
    } else {
      final profile = await _profileStore.loadProfile();
      if (profile == null) {
        throw StateError('No calibration profile found. Complete calibration first.');
      }
      _shotDetector = ShotDetector(config: ShotDetectorConfig(referenceProfile: profile));
    }

    initMicForegroundTask();
    await ensureNotificationPermission();
    await startMicForegroundService();

    _shotCount = 0;
    final pcmStream = await _captureService.start();
    _levelSubscription =
        _captureService.amplitudeStream(pcmStream).listen(_levelController.add);
    _shotSubscription = pcmStream.listen((chunk) {
      if (_shotDetector!.detect(chunk)) {
        _shotCount++;
        _shotCountController.add(_shotCount);
        updateMicForegroundNotificationCount(_shotCount);
      }
    });
  }

  @override
  Future<void> stop() async {
    await _levelSubscription?.cancel();
    _levelSubscription = null;
    await _shotSubscription?.cancel();
    _shotSubscription = null;
    await _captureService.stop();
    await stopMicForegroundService();
  }
}
