import 'package:flutter/material.dart';

/// Minimal settings screen: the calibration redo entry point (Acceptance
/// criterion: calibration can be re-done at any time), plus an optional
/// entry to the raw mic debug meter (ticket 01's capture proof-of-concept),
/// which stopped being reachable once the session screen became the app's
/// home.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.onRecalibrate, this.onDebugMeterTap});

  final VoidCallback onRecalibrate;
  final VoidCallback? onDebugMeterTap;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          ListTile(
            key: const Key('recalibrateTile'),
            leading: const Icon(Icons.tune),
            title: const Text('Redo calibration'),
            onTap: onRecalibrate,
          ),
          if (onDebugMeterTap != null)
            ListTile(
              key: const Key('debugMeterTile'),
              leading: const Icon(Icons.bug_report),
              title: const Text('Debug meter'),
              onTap: onDebugMeterTap,
            ),
        ],
      ),
    );
  }
}
