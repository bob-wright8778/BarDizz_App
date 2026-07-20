import 'package:shared_preferences/shared_preferences.dart';

const String _shotsKey = 'all_time_shots';
const String _autoBarDownsKey = 'all_time_auto_bar_downs';
const String _manualBarDownsKey = 'all_time_manual_bar_downs';

/// Cumulative all-time shot/bar-down totals, with the bar-down total and rate
/// always derived rather than independently tracked.
class AllTimeScoreboard {
  const AllTimeScoreboard({
    required this.shots,
    required this.autoBarDowns,
    required this.manualBarDowns,
  });

  final int shots;
  final int autoBarDowns;
  final int manualBarDowns;

  int get barDowns => autoBarDowns + manualBarDowns;

  /// Outputs: bar-down rate, or 0 when no shots have been taken yet.
  double get rate => shots == 0 ? 0 : barDowns / shots;

  /// Inputs: a session's live shot/auto/manual bar-down counts.
  /// Outputs: this scoreboard with those counts added in, computed without persisting.
  AllTimeScoreboard withSession({
    required int sessionShots,
    required int sessionAutoBarDowns,
    required int sessionManualBarDowns,
  }) {
    return AllTimeScoreboard(
      shots: shots + sessionShots,
      autoBarDowns: autoBarDowns + sessionAutoBarDowns,
      manualBarDowns: manualBarDowns + sessionManualBarDowns,
    );
  }
}

/// Persists the all-time cumulative scoreboard locally via [SharedPreferences].
class AllTimeScoreboardStore {
  const AllTimeScoreboardStore();

  /// Outputs: the persisted all-time totals (zeroed if nothing saved yet).
  Future<AllTimeScoreboard> load() async {
    final prefs = await SharedPreferences.getInstance();
    return AllTimeScoreboard(
      shots: prefs.getInt(_shotsKey) ?? 0,
      autoBarDowns: prefs.getInt(_autoBarDownsKey) ?? 0,
      manualBarDowns: prefs.getInt(_manualBarDownsKey) ?? 0,
    );
  }

  /// Inputs: a session's final shot/auto/manual bar-down counts, added into the persisted totals.
  /// Outputs: the new persisted totals, so callers never need to recompute this themselves off a
  /// possibly-stale local copy.
  Future<AllTimeScoreboard> foldInSession({
    required int sessionShots,
    required int sessionAutoBarDowns,
    required int sessionManualBarDowns,
  }) async {
    final current = await load();
    final updated = current.withSession(
      sessionShots: sessionShots,
      sessionAutoBarDowns: sessionAutoBarDowns,
      sessionManualBarDowns: sessionManualBarDowns,
    );
    await _save(updated);
    return updated;
  }

  /// Zeroes all persisted counters (shots, auto bar downs, manual bar downs).
  Future<void> reset() async {
    await _save(const AllTimeScoreboard(shots: 0, autoBarDowns: 0, manualBarDowns: 0));
  }

  Future<void> _save(AllTimeScoreboard scoreboard) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_shotsKey, scoreboard.shots);
    await prefs.setInt(_autoBarDownsKey, scoreboard.autoBarDowns);
    await prefs.setInt(_manualBarDownsKey, scoreboard.manualBarDowns);
  }
}
