import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../audio/classifier_detector.dart';
import '../audio/mic_level_controller.dart';
import '../settings/eww_always_bar_down_store.dart';
import '../settings/video_settings_store.dart';
import 'luma_frame.dart';
import 'shot_fusion.dart';
import 'shot_tracker.dart';
import 'video_calibration.dart';

/// How a running session is counting shots.
enum ShotSource {
  /// Camera detects the shot; the mic confirms it (or not, per settings).
  video,

  /// No usable camera setup (not calibrated, or camera unavailable): the
  /// sound classifier counts shots on its own, as before video existed.
  soundOnly,
}

/// What the session screen needs from the camera side, separate from the
/// counting streams on [MicLevelController], so it can be faked in tests.
abstract class VideoShotFeed {
  /// Every counted shot with its camera analysis.
  Stream<ShotAnalysis> get analyses;

  /// How shots are being counted in the current session.
  ValueListenable<ShotSource> get source;

  /// The latest analysis-grid frame while the camera runs, for calibration.
  ValueListenable<LumaFrame?> get latestFrame;

  VideoCalibration? get calibration;

  /// Applies and persists a new calibration; takes effect on the next frame.
  Future<void> setCalibration(VideoCalibration calibration);

  /// A live camera preview while the camera runs, else `null`.
  Widget? buildPreview();
}

/// Production session controller: a back-camera [ShotTracker] decides when
/// a shot happened, the existing mic pipeline ([LiveMicLevelController])
/// confirms it with a stick impact and still detects bar-downs (bar ping +
/// "Eww"). Falls back to sound-only counting when the camera is
/// uncalibrated or unavailable.
class LiveVideoShotController implements MicLevelController, VideoShotFeed {
  LiveVideoShotController({
    EwwAlwaysBarDownGetter ewwAlwaysBarDown = ewwAlwaysBarDownDefaultGetter,
    bool Function() requireSound = _requireSoundDefault,
    this.store = const VideoSettingsStore(),
  })  : _audio = LiveMicLevelController(ewwAlwaysBarDown: ewwAlwaysBarDown),
        _requireSound = requireSound;

  static bool _requireSoundDefault() => requireSoundDefault;

  final VideoSettingsStore store;
  final LiveMicLevelController _audio;
  final bool Function() _requireSound;

  final StreamController<int> _shotCountController = StreamController<int>.broadcast();
  final StreamController<ShotAnalysis> _analysisController =
      StreamController<ShotAnalysis>.broadcast();
  final ValueNotifier<ShotSource> _source = ValueNotifier(ShotSource.soundOnly);
  final ValueNotifier<LumaFrame?> _latestFrame = ValueNotifier(null);

  CameraController? _camera;
  VideoCalibration? _calibration;
  ShotTracker? _tracker;
  ShotFusion _fusion = ShotFusion();
  bool _audioRunning = false;
  int _shotCount = 0;
  final List<StreamSubscription<Object?>> _subscriptions = [];

  @override
  Stream<double> get levels => _audio.levels;

  @override
  Stream<int> get shotCount => _shotCountController.stream;

  @override
  Stream<int> get barDownCount => _audio.barDownCount;

  @override
  bool get isCapturing => _audioRunning || (_camera?.value.isStreamingImages ?? false);

  @override
  Stream<ShotAnalysis> get analyses => _analysisController.stream;

  @override
  ValueListenable<ShotSource> get source => _source;

  @override
  ValueListenable<LumaFrame?> get latestFrame => _latestFrame;

  @override
  VideoCalibration? get calibration => _calibration;

  @override
  Future<void> setCalibration(VideoCalibration calibration) async {
    _calibration = calibration;
    _tracker = ShotTracker(calibration);
    await store.saveCalibration(calibration);
    if (_camera != null) _source.value = ShotSource.video;
  }

  @override
  Widget? buildPreview() {
    final camera = _camera;
    if (camera == null || !camera.value.isInitialized) return null;
    return CameraPreview(camera);
  }

  @override
  Future<void> start() async {
    _shotCount = 0;
    _calibration = await store.loadCalibration();
    final calibration = _calibration;
    _tracker = calibration == null ? null : ShotTracker(calibration);

    // Mic first: it still finds bar-downs, and is the whole show if the
    // camera can't run. Its permission error only matters if the camera
    // also fails.
    Object? audioError;
    try {
      await _audio.start();
      _audioRunning = true;
    } catch (e) {
      audioError = e;
    }
    _fusion = ShotFusion(
      config: ShotFusionConfig(requireSound: _audioRunning && _requireSound()),
    );

    try {
      await _startCamera();
    } catch (e) {
      if (!_audioRunning) throw audioError ?? e;
      _camera = null;
    }

    _source.value =
        (_camera != null && _tracker != null) ? ShotSource.video : ShotSource.soundOnly;
    _subscriptions
      ..add(_audio.levels.listen((level) => _fusion.addAudioLevel(level, DateTime.now())))
      ..add(_audio.shotCount.listen(_onSoundShot));
    unawaited(WakelockPlus.enable());
  }

  Future<void> _startCamera() async {
    final cameras = await availableCameras();
    final back = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );
    final camera = CameraController(
      back,
      // ~720x480: plenty once shrunk to the analysis grid, and cheap enough
      // to process every frame on the UI isolate.
      ResolutionPreset.medium,
      enableAudio: false,
      // A hard shot crosses the frame in a few frames even at 60 fps; ask
      // for it and take what the device gives.
      fps: 60,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );
    _camera = camera;
    await camera.initialize();
    await camera.startImageStream(_onImage);
  }

  // Runs synchronously per frame on the UI isolate. Only the Y (luma)
  // plane is read: a black puck on a light pad needs no colour.
  void _onImage(CameraImage image) {
    final y = image.planes.first;
    final frame = downsampleLuma(
      y.bytes,
      width: image.width,
      height: image.height,
      bytesPerRow: y.bytesPerRow,
    );
    _latestFrame.value = frame;
    final shot = _tracker?.addFrame(frame, DateTime.now());
    if (shot != null && _source.value == ShotSource.video) _onVideoShot(shot);
  }

  void _onVideoShot(VideoShot shot) {
    final analysis = _fusion.addVideoShot(shot);
    if (analysis == null) return;
    _shotCount++;
    _shotCountController.add(_shotCount);
    _analysisController.add(analysis);
  }

  void _onSoundShot(int _) {
    if (_source.value != ShotSource.soundOnly) return;
    _shotCount++;
    _shotCountController.add(_shotCount);
  }

  @override
  Future<void> stop() async {
    for (final s in _subscriptions) {
      await s.cancel();
    }
    _subscriptions.clear();
    final camera = _camera;
    _camera = null;
    _latestFrame.value = null;
    if (camera != null) {
      if (camera.value.isStreamingImages) await camera.stopImageStream();
      await camera.dispose();
    }
    if (_audioRunning) {
      _audioRunning = false;
      await _audio.stop();
    }
    unawaited(WakelockPlus.disable());
  }
}
