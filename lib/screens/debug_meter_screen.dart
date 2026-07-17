import 'package:flutter/material.dart';

import '../audio/mic_level_controller.dart';
import '../theme/design_tokens.dart';
import '../widgets/pill_progress_indicator.dart';

/// Debug screen proving continuous mic capture: a live level meter driven
/// by [controller]'s amplitude stream, plus start/stop controls.
class DebugMeterScreen extends StatefulWidget {
  const DebugMeterScreen({super.key, required this.controller, this.onSettingsTap});

  final MicLevelController controller;
  final VoidCallback? onSettingsTap;

  @override
  State<DebugMeterScreen> createState() => _DebugMeterScreenState();
}

class _DebugMeterScreenState extends State<DebugMeterScreen> {
  bool _running = false;
  String? _error;

  Future<void> _toggle() async {
    setState(() => _error = null);
    try {
      if (_running) {
        await widget.controller.stop();
      } else {
        await widget.controller.start();
      }
      setState(() => _running = !_running);
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  @override
  void dispose() {
    if (_running) {
      widget.controller.stop();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mic Debug Meter'),
        actions: [
          if (widget.onSettingsTap != null)
            IconButton(
              key: const Key('settingsButton'),
              icon: const Icon(Icons.settings),
              onPressed: widget.onSettingsTap,
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            StreamBuilder<double>(
              stream: widget.controller.levels,
              initialData: 0.0,
              builder: (context, snapshot) {
                final level = snapshot.data ?? 0.0;
                return Column(
                  children: [
                    Text(
                      'Level: ${(level * 100).toStringAsFixed(0)}%',
                      key: const Key('levelText'),
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    PillProgressIndicator(
                      progressKey: const Key('levelMeter'),
                      value: level,
                      minHeight: AppSpacing.xl,
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: AppSpacing.xxl),
            StreamBuilder<int>(
              stream: widget.controller.shotCount,
              initialData: 0,
              builder: (context, snapshot) {
                return Text(
                  'Shots: ${snapshot.data ?? 0}',
                  key: const Key('shotCountText'),
                  style: Theme.of(context).textTheme.headlineSmall,
                );
              },
            ),
            const SizedBox(height: AppSpacing.xxl),
            ElevatedButton(
              key: const Key('toggleButton'),
              onPressed: _toggle,
              child: Text(_running ? 'Stop' : 'Start'),
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.lg),
              Text(
                _error!,
                key: const Key('errorText'),
                style: AppTypography.errorText,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
