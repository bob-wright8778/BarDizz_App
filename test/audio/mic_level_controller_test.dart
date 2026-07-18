import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hockey_shot_tracker/audio/bar_down_detector.dart';
import 'package:hockey_shot_tracker/audio/calibration_profile_store.dart';
import 'package:hockey_shot_tracker/audio/mic_capture_service.dart';
import 'package:hockey_shot_tracker/audio/mic_level_controller.dart';
import 'package:hockey_shot_tracker/audio/shot_detector.dart';
import 'package:hockey_shot_tracker/audio/spectral_profile.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'synthetic_audio.dart';

// Mid-band-dominant, deliberately distinguishable from both
// defaultBarHitSpectralProfile (low-frequency-dominant) and _testEwwProfile
// (high-frequency-dominant) below, so a synthetic chunk built for one
// detector's profile never crosses the other's match threshold.
const _testShotProfile = [0.05, 0.05, 0.70, 0.10, 0.05, 0.05];

// High-frequency-weighted, the opposite end of the spectrum from
// defaultBarHitSpectralProfile's low-frequency-dominant impact shape --
// stands in for a per-user calibrated "Eww" profile (same as
// bar_down_detector_test.dart's synthetic profile).
const _testEwwProfile = [0.02, 0.03, 0.05, 0.10, 0.30, 0.50];

Uint8List _shotChunk() => chunkMatching(_testShotProfile);
Uint8List _barHitChunk() => chunkMatching(defaultBarHitSpectralProfile);
Uint8List _ewwChunk() => chunkMatching(_testEwwProfile);
Uint8List _silence() => silentChunk();

/// Stands in for [MicCaptureService], driven by a controllable PCM stream
/// instead of a real recorder/platform channel.
class _FakeMicCaptureService extends MicCaptureService {
  final StreamController<Uint8List> _pcmController = StreamController<Uint8List>.broadcast();
  bool started = false;
  bool stopped = false;

  @override
  Future<bool> requestPermission() async => true;

  @override
  bool get isCapturing => started && !stopped;

  @override
  Future<Stream<Uint8List>> start() async {
    started = true;
    return _pcmController.stream;
  }

  @override
  Stream<double> amplitudeStream(Stream<Uint8List> pcmStream) => pcmStream.map((_) => 0.0);

  @override
  Future<void> stop() async {
    stopped = true;
  }

  void emit(Uint8List chunk) => _pcmController.add(chunk);
}

/// Flushes pending microtasks/stream deliveries so a just-emitted chunk has
/// been processed by both detector subscriptions before assertions run.
Future<void> _flush() => Future<void>.delayed(Duration.zero);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const mdChannel = MethodChannel('flutter_foreground_task/methods');
  // AudioRecorder() (behind MicCaptureService, never touched by
  // _FakeMicCaptureService's overrides) eagerly calls 'create' on this
  // channel from its constructor -- mocked so merely constructing the fake
  // service doesn't throw MissingPluginException.
  const recordChannel = MethodChannel('com.llfbandit.record/messages');
  late List<MethodCall> mdCalls;
  late bool serviceRunning;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    mdCalls = [];
    serviceRunning = false;
    FlutterForegroundTask.skipServiceResponseCheck = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(mdChannel, (call) async {
      mdCalls.add(call);
      switch (call.method) {
        case 'startService':
          serviceRunning = true;
          return null;
        case 'stopService':
          serviceRunning = false;
          return null;
        case 'isRunningService':
          return serviceRunning;
        case 'checkNotificationPermission':
        case 'requestNotificationPermission':
          return NotificationPermission.granted.index;
        default:
          return null;
      }
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(recordChannel, (call) async => null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(mdChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(recordChannel, null);
    FlutterForegroundTask.resetStatic();
  });

  String? lastNotificationText() {
    final updateCalls = mdCalls.where((c) => c.method == 'updateService');
    if (updateCalls.isEmpty) return null;
    final args = updateCalls.last.arguments as Map;
    return args['notificationContentText'] as String?;
  }

  group('LiveMicLevelController bar-down wiring', () {
    test('shot and bar-down detection run independently on the same stream', () async {
      final capture = _FakeMicCaptureService();
      final controller = LiveMicLevelController(
        captureService: capture,
        shotDetector: ShotDetector(config: const ShotDetectorConfig(referenceProfile: _testShotProfile)),
        barDownDetector: BarDownDetector(
          config: const BarDownDetectorConfig(ewwReferenceProfile: _testEwwProfile),
        ),
      );

      final shotCounts = <int>[];
      final barDownCounts = <int>[];
      controller.shotCount.listen(shotCounts.add);
      controller.barDownCount.listen(barDownCounts.add);

      await controller.start();

      capture.emit(_shotChunk());
      await _flush();
      capture.emit(_barHitChunk());
      await _flush();
      capture.emit(_ewwChunk());
      await _flush();

      expect(shotCounts, [1], reason: 'the shot is its own counted event');
      expect(barDownCounts, [1], reason: 'the bar-hit+Eww is a separate counted event');
    });

    test('a bar-hit with no confirming Eww never increments the bar-down count', () async {
      final capture = _FakeMicCaptureService();
      var now = DateTime(2026);
      final controller = LiveMicLevelController(
        captureService: capture,
        shotDetector: ShotDetector(config: const ShotDetectorConfig(referenceProfile: _testShotProfile)),
        barDownDetector: BarDownDetector(
          config: const BarDownDetectorConfig(ewwReferenceProfile: _testEwwProfile),
          now: () => now,
        ),
      );

      final barDownCounts = <int>[];
      controller.barDownCount.listen(barDownCounts.add);
      await controller.start();

      capture.emit(_barHitChunk());
      await _flush();
      now = now.add(const Duration(seconds: 3));
      capture.emit(_silence());
      await _flush();

      expect(barDownCounts, isEmpty);
    });

    test('the live bar-down count is built from the default bar-hit profile and the persisted Eww profile',
        () async {
      await const CalibrationProfileStore().saveProfile(_testShotProfile);
      await CalibrationProfileStore(key: ewwProfileKey).saveProfile(_testEwwProfile);

      final capture = _FakeMicCaptureService();
      final controller = LiveMicLevelController(captureService: capture);

      final barDownCounts = <int>[];
      controller.barDownCount.listen(barDownCounts.add);
      await controller.start();

      capture.emit(_barHitChunk());
      await _flush();
      capture.emit(_ewwChunk());
      await _flush();

      expect(barDownCounts, [1]);
    });

    test('throws if no Eww calibration profile has been saved', () async {
      await const CalibrationProfileStore().saveProfile(_testShotProfile);
      final capture = _FakeMicCaptureService();
      final controller = LiveMicLevelController(captureService: capture);

      await expectLater(controller.start(), throwsA(isA<StateError>()));
    });

    test('the persistent notification shows both the shot count and the bar-down count', () async {
      final capture = _FakeMicCaptureService();
      final controller = LiveMicLevelController(
        captureService: capture,
        shotDetector: ShotDetector(config: const ShotDetectorConfig(referenceProfile: _testShotProfile)),
        barDownDetector: BarDownDetector(
          config: const BarDownDetectorConfig(ewwReferenceProfile: _testEwwProfile),
        ),
      );

      await controller.start();

      capture.emit(_shotChunk());
      await _flush();
      expect(lastNotificationText(), 'Shots: 1 · Bar Downs: 0');

      capture.emit(_barHitChunk());
      await _flush();
      capture.emit(_ewwChunk());
      await _flush();
      expect(lastNotificationText(), 'Shots: 1 · Bar Downs: 1');
    });
  });
}
