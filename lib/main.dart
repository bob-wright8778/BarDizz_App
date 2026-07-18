import 'package:flutter/material.dart';

import 'audio/calibration_controller.dart';
import 'audio/calibration_profile_store.dart';
import 'audio/mic_level_controller.dart';
import 'screens/calibration_screen.dart';
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

/// Gates the app on an initial calibration profile: shows the guided
/// calibration flow first-launch (Acceptance criterion: detection cannot be
/// used before an initial calibration exists), then the home screen once one
/// exists.
class AppHomeGate extends StatefulWidget {
  const AppHomeGate({super.key, CalibrationProfileStore? profileStore, CalibrationProfileStore? ewwProfileStore})
      : profileStore = profileStore ?? const CalibrationProfileStore(),
        ewwProfileStore = ewwProfileStore ?? const CalibrationProfileStore(key: ewwProfileKey);

  final CalibrationProfileStore profileStore;
  final CalibrationProfileStore ewwProfileStore;

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

  // Both profiles must be present -- calibration always saves the shot
  // profile then the Eww one (LiveCalibrationController.finish()); treating
  // only the shot profile as "calibrated" would let an interrupted
  // mid-finish state slip past this gate and fail later, inside a session.
  Future<void> _checkProfile() async {
    final hasShot = await widget.profileStore.hasProfile();
    final hasEww = await widget.ewwProfileStore.hasProfile();
    if (mounted) setState(() => _hasProfile = hasShot && hasEww);
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
    );
  }
}
