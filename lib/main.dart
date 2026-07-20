import 'package:flutter/material.dart';

import 'audio/mic_level_controller.dart';
import 'screens/debug_meter_screen.dart';
import 'screens/session_screen.dart';
import 'screens/settings_screen.dart';
import 'theme/app_theme.dart';

void main() {
  runApp(const HockeyShotTrackerApp());
}

class HockeyShotTrackerApp extends StatelessWidget {
  const HockeyShotTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BarDizz',
      theme: AppTheme.dark,
      home: const AppHomeGate(),
    );
  }
}

/// Hosts the session screen and the persistent mic-level controller behind
/// it (settings/debug-meter navigation live here too).
class AppHomeGate extends StatefulWidget {
  const AppHomeGate({super.key});

  @override
  State<AppHomeGate> createState() => _AppHomeGateState();
}

class _AppHomeGateState extends State<AppHomeGate> {
  // Created once and reused across rebuilds (e.g. rotation), rather than
  // per-build, so a running session's controller is never swapped out from
  // under SessionScreen's stream subscription mid-session.
  late final LiveMicLevelController _sessionController = LiveMicLevelController();

  void _openSettings(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SettingsScreen(
          onDebugMeterTap: () => _openDebugMeter(context),
        ),
      ),
    );
  }

  void _openDebugMeter(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DebugMeterScreen(
          controller: LiveMicLevelController(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SessionScreen(
      controller: _sessionController,
      onSettingsTap: () => _openSettings(context),
    );
  }
}
