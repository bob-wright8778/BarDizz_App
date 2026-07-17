import 'dart:async';

import 'package:flutter/material.dart';

import '../audio/calibration_controller.dart';

/// Guided flow: prompts the user to take [CalibrationController.targetSamples]
/// sample shots, then derives and saves a reference profile from them.
class CalibrationScreen extends StatefulWidget {
  const CalibrationScreen({super.key, required this.controller, this.onComplete});

  final CalibrationController controller;
  final VoidCallback? onComplete;

  @override
  State<CalibrationScreen> createState() => _CalibrationScreenState();
}

class _CalibrationScreenState extends State<CalibrationScreen> {
  late final StreamSubscription<int> _samplesSubscription;
  late final StreamSubscription<double> _levelSubscription;
  int _recorded = 0;
  double _level = 0.0;
  bool _starting = true;
  bool _recording = false;
  bool _finishing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _samplesSubscription = widget.controller.samplesRecorded.listen(
      (count) => setState(() => _recorded = count),
    );
    _levelSubscription = widget.controller.levels.listen(
      (level) => setState(() => _level = level),
    );
    _begin();
  }

  Future<void> _begin() async {
    try {
      await widget.controller.start();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _recordShot() async {
    setState(() {
      _recording = true;
      _error = null;
    });
    try {
      await widget.controller.recordSample();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _recording = false);
    }
  }

  Future<void> _finish() async {
    setState(() {
      _finishing = true;
      _error = null;
    });
    try {
      await widget.controller.finish();
      widget.onComplete?.call();
    } catch (e) {
      setState(() {
        _finishing = false;
        _error = e.toString();
      });
    }
  }

  @override
  void dispose() {
    _samplesSubscription.cancel();
    _levelSubscription.cancel();
    // Releases the mic if the user backs out mid-flow instead of tapping
    // Finish; harmless (idempotent) if capture was already stopped there.
    widget.controller.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final target = widget.controller.targetSamples;
    final done = _recorded >= target;

    return Scaffold(
      appBar: AppBar(title: const Text('Calibrate Detection')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              done
                  ? 'All $target sample shots recorded.'
                  : 'Take a shot to record sample ${_recorded + 1} of $target.',
              key: const Key('calibrationStatusText'),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 24),
            LinearProgressIndicator(
              key: const Key('calibrationProgress'),
              value: target == 0 ? 0 : _recorded / target,
            ),
            const SizedBox(height: 32),
            if (!_starting && !done) ...[
              Text(
                'Mic level: ${(_level * 100).toStringAsFixed(0)}%'
                ' (need ${(widget.controller.amplitudeThreshold * 100).toStringAsFixed(0)}%+)',
                key: const Key('calibrationLevelText'),
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                key: const Key('calibrationLevelMeter'),
                value: _level.clamp(0.0, 1.0),
                minHeight: 12,
              ),
              const SizedBox(height: 24),
            ],
            if (_starting)
              const CircularProgressIndicator()
            else if (!done)
              ElevatedButton(
                key: const Key('recordShotButton'),
                onPressed: _recording ? null : _recordShot,
                child: Text(_recording ? 'Listening…' : 'Record Shot'),
              )
            else
              ElevatedButton(
                key: const Key('finishCalibrationButton'),
                onPressed: _finishing ? null : _finish,
                child: Text(_finishing ? 'Saving…' : 'Finish'),
              ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(
                _error!,
                key: const Key('calibrationErrorText'),
                style: const TextStyle(color: Colors.red),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
