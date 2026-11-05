import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
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

  /// The next camera frame at full resolution, as the sensor delivers it
  /// (not yet rotated upright), or `null` if the camera isn't running --
  /// for calibration, where a sharper puck means a better size measurement.
  Future<LumaFrame?> captureStill();

  /// Best guess at the clockwise quarter turns that make [captureStill]'s
  /// frames upright for how the phone is currently standing.
  int get suggestedQuarterTurns;

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
  Completer<LumaFrame?>? _stillRequest;

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
  Future<LumaFrame?> captureStill() {
    final camera = _camera;
    if (camera == null || !camera.value.isStreamingImages) return Future.value(null);
    return (_stillRequest ??= Completer<LumaFrame?>()).future;
  }

  @override
  int get suggestedQuarterTurns {
    final camera = _camera;
    if (camera == null) return 0;
    // The sensor is mounted at sensorOrientation degrees; a back camera's
    // frame needs that much clockwise rotation, less however far the phone
    // itself is turned, to come out upright.
    final device = switch (camera.value.deviceOrientation) {
      DeviceOrientation.portraitUp => 0,
      DeviceOrientation.landscapeLeft => 90,
      DeviceOrientation.portraitDown => 180,
      DeviceOrientation.landscapeRight => 270,
    };
    final sensor = camera.description.sensorOrientation;
    final degrees = camera.description.lensDirection == CameraLensDirection.front
        ? (sensor + device) % 360
        : (sensor - device + 360) % 360;
    return degrees ~/ 90;
  }

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
    final still = _stillRequest;
    if (still != null) {
      _stillRequest = null;
      still.complete(downsampleLuma(
        y.bytes,
        width: image.width,
        height: image.height,
        bytesPerRow: y.bytesPerRow,
        targetWidth: image.width,
      ));
    }

    final tracker = _tracker;
    if (tracker == null) return;
    final frame = rotateLuma(
      downsampleLuma(y.bytes, width: image.width, height: image.height, bytesPerRow: y.bytesPerRow),
      tracker.calibration.quarterTurns,
    );
    final shot = tracker.addFrame(frame, DateTime.now());
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
    _stillRequest?.complete(null);
    _stillRequest = null;
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
