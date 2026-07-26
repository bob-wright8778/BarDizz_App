import 'package:flutter/material.dart';

import 'audio/mic_level_controller.dart';
import 'screens/debug_meter_screen.dart';
import 'screens/session_screen.dart';
import 'screens/settings_screen.dart';
import 'settings/eww_always_bar_down_store.dart';
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
  // Cached in memory (not re-read from SharedPreferences per audio chunk) so
  // the getters below stay synchronous; loaded once at startup and kept in
  // sync with Settings via _onEwwAlwaysBarDownChanged.
  bool _ewwAlwaysBarDown = ewwAlwaysBarDownDefault;

  // Created once and reused across rebuilds (e.g. rotation), rather than
  // per-build, so a running session's controller is never swapped out from
  // under SessionScreen's stream subscription mid-session. Reads
  // _ewwAlwaysBarDown via a getter (not a fixed value) so toggling Settings
  // takes effect on the next classified window, no restart needed.
  late final LiveMicLevelController _sessionController =
      LiveMicLevelController(ewwAlwaysBarDown: _currentEwwAlwaysBarDown);

  @override
  void initState() {
    super.initState();
    _loadEwwAlwaysBarDown();
  }

  bool _currentEwwAlwaysBarDown() => _ewwAlwaysBarDown;

  Future<void> _loadEwwAlwaysBarDown() async {
    final loaded = await const EwwAlwaysBarDownStore().load();
    if (mounted) setState(() => _ewwAlwaysBarDown = loaded);
  }

  void _onEwwAlwaysBarDownChanged(bool value) {
    setState(() => _ewwAlwaysBarDown = value);
  }

  Future<void> _openSettings(BuildContext context) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SettingsScreen(
          onDebugMeterTap: () => _openDebugMeter(context),
          onEwwAlwaysBarDownChanged: _onEwwAlwaysBarDownChanged,
        ),
      ),
    );
  }

  void _openDebugMeter(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DebugMeterScreen(
          controller: LiveMicLevelController(ewwAlwaysBarDown: _currentEwwAlwaysBarDown),
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
