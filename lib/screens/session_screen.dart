import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../audio/mic_level_controller.dart';
import '../scoreboard/all_time_scoreboard_store.dart';
import '../theme/design_tokens.dart';
import '../widgets/app_card.dart';

/// Native channel that asks Android to background the app (`moveTaskToBack`)
/// instead of finishing the Activity. Ending the Activity on system back would
/// destroy the Flutter engine — and with it all in-memory session state —
/// while the native foreground-service mic capture keeps running orphaned
/// underneath, since it doesn't depend on the Dart isolate.
const _systemNavChannel = MethodChannel('hockey_shot_tracker/system_nav');

/// Lets the user run a shooting session under the BAR DIZZ challenge: mic
/// capture starts automatically when the screen loads and keeps running for
/// the life of the screen. Live auto-detected shot and bar-down dials scoped
/// to the current session (each correctable via +/-) update live, along with
/// an all-time totals strip. "Save Session" folds the session's current
/// counts into the persisted all-time scoreboard and resets both dials to 0
/// without stopping capture.
class SessionScreen extends StatefulWidget {
  const SessionScreen({
    super.key,
    required this.controller,
    this.onSettingsTap,
    this.scoreboardStore = const AllTimeScoreboardStore(),
  });

  final MicLevelController controller;
  final Future<void> Function()? onSettingsTap;
  final AllTimeScoreboardStore scoreboardStore;

  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends State<SessionScreen> {
  late final StreamSubscription<int> _shotCountSubscription;
  late final StreamSubscription<int> _barDownCountSubscription;
  bool _capturing = false;
  bool _starting = false;
  bool _saving = false;
  String? _error;

  int _sessionShots = 0;
  int _autoShotRaw = 0;
  int _sessionAutoBarDowns = 0;
  int _sessionManualBarDowns = 0;
  int _autoBarDownRaw = 0;

  AllTimeScoreboard _persisted =
      const AllTimeScoreboard(shots: 0, autoBarDowns: 0, manualBarDowns: 0);
  // Set once a save has applied a fresher scoreboard than the initial load
  // could have seen, so that slow-resolving load doesn't clobber it (both
  // fire unawaited from initState and race each other).
  bool _initialLoadStale = false;

  int get _sessionBarDowns => _sessionAutoBarDowns + _sessionManualBarDowns;

  // All-time totals live-derived from the persisted scoreboard plus the
  // current session's counts, reusing AllTimeScoreboard's own math rather
  // than re-deriving shots/barDowns/rate by hand.
  AllTimeScoreboard get _combined => _persisted.withSession(
        sessionShots: _sessionShots,
        sessionAutoBarDowns: _sessionAutoBarDowns,
        sessionManualBarDowns: _sessionManualBarDowns,
      );
  int get _displayedShots => _combined.shots;
  int get _displayedBarDowns => _combined.barDowns;
  double get _displayedRate => _combined.rate * 100;

  @override
  void initState() {
    super.initState();
    _shotCountSubscription = widget.controller.shotCount.listen(_onAutoShotCount);
    _barDownCountSubscription = widget.controller.barDownCount.listen(_onAutoBarDownCount);
    _loadScoreboard();
    _startCapture();
  }

  Future<void> _loadScoreboard() async {
    final loaded = await widget.scoreboardStore.load();
    if (mounted && !_initialLoadStale) setState(() => _persisted = loaded);
  }

  /// Reloads the persisted scoreboard after Settings closes.
  Future<void> _handleSettingsTap() async {
    await widget.onSettingsTap?.call();
    // Not _loadScoreboard(): its _initialLoadStale guard is permanently true
    // after the first save and would silently no-op this reload.
    final loaded = await widget.scoreboardStore.load();
    if (mounted) setState(() => _persisted = loaded);
  }

  @override
  void dispose() {
    _shotCountSubscription.cancel();
    _barDownCountSubscription.cancel();
    if (_capturing) {
      widget.controller.stop();
      // Fire-and-forget: dispose() can't await, and there's no widget left
      // to update once this returns. Folds the live session into the
      // scoreboard so it isn't silently lost if the screen is torn down some
      // way other than tapping "Save Session" (e.g. the OS reclaims the
      // Activity mid-session). Skipped if a save is already in flight: the
      // store's load-then-save isn't safe to run concurrently with itself,
      // so that save's own continuation (see _saveSession's finally block)
      // is responsible for folding whatever's still live once it settles,
      // rather than racing it here.
      if (!_saving) _foldLiveSessionIntoScoreboard();
    }
    super.dispose();
  }

  /// Fire-and-forget fold of whatever's currently live; shared by dispose() and _saveSession's finally block.
  void _foldLiveSessionIntoScoreboard() {
    widget.scoreboardStore.foldInSession(
      sessionShots: _sessionShots,
      sessionAutoBarDowns: _sessionAutoBarDowns,
      sessionManualBarDowns: _sessionManualBarDowns,
    );
  }

  void _onAutoShotCount(int rawCount) =>
      _applyAutoDelta(rawCount, getRaw: () => _autoShotRaw, setRaw: (v) => _autoShotRaw = v,
          apply: (delta) => _sessionShots += delta);

  void _onAutoBarDownCount(int rawCount) =>
      _applyAutoDelta(rawCount, getRaw: () => _autoBarDownRaw, setRaw: (v) => _autoBarDownRaw = v,
          apply: (delta) => _sessionAutoBarDowns += delta);

  // Combines the controller's absolute auto-detected count with any manual
  // +/- offset already applied, by tracking the delta since the last auto
  // update rather than overwriting the displayed count outright.
  void _applyAutoDelta(
    int rawCount, {
    required int Function() getRaw,
    required void Function(int) setRaw,
    required void Function(int delta) apply,
  }) {
    final delta = rawCount - getRaw();
    setRaw(rawCount);
    setState(() => apply(delta));
  }

  /// Resets session and raw-baseline counters; only valid right after controller.start() resets its own.
  void _resetForNewCapture() {
    _sessionShots = 0;
    _autoShotRaw = 0;
    _sessionAutoBarDowns = 0;
    _sessionManualBarDowns = 0;
    _autoBarDownRaw = 0;
  }

  Future<void> _startCapture() async {
    if (_starting) return;
    setState(() {
      _starting = true;
      _error = null;
    });
    try {
      await widget.controller.start();
      if (mounted) {
        setState(() {
          _capturing = true;
          _starting = false;
          _resetForNewCapture();
        });
      } else {
        // The screen was torn down while this start was still in flight, so
        // dispose() never got a chance to stop it (it only stops a capture
        // that was already marked _capturing). Capture may have started
        // successfully in the background regardless -- release it now
        // rather than leaking the mic/foreground service indefinitely.
        unawaited(widget.controller.stop());
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _starting = false;
          _error = e.toString();
        });
      }
    }
  }

  Future<void> _saveSession() async {
    if (_saving) return;
    final foldedShots = _sessionShots;
    final foldedAutoBarDowns = _sessionAutoBarDowns;
    final foldedManualBarDowns = _sessionManualBarDowns;
    setState(() {
      _saving = true;
      _error = null;
      // Optimistic reset, before the await: capture keeps running through
      // the save, so zeroing now (rather than after foldInSession resolves)
      // means anything that lands mid-save correctly belongs to the next
      // session rather than being wiped out by a reset-after-await. Raw
      // auto-detected baselines are untouched -- the controller's absolute
      // counters never reset mid-capture.
      _sessionShots = 0;
      _sessionAutoBarDowns = 0;
      _sessionManualBarDowns = 0;
    });
    try {
      final updated = await widget.scoreboardStore.foldInSession(
        sessionShots: foldedShots,
        sessionAutoBarDowns: foldedAutoBarDowns,
        sessionManualBarDowns: foldedManualBarDowns,
      );
      _initialLoadStale = true;
      if (mounted) {
        setState(() {
          _persisted = updated;
          _saving = false;
        });
      }
    } catch (e) {
      // The fold didn't happen -- give the optimistically-cleared counts
      // back to the live session instead of losing them. Done unconditionally
      // (not just if mounted): the finally block below needs the true
      // unfolded amount to fold it separately if the screen is gone.
      _sessionShots += foldedShots;
      _sessionAutoBarDowns += foldedAutoBarDowns;
      _sessionManualBarDowns += foldedManualBarDowns;
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e.toString();
        });
      }
    } finally {
      // dispose() skips its own fold while a save is in flight (see there),
      // so if the screen was torn down during this save, this save is the
      // only thing left that can fold whatever's still live -- runs
      // sequentially after the above already settled, never concurrently
      // with it.
      if (!mounted &&
          (_sessionShots != 0 || _sessionAutoBarDowns != 0 || _sessionManualBarDowns != 0)) {
        _foldLiveSessionIntoScoreboard();
      }
    }
  }

  Future<void> _moveToBackground() => _systemNavChannel.invokeMethod('moveTaskToBack');

  /// Inputs: [get]/[set] the field to adjust, [delta] the signed change.
  /// Outputs: none -- applies the change floored at 0.
  void _adjust(int Function() get, void Function(int) set, int delta) {
    // Upper bound is a no-op cap (no dial has a real ceiling) -- clamp only
    // exists for the floor-at-0 side.
    setState(() => set((get() + delta).clamp(0, 1 << 31)));
  }

  void _incrementShots() => _adjust(() => _sessionShots, (v) => _sessionShots = v, 1);

  void _decrementShots() => _adjust(() => _sessionShots, (v) => _sessionShots = v, -1);

  void _incrementBarDowns() =>
      _adjust(() => _sessionManualBarDowns, (v) => _sessionManualBarDowns = v, 1);

  void _decrementBarDowns() =>
      _adjust(() => _sessionManualBarDowns, (v) => _sessionManualBarDowns = v, -1);

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_capturing,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _capturing) _moveToBackground();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Session'),
          actions: [
            if (widget.onSettingsTap != null)
              IconButton(
                key: const Key('settingsButton'),
                icon: const Icon(Icons.settings),
                onPressed: _handleSettingsTap,
              ),
          ],
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              children: [
                Text(
                  'BAR DIZZ',
                  style: AppTypography.h1.copyWith(color: AppColors.iceBluePrimary),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'THE BAR DOWN CHALLENGE',
                  style: AppTypography.overline.copyWith(color: AppColors.iceBluePrimary),
                ),
                const SizedBox(height: AppSpacing.xl),
                AppCard(
                  padding: const EdgeInsets.symmetric(
                    vertical: AppSpacing.lg,
                    horizontal: AppSpacing.md,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _TotalStat(
                        label: 'SHOTS',
                        value: '$_displayedShots',
                        valueKey: const Key('allTimeShotsValue'),
                      ),
                      _TotalStat(
                        label: 'BAR DOWNS',
                        value: '$_displayedBarDowns',
                        valueKey: const Key('allTimeBarDownsValue'),
                        barDownAccent: true,
                      ),
                      _TotalStat(
                        label: 'RATE',
                        value: '${_displayedRate.toStringAsFixed(1)}%',
                        valueKey: const Key('allTimeRateValue'),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _CorrectionDial(
                      label: 'SHOTS',
                      value: _sessionShots,
                      running: _capturing,
                      onIncrement: _incrementShots,
                      onDecrement: _decrementShots,
                      incrementKey: const Key('shotIncrementButton'),
                      decrementKey: const Key('shotDecrementButton'),
                      valueKey: const Key('sessionShotCountText'),
                    ),
                    _CorrectionDial(
                      label: 'BAR DOWN',
                      value: _sessionBarDowns,
                      running: _capturing,
                      onIncrement: _incrementBarDowns,
                      onDecrement: _decrementBarDowns,
                      incrementKey: const Key('barDownIncrementButton'),
                      decrementKey: const Key('barDownDecrementButton'),
                      valueKey: const Key('sessionBarDownCountText'),
                      barDownAccent: true,
                    ),
                  ],
                ),
                const Spacer(),
                ElevatedButton(
                  key: const Key('sessionActionButton'),
                  onPressed: (_starting || _saving)
                      ? null
                      : (_capturing ? _saveSession : _startCapture),
                  child: Text(_capturing ? 'Save Session' : 'Start Session'),
                ),
                if (_error != null) ...[
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    _error!,
                    key: const Key('sessionErrorText'),
                    style: AppTypography.errorText,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TotalStat extends StatelessWidget {
  const _TotalStat({
    required this.label,
    required this.value,
    required this.valueKey,
    this.barDownAccent = false,
  });

  final String label;
  final String value;
  final Key valueKey;
  final bool barDownAccent;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: AppTypography.overline.copyWith(color: AppColors.ink300)),
        const SizedBox(height: AppSpacing.xs),
        Text(
          value,
          key: valueKey,
          style: AppTypography.h2.copyWith(
            color: barDownAccent ? AppColors.iceBluePressed : AppColors.ink50,
            fontFeatures: const [FontFeature.tabularFigures()],
            shadows: barDownAccent ? AppGlow.barDown : null,
          ),
        ),
      ],
    );
  }
}

class _CorrectionDial extends StatelessWidget {
  const _CorrectionDial({
    required this.label,
    required this.value,
    required this.running,
    required this.onIncrement,
    required this.onDecrement,
    required this.incrementKey,
    required this.decrementKey,
    required this.valueKey,
    this.barDownAccent = false,
  });

  final String label;
  final int value;
  final bool running;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final Key incrementKey;
  final Key decrementKey;
  final Key valueKey;
  final bool barDownAccent;

  @override
  Widget build(BuildContext context) {
    final valueStyle = AppTypography.display.copyWith(
      fontSize: 48,
      color: barDownAccent ? AppColors.iceBluePressed : null,
      shadows: barDownAccent ? AppGlow.barDown : null,
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: AppTypography.overline.copyWith(color: AppColors.ink300)),
        const SizedBox(height: AppSpacing.sm),
        if (running)
          IconButton(
            key: incrementKey,
            icon: const Icon(Icons.add_circle_outline),
            onPressed: onIncrement,
          ),
        Text('$value', key: valueKey, style: valueStyle),
        if (running)
          IconButton(
            key: decrementKey,
            icon: const Icon(Icons.remove_circle_outline),
            onPressed: onDecrement,
          ),
      ],
    );
  }
}
