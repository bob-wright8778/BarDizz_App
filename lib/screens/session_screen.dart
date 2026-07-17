import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../audio/mic_level_controller.dart';
import '../history/session_history_store.dart';
import '../history/session_record.dart';

/// Default shot-count goal for a new session, shown as "of 10000" until the
/// user edits it.
const defaultSessionGoal = 10000;

/// Native channel that asks Android to background the app (`moveTaskToBack`)
/// instead of finishing the Activity. Ending the Activity on system back would
/// destroy the Flutter engine — and with it all in-memory session state —
/// while the native foreground-service mic capture keeps running orphaned
/// underneath, since it doesn't depend on the Dart isolate.
const _systemNavChannel = MethodChannel('hockey_shot_tracker/system_nav');

/// Lets the user run a shooting session: start/stop capture, watch the
/// live auto-detected count climb toward an editable goal, and correct the
/// count immediately via +/- if detection misses or misfires.
class SessionScreen extends StatefulWidget {
  const SessionScreen({
    super.key,
    required this.controller,
    this.initialGoal = defaultSessionGoal,
    this.onSettingsTap,
    this.onHistoryTap,
    this.historyStore = const SessionHistoryStore(),
  });

  final MicLevelController controller;
  final int initialGoal;
  final VoidCallback? onSettingsTap;
  final VoidCallback? onHistoryTap;
  final SessionHistoryStore historyStore;

  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends State<SessionScreen> {
  late final StreamSubscription<int> _shotCountSubscription;
  bool _running = false;
  String? _error;
  int _count = 0;
  int _autoCount = 0;
  late int _goal = widget.initialGoal;
  DateTime? _startedAt;

  @override
  void initState() {
    super.initState();
    _shotCountSubscription = widget.controller.shotCount.listen(_onAutoShotCount);
  }

  @override
  void dispose() {
    _shotCountSubscription.cancel();
    if (_running) {
      widget.controller.stop();
      _saveToHistory();
    }
    super.dispose();
  }

  // Combines the controller's absolute auto-detected count with any manual
  // +/- offset already applied, by tracking the delta since the last auto
  // update rather than overwriting the displayed count outright.
  void _onAutoShotCount(int rawCount) {
    final delta = rawCount - _autoCount;
    _autoCount = rawCount;
    setState(() => _count += delta);
  }

  Future<void> _toggleSession() async {
    setState(() => _error = null);
    try {
      if (_running) {
        await widget.controller.stop();
        await _saveToHistory();
        setState(() => _running = false);
      } else {
        await widget.controller.start();
        setState(() {
          _running = true;
          _count = 0;
          _autoCount = 0;
          _startedAt = DateTime.now();
        });
      }
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  // Persists the just-ended session to local history (Acceptance criterion:
  // ending a session saves date, duration, shot count, and goal).
  Future<void> _saveToHistory() async {
    final startedAt = _startedAt;
    if (startedAt == null) return;
    await widget.historyStore.saveSession(
      SessionRecord(
        date: startedAt,
        duration: DateTime.now().difference(startedAt),
        shotCount: _count,
        goal: _goal,
      ),
    );
  }

  Future<void> _moveToBackground() => _systemNavChannel.invokeMethod('moveTaskToBack');

  void _increment() => setState(() => _count++);

  void _decrement() => setState(() => _count = _count > 0 ? _count - 1 : 0);

  Future<void> _editGoal() async {
    var goalText = _goal.toString();
    final newGoal = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Set goal'),
        content: TextFormField(
          key: const Key('goalInputField'),
          initialValue: goalText,
          keyboardType: TextInputType.number,
          autofocus: true,
          onChanged: (value) => goalText = value,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            key: const Key('saveGoalButton'),
            onPressed: () => Navigator.of(context).pop(int.tryParse(goalText)),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (newGoal != null && newGoal > 0) {
      setState(() => _goal = newGoal);
    }
  }

  @override
  Widget build(BuildContext context) {
    final progress = (_count / _goal).clamp(0.0, 1.0);

    return PopScope(
      canPop: !_running,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _running) _moveToBackground();
      },
      child: Scaffold(
      appBar: AppBar(
        title: const Text('Session'),
        actions: [
          IconButton(
            key: const Key('editGoalButton'),
            icon: const Icon(Icons.flag),
            onPressed: _editGoal,
          ),
          if (widget.onHistoryTap != null)
            IconButton(
              key: const Key('historyButton'),
              icon: const Icon(Icons.history),
              onPressed: widget.onHistoryTap,
            ),
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
            Text(
              '$_count',
              key: const Key('shotCountText'),
              style: Theme.of(context).textTheme.displayMedium,
            ),
            Text('of $_goal', key: const Key('goalText')),
            const SizedBox(height: 16),
            LinearProgressIndicator(
              key: const Key('progressBar'),
              value: progress,
              minHeight: 16,
            ),
            const SizedBox(height: 32),
            if (_running)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    key: const Key('decrementButton'),
                    iconSize: 40,
                    icon: const Icon(Icons.remove_circle_outline),
                    onPressed: _decrement,
                  ),
                  const SizedBox(width: 32),
                  IconButton(
                    key: const Key('incrementButton'),
                    iconSize: 40,
                    icon: const Icon(Icons.add_circle_outline),
                    onPressed: _increment,
                  ),
                ],
              ),
            const SizedBox(height: 32),
            ElevatedButton(
              key: const Key('sessionToggleButton'),
              onPressed: _toggleSession,
              child: Text(_running ? 'End Session' : 'Start Session'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(
                _error!,
                key: const Key('sessionErrorText'),
                style: const TextStyle(color: Colors.red),
              ),
            ],
          ],
        ),
      ),
      ),
    );
  }
}
