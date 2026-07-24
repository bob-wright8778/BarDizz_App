import 'package:flutter/material.dart';

import '../scoreboard/all_time_scoreboard_store.dart';
import '../scoreboard/high_score_store.dart';
import '../theme/design_tokens.dart';
import '../widgets/app_card.dart';

/// Settings screen: the all-time sound-only vs. manually-added bar-down
/// breakdown, independent Reset Scoreboard / Reset High Score actions, plus
/// an optional entry to the raw mic debug meter (ticket 01's capture
/// proof-of-concept), which stopped being reachable once the session screen
/// became the app's home.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    this.onDebugMeterTap,
    this.scoreboardStore = const AllTimeScoreboardStore(),
    this.highScoreStore = const HighScoreStore(),
  });

  final VoidCallback? onDebugMeterTap;
  final AllTimeScoreboardStore scoreboardStore;
  final HighScoreStore highScoreStore;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  AllTimeScoreboard? _scoreboard;

  @override
  void initState() {
    super.initState();
    _loadScoreboard();
  }

  Future<void> _loadScoreboard() async {
    final loaded = await widget.scoreboardStore.load();
    if (mounted) setState(() => _scoreboard = loaded);
  }

  Future<void> _resetScoreboard() async {
    final confirmed = await _confirmReset(
      title: 'Reset Scoreboard?',
      content: 'This permanently clears your all-time shot and bar-down totals, '
          'including the sound-only/manually-added breakdown. This cannot be undone.',
      cancelKey: const Key('resetScoreboardCancelButton'),
      confirmKey: const Key('resetScoreboardConfirmButton'),
    );

    if (confirmed) {
      await widget.scoreboardStore.reset();
      await _loadScoreboard();
    }
  }

  Future<void> _resetHighScore() async {
    final confirmed = await _confirmReset(
      title: 'Reset High Score?',
      content: 'This permanently clears your recorded high score. This cannot be undone.',
      cancelKey: const Key('resetHighScoreCancelButton'),
      confirmKey: const Key('resetHighScoreConfirmButton'),
    );

    if (confirmed) await widget.highScoreStore.reset();
  }

  /// Inputs: dialog title/body text and keys for its Cancel/Reset buttons.
  /// Outputs: true if the user confirmed, false if cancelled or dismissed.
  Future<bool> _confirmReset({
    required String title,
    required String content,
    required Key cancelKey,
    required Key confirmKey,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            key: cancelKey,
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            key: confirmKey,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  @override
  Widget build(BuildContext context) {
    final scoreboard = _scoreboard;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppCard(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.onDebugMeterTap != null)
                    ListTile(
                      key: const Key('debugMeterTile'),
                      leading: const Icon(Icons.bug_report),
                      title: const Text('Debug meter'),
                      onTap: widget.onDebugMeterTap,
                    ),
                  ListTile(
                    key: const Key('resetScoreboardTile'),
                    leading: const Icon(Icons.restart_alt),
                    title: const Text('Reset Scoreboard'),
                    onTap: _resetScoreboard,
                  ),
                  ListTile(
                    key: const Key('resetHighScoreTile'),
                    leading: const Icon(Icons.emoji_events_outlined),
                    title: const Text('Reset High Score'),
                    onTap: _resetHighScore,
                  ),
                ],
              ),
            ),
            if (scoreboard != null) ...[
              const SizedBox(height: AppSpacing.lg),
              AppCard(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('All-time bar downs', style: AppTypography.label),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'Sound-only: ${scoreboard.autoBarDowns}',
                      key: const Key('soundOnlyBarDownsValue'),
                      style: AppTypography.body,
                    ),
                    Text(
                      'Manually added: ${scoreboard.manualBarDowns}',
                      key: const Key('manualBarDownsValue'),
                      style: AppTypography.body,
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
