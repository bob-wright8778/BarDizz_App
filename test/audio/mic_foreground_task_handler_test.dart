import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hockey_shot_tracker/audio/mic_foreground_task_handler.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const mdChannel = MethodChannel('flutter_foreground_task/methods');
  late List<MethodCall> calls;
  late bool serviceRunning;

  setUp(() {
    calls = [];
    serviceRunning = false;
    FlutterForegroundTask.skipServiceResponseCheck = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(mdChannel, (call) async {
      calls.add(call);
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
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(mdChannel, null);
    FlutterForegroundTask.resetStatic();
  });

  group('updateMicForegroundNotificationCounts', () {
    test('sends both the shot count and the bar-down count in the notification text', () async {
      initMicForegroundTask();
      await startMicForegroundService();

      await updateMicForegroundNotificationCounts(shots: 3, barDowns: 1);

      final updateCall = calls.singleWhere((c) => c.method == 'updateService');
      final args = updateCall.arguments as Map;
      expect(args['notificationContentText'], 'Shots: 3 · Bar Downs: 1');
    });

    test('reflects a zero bar-down count the same way as a nonzero one', () async {
      initMicForegroundTask();
      await startMicForegroundService();

      await updateMicForegroundNotificationCounts(shots: 5, barDowns: 0);

      final updateCall = calls.singleWhere((c) => c.method == 'updateService');
      final args = updateCall.arguments as Map;
      expect(args['notificationContentText'], 'Shots: 5 · Bar Downs: 0');
    });
  });

  group('startMicForegroundService', () {
    test('the initial notification text mentions both shots and bar downs', () async {
      initMicForegroundTask();
      await startMicForegroundService();

      final startCall = calls.singleWhere((c) => c.method == 'startService');
      final args = startCall.arguments as Map;
      expect(args['notificationContentText'], contains('shots'));
      expect(args['notificationContentText'], contains('bar down'));
    });
  });
}
