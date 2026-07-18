import 'dart:async';
import 'dart:typed_data';

import 'amplitude.dart';
import 'calibration_profile.dart';
import 'calibration_profile_store.dart';
import 'mic_capture_service.dart';
import 'spectral_profile.dart';

/// Which reference profile the wizard is currently recording samples for.
/// The flow always runs [shot] to completion before moving to [eww].
enum CalibrationStage { shot, eww }

/// Seam between the calibration UI and real mic-capture plumbing, so the UI
/// can be widget-tested with a fake implementation instead of touching
/// platform channels.
abstract class CalibrationController {
  int get targetSamples;
  CalibrationStage get stage;
  Stream<int> get samplesRecorded;

  /// Live mic amplitude (0.0-1.0) while listening for a sample, so the UI
  /// can prove capture is active and the user can judge their volume
  /// against [amplitudeThreshold].
  Stream<double> get levels;
  double get amplitudeThreshold;
  Future<void> start();
  Future<void> recordSample();
  Future<void> finish();
  Future<void> cancel();
}

/// Production implementation: captures raw mic audio, waits for a
/// loud-enough transient per sample shot, and derives + saves a reference
/// spectral profile from the recorded samples.
class LiveCalibrationController implements CalibrationController {
  LiveCalibrationController({
    MicCaptureService? captureService,
    CalibrationProfileStore? profileStore,
    CalibrationProfileStore? ewwProfileStore,
    this.targetSamples = 5,
    // Lower than ShotDetectorConfig's 0.35: real-device testing showed a
    // deliberate clap only reaching ~0.10 through this mic pipeline (likely
    // AGC/noise suppression flattening transients), so 0.35 never triggers.
    // Independent of the production detector's own threshold, which still
    // needs real stick-puck recordings to tune properly (ticket 02 AC 5/6).
    this.amplitudeThreshold = 0.06,
  })  : _captureService = captureService ?? MicCaptureService(),
        _profileStore = profileStore ?? const CalibrationProfileStore(),
        _ewwProfileStore = ewwProfileStore ?? const CalibrationProfileStore(key: ewwProfileKey);

  @override
  final int targetSamples;
  @override
  final double amplitudeThreshold;
  final MicCaptureService _captureService;
  final CalibrationProfileStore _profileStore;
  final CalibrationProfileStore _ewwProfileStore;
  final StreamController<int> _samplesController = StreamController<int>.broadcast();
  final StreamController<double> _levelsController = StreamController<double>.broadcast();
  final List<List<double>> _shotProfiles = [];
  final List<List<double>> _ewwProfiles = [];
  Stream<Uint8List>? _pcmStream;
  StreamSubscription<double>? _levelSubscription;

  @override
  CalibrationStage stage = CalibrationStage.shot;

  @override
  Stream<int> get samplesRecorded => _samplesController.stream;

  @override
  Stream<double> get levels => _levelsController.stream;

  @override
  Future<void> start() async {
    final granted = await _captureService.requestPermission();
    if (!granted) {
      throw StateError('Microphone permission denied.');
    }
    final stream = await _captureService.start();
    _pcmStream = stream;
    _levelSubscription =
        _captureService.amplitudeStream(stream).listen(_levelsController.add);
  }

  @override
  Future<void> recordSample() async {
    final stream = _pcmStream;
    if (stream == null) {
      throw StateError('Call start() before recording samples.');
    }
    final profiles = stage == CalibrationStage.shot ? _shotProfiles : _ewwProfiles;
    if (profiles.length >= targetSamples) return;

    final chunk = await stream.firstWhere((c) => computeAmplitude(c) >= amplitudeThreshold);
    profiles.add(computeSpectralProfile(chunk));

    if (stage == CalibrationStage.shot && _shotProfiles.length >= targetSamples) {
      stage = CalibrationStage.eww;
      _samplesController.add(0);
    } else {
      _samplesController.add(profiles.length);
    }
  }

  @override
  Future<void> finish() async {
    final shotProfile = deriveReferenceProfile(_shotProfiles);
    final ewwProfile = deriveReferenceProfile(_ewwProfiles);
    await _profileStore.saveProfile(shotProfile);
    await _ewwProfileStore.saveProfile(ewwProfile);
    await _stopCapture();
  }

  @override
  Future<void> cancel() async {
    await _stopCapture();
  }

  Future<void> _stopCapture() async {
    await _levelSubscription?.cancel();
    _levelSubscription = null;
    await _captureService.stop();
    _pcmStream = null;
  }
}
