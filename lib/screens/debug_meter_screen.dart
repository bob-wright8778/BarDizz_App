import 'package:flutter/material.dart';

import '../audio/mic_level_controller.dart';

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
        padding: const EdgeInsets.all(24),
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
                    const SizedBox(height: 16),
                    LinearProgressIndicator(
                      key: const Key('levelMeter'),
                      value: level,
                      minHeight: 24,
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 32),
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
            const SizedBox(height: 32),
            ElevatedButton(
              key: const Key('toggleButton'),
              onPressed: _toggle,
              child: Text(_running ? 'Stop' : 'Start'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(
                _error!,
                key: const Key('errorText'),
                style: const TextStyle(color: Colors.red),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
