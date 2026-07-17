import 'package:flutter/material.dart';

import 'audio/calibration_controller.dart';
import 'audio/calibration_profile_store.dart';
import 'audio/mic_level_controller.dart';
import 'screens/calibration_screen.dart';
import 'screens/debug_meter_screen.dart';
import 'screens/history_screen.dart';
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

/// Gates the app on an initial calibration profile: shows the guided
/// calibration flow first-launch (Acceptance criterion: detection cannot be
/// used before an initial calibration exists), then the home screen once one
/// exists.
class AppHomeGate extends StatefulWidget {
  const AppHomeGate({super.key, CalibrationProfileStore? profileStore})
      : profileStore = profileStore ?? const CalibrationProfileStore();

  final CalibrationProfileStore profileStore;

  @override
  State<AppHomeGate> createState() => _AppHomeGateState();
}

class _AppHomeGateState extends State<AppHomeGate> {
  bool? _hasProfile;

  // Created once and reused across rebuilds (e.g. rotation), rather than
  // per-build, so a running session's controller is never swapped out from
  // under SessionScreen's stream subscription mid-session.
  late final LiveMicLevelController _sessionController =
      LiveMicLevelController(profileStore: widget.profileStore);

  @override
  void initState() {
    super.initState();
    _checkProfile();
  }

  Future<void> _checkProfile() async {
    final has = await widget.profileStore.hasProfile();
    if (mounted) setState(() => _hasProfile = has);
  }

  void _openSettings(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SettingsScreen(
          onRecalibrate: () => _openCalibration(context),
          onDebugMeterTap: () => _openDebugMeter(context),
        ),
      ),
    );
  }

  void _openHistory(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const HistoryScreen()),
    );
  }

  void _openDebugMeter(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DebugMeterScreen(
          controller: LiveMicLevelController(profileStore: widget.profileStore),
        ),
      ),
    );
  }

  void _openCalibration(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CalibrationScreen(
          controller: LiveCalibrationController(profileStore: widget.profileStore),
          onComplete: () => Navigator.of(context)
            ..pop()
            ..pop(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_hasProfile == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_hasProfile == false) {
      return CalibrationScreen(
        controller: LiveCalibrationController(profileStore: widget.profileStore),
        onComplete: () => setState(() => _hasProfile = true),
      );
    }

    return SessionScreen(
      controller: _sessionController,
      onSettingsTap: () => _openSettings(context),
      onHistoryTap: () => _openHistory(context),
    );
  }
}
