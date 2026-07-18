import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// Keeps the Android foreground service (type: microphone) alive so the
/// process — and the mic stream it hosts — isn't killed while backgrounded
/// or the screen is locked. The actual PCM capture runs via
/// [MicCaptureService] on the main isolate; this handler only owns the
/// persistent notification/service lifecycle Android requires for it.
class MicForegroundTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}
}

/// One-time notification channel/options setup. Call before starting the
/// service.
void initMicForegroundTask() {
  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      channelId: 'hockey_shot_tracker_mic',
      channelName: 'Shot detection microphone',
      channelDescription:
          'Keeps microphone capture running while the app is backgrounded.',
      channelImportance: NotificationChannelImportance.LOW,
      priority: NotificationPriority.LOW,
    ),
    iosNotificationOptions: const IOSNotificationOptions(),
    foregroundTaskOptions: ForegroundTaskOptions(
      eventAction: ForegroundTaskEventAction.repeat(5000),
      autoRunOnBoot: false,
      allowWakeLock: true,
      allowWifiLock: false,
    ),
  );
}

/// Requests the separate Android 13+ runtime notification permission —
/// without it the foreground service still runs, but its ongoing
/// notification silently never posts, leaving the user with no visibility
/// that background listening is happening.
Future<void> ensureNotificationPermission() async {
  final permission = await FlutterForegroundTask.checkNotificationPermission();
  if (permission != NotificationPermission.granted) {
    await FlutterForegroundTask.requestNotificationPermission();
  }
}

Future<void> startMicForegroundService() {
  return FlutterForegroundTask.startService(
    serviceTypes: const [ForegroundServiceTypes.microphone],
    notificationTitle: 'Hockey Shot Tracker',
    notificationText: 'Listening for shots and bar downs…',
    callback: _startCallback,
  );
}

Future<void> stopMicForegroundService() {
  return FlutterForegroundTask.stopService();
}

/// Refreshes the persistent notification text with the current shot/bar-down counts.
Future<void> updateMicForegroundNotificationCounts({required int shots, required int barDowns}) {
  return FlutterForegroundTask.updateService(
    notificationText: 'Shots: $shots · Bar Downs: $barDowns',
  );
}

@pragma('vm:entry-point')
void _startCallback() {
  FlutterForegroundTask.setTaskHandler(MicForegroundTaskHandler());
}
