import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hockey_shot_tracker/audio/classifier_detector.dart';
import 'package:hockey_shot_tracker/audio/mic_capture_service.dart';
import 'package:hockey_shot_tracker/audio/mic_level_controller.dart';

import 'synthetic_audio.dart';

/// Deterministic stand-in for the real 200-tree classifier, keyed off a
/// chunk's amplitude so test chunks (built via [sineWave]'s amplitude
/// parameter) can pick a specific label without depending on real Goertzel
/// band shaping -- mirrors [classifier_detector_test.dart]'s `_FakeClassifier`
/// but as a plain function, since these tests only need one fixed rule, not
/// a call-ordered sequence.
// A sine wave's RMS amplitude tops out at peak/sqrt(2) (~0.707), so these
// thresholds are picked to fall well inside that reachable range (peaks of
// 0.95/0.6/0.35 below give RMS ~0.67/~0.42/~0.25 respectively) rather than at
// round fractions of 1.0, which a sine chunk could never actually reach.
String _fakeClassify(List<double> features) {
  final amplitude = features[6];
  if (amplitude > 0.55) return 'shot';
  if (amplitude > 0.35) return 'bar-hit';
  if (amplitude > 0.15) return 'eww';
  return 'background-quiet';
}

Uint8List _shotChunk() => sineWave([const MapEntry(1000.0, 0.95)]);
Uint8List _barHitChunk() => sineWave([const MapEntry(1000.0, 0.6)]);
Uint8List _ewwChunk() => sineWave([const MapEntry(1000.0, 0.35)]);
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
/// been processed by the detector before assertions run.
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

  // windowDuration matches one emitted chunk (sineWave's default 320
  // samples/20ms @16kHz), so every `emit` completes and classifies exactly
  // one window, mirroring the old tests' one-chunk-per-emit convention.
  ClassifierDetector buildDetector(DateTime Function() now) => ClassifierDetector(
    config: const ClassifierDetectorConfig(windowDuration: Duration(milliseconds: 20)),
    now: now,
    classify: _fakeClassify,
  );

  group('LiveMicLevelController classifier wiring', () {
    test('a shot classification increments the shot count', () async {
      final capture = _FakeMicCaptureService();
      var now = DateTime(2026);
      final controller = LiveMicLevelController(captureService: capture, detector: buildDetector(() => now));

      final shotCounts = <int>[];
      controller.shotCount.listen(shotCounts.add);
      await controller.start();

      capture.emit(_shotChunk());
      await _flush();

      expect(shotCounts, [1]);
    });

    test('a bar-hit followed by a confirming eww increments the bar-down count, not the shot count', () async {
      final capture = _FakeMicCaptureService();
      var now = DateTime(2026);
      final controller = LiveMicLevelController(captureService: capture, detector: buildDetector(() => now));

      final shotCounts = <int>[];
      final barDownCounts = <int>[];
      controller.shotCount.listen(shotCounts.add);
      controller.barDownCount.listen(barDownCounts.add);
      await controller.start();

      capture.emit(_barHitChunk());
      await _flush();
      now = now.add(const Duration(milliseconds: 300)); // past the 250ms refractory
      capture.emit(_ewwChunk());
      await _flush();

      expect(barDownCounts, [1]);
      expect(shotCounts, isEmpty);
    });

    test('shot and bar-down detection both run over the same stream', () async {
      final capture = _FakeMicCaptureService();
      var now = DateTime(2026);
      final controller = LiveMicLevelController(captureService: capture, detector: buildDetector(() => now));

      final shotCounts = <int>[];
      final barDownCounts = <int>[];
      controller.shotCount.listen(shotCounts.add);
      controller.barDownCount.listen(barDownCounts.add);
      await controller.start();

      capture.emit(_shotChunk());
      await _flush();
      now = now.add(const Duration(milliseconds: 300));
      capture.emit(_barHitChunk());
      await _flush();
      now = now.add(const Duration(milliseconds: 300));
      capture.emit(_ewwChunk());
      await _flush();

      expect(shotCounts, [1], reason: 'the shot is its own counted event');
      expect(barDownCounts, [1], reason: 'the bar-hit+eww is a separate counted event');
    });

    test('a bar-hit with no confirming eww before the confirm window expires never counts', () async {
      final capture = _FakeMicCaptureService();
      var now = DateTime(2026);
      final controller = LiveMicLevelController(captureService: capture, detector: buildDetector(() => now));

      final barDownCounts = <int>[];
      controller.barDownCount.listen(barDownCounts.add);
      await controller.start();

      capture.emit(_barHitChunk());
      await _flush();
      now = now.add(const Duration(seconds: 3)); // past the 2s confirm window
      capture.emit(_ewwChunk());
      await _flush();

      expect(barDownCounts, isEmpty);
    });

    test('background-quiet classifications (e.g. silence) never count as anything', () async {
      final capture = _FakeMicCaptureService();
      var now = DateTime(2026);
      final controller = LiveMicLevelController(captureService: capture, detector: buildDetector(() => now));

      final shotCounts = <int>[];
      final barDownCounts = <int>[];
      controller.shotCount.listen(shotCounts.add);
      controller.barDownCount.listen(barDownCounts.add);
      await controller.start();

      capture.emit(_silence());
      await _flush();

      expect(shotCounts, isEmpty);
      expect(barDownCounts, isEmpty);
    });

    test('the persistent notification shows both the shot count and the bar-down count', () async {
      final capture = _FakeMicCaptureService();
      var now = DateTime(2026);
      final controller = LiveMicLevelController(captureService: capture, detector: buildDetector(() => now));
      await controller.start();

      capture.emit(_shotChunk());
      await _flush();
      expect(lastNotificationText(), 'Shots: 1 · Bar Downs: 0');

      now = now.add(const Duration(milliseconds: 300));
      capture.emit(_barHitChunk());
      await _flush();
      expect(lastNotificationText(), 'Shots: 1 · Bar Downs: 0', reason: 'a lone bar-hit does not update the notification');

      now = now.add(const Duration(milliseconds: 300));
      capture.emit(_ewwChunk());
      await _flush();
      expect(lastNotificationText(), 'Shots: 1 · Bar Downs: 1');
    });

    test('a default LiveMicLevelController (no detector injected) starts without requiring any calibration profile',
        () async {
      final capture = _FakeMicCaptureService();
      final controller = LiveMicLevelController(captureService: capture);

      await controller.start();

      expect(controller.isCapturing, isTrue);
    });
  });
}
