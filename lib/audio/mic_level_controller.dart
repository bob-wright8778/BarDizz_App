import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'audio_constants.dart';
import 'bar_down_detector.dart';
import 'calibration_profile_store.dart';
import 'mic_capture_service.dart';
import 'mic_foreground_task_handler.dart';
import 'shot_detector.dart';
import 'spectral_profile.dart';

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
/// foreground service, then starts raw PCM capture and derives amplitude
/// plus running detected-shot and detected-bar-down counts. Shot and
/// bar-down detection run as two independent state machines over the same
/// audio stream -- a shot and a later bar-hit+Eww from the same physical
/// puck strike are both counted, not merged.
class LiveMicLevelController implements MicLevelController {
  LiveMicLevelController({
    MicCaptureService? captureService,
    ShotDetector? shotDetector,
    BarDownDetector? barDownDetector,
    CalibrationProfileStore? profileStore,
    CalibrationProfileStore? ewwProfileStore,
  })  : _captureService = captureService ?? MicCaptureService(),
        _injectedShotDetector = shotDetector,
        _injectedBarDownDetector = barDownDetector,
        _profileStore = profileStore ?? const CalibrationProfileStore(),
        _ewwProfileStore = ewwProfileStore ?? const CalibrationProfileStore(key: ewwProfileKey);

  final MicCaptureService _captureService;
  final ShotDetector? _injectedShotDetector;
  final BarDownDetector? _injectedBarDownDetector;
  final CalibrationProfileStore _profileStore;
  final CalibrationProfileStore _ewwProfileStore;
  ShotDetector? _shotDetector;
  BarDownDetector? _barDownDetector;
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

    if (_injectedShotDetector != null) {
      _shotDetector = _injectedShotDetector;
    } else {
      final profile = await _profileStore.loadProfile();
      if (profile == null) {
        throw StateError('No calibration profile found. Complete calibration first.');
      }
      _shotDetector = ShotDetector(config: ShotDetectorConfig(referenceProfile: profile));
    }

    if (_injectedBarDownDetector != null) {
      _barDownDetector = _injectedBarDownDetector;
    } else {
      final ewwProfile = await _ewwProfileStore.loadProfile();
      if (ewwProfile == null) {
        throw StateError('No Eww calibration profile found. Complete calibration first.');
      }
      _barDownDetector = BarDownDetector(
        config: BarDownDetectorConfig(ewwReferenceProfile: ewwProfile),
      );
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

  // Shot and bar-down detection are two independent state machines, but both
  // run against the same chunk -- computing amplitude/spectral profile once
  // here and sharing them (ShotDetector/BarDownDetector.detectFromFeatures)
  // avoids redoing that analysis for every chunk a live session processes.
  void _onChunk(Uint8List chunk) {
    final minThreshold = math.min(
      _shotDetector!.config.amplitudeThreshold,
      math.min(_barDownDetector!.config.barHitAmplitudeThreshold, _barDownDetector!.config.ewwAmplitudeThreshold),
    );
    final features = computeChunkFeatures(chunk, amplitudeThreshold: minThreshold, sampleRate: micSampleRate);

    if (_shotDetector!.detectFromFeatures(features.amplitude, features.profile)) {
      _shotCount++;
      _shotCountController.add(_shotCount);
      updateMicForegroundNotificationCounts(shots: _shotCount, barDowns: _barDownCount);
    }
    if (_barDownDetector!.detectFromFeatures(features.amplitude, features.profile)) {
      _barDownCount++;
      _barDownCountController.add(_barDownCount);
      updateMicForegroundNotificationCounts(shots: _shotCount, barDowns: _barDownCount);
    }
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
