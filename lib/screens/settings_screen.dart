import 'package:flutter/material.dart';

import '../scoreboard/all_time_scoreboard_store.dart';
import '../theme/design_tokens.dart';
import '../widgets/app_card.dart';

/// Settings screen: the all-time sound-only vs. manually-added bar-down
/// breakdown, the Reset Scoreboard action, plus an optional entry to the raw
/// mic debug meter (ticket 01's capture proof-of-concept), which stopped
/// being reachable once the session screen became the app's home.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    this.onDebugMeterTap,
    this.scoreboardStore = const AllTimeScoreboardStore(),
  });

  final VoidCallback? onDebugMeterTap;
  final AllTimeScoreboardStore scoreboardStore;

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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Reset Scoreboard?'),
        content: const Text(
          'This permanently clears your all-time shot and bar-down totals, '
          'including the sound-only/manually-added breakdown. This cannot be undone.',
        ),
        actions: [
          TextButton(
            key: const Key('resetScoreboardCancelButton'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            key: const Key('resetScoreboardConfirmButton'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await widget.scoreboardStore.reset();
      await _loadScoreboard();
    }
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
