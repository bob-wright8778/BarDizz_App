import 'package:shared_preferences/shared_preferences.dart';

const String _shotsKey = 'high_score_shots';
const String _autoBarDownsKey = 'high_score_auto_bar_downs';
const String _manualBarDownsKey = 'high_score_manual_bar_downs';

/// The single best session ever recorded, ranked by bar-down rate then bar-down total.
class HighScoreSession {
  const HighScoreSession({
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

  /// Inputs: a candidate session to rank against this one.
  /// Outputs: whichever session ranks higher -- the candidate only wins with a strictly higher rate,
  /// or a tied rate with a strictly higher bar-down total.
  HighScoreSession bestOf(HighScoreSession candidate) {
    final candidateWins =
        candidate.rate > rate || (candidate.rate == rate && candidate.barDowns > barDowns);
    return candidateWins ? candidate : this;
  }
}

/// Persists the all-time best single session locally via [SharedPreferences], independent of the
/// cumulative all-time scoreboard store.
class HighScoreStore {
  const HighScoreStore();

  /// Outputs: the persisted high score (zeroed if no session has ever been recorded).
  Future<HighScoreSession> load() async {
    return await _loadRecorded() ?? const HighScoreSession(shots: 0, autoBarDowns: 0, manualBarDowns: 0);
  }

  /// Inputs: a session's final shot/auto/manual bar-down counts.
  /// Outputs: the persisted high score after ranking the session against it via [HighScoreSession.bestOf]
  /// -- any session always wins against "nothing recorded yet" (a zero-rate session is a real result,
  /// not the same thing as no session ever having been played).
  Future<HighScoreSession> considerSession({
    required int sessionShots,
    required int sessionAutoBarDowns,
    required int sessionManualBarDowns,
  }) async {
    final current = await _loadRecorded();
    final candidate = HighScoreSession(
      shots: sessionShots,
      autoBarDowns: sessionAutoBarDowns,
      manualBarDowns: sessionManualBarDowns,
    );
    final winner = current?.bestOf(candidate) ?? candidate;
    await _save(winner);
    return winner;
  }

  /// Clears the persisted high score back to "nothing recorded yet".
  Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_shotsKey);
    await prefs.remove(_autoBarDownsKey);
    await prefs.remove(_manualBarDownsKey);
  }

  /// Outputs: the persisted high score, or null if no session has ever been recorded -- distinct from
  /// a recorded session that happens to be all zeros.
  Future<HighScoreSession?> _loadRecorded() async {
    final prefs = await SharedPreferences.getInstance();
    if (!prefs.containsKey(_shotsKey)) return null;
    return HighScoreSession(
      shots: prefs.getInt(_shotsKey) ?? 0,
      autoBarDowns: prefs.getInt(_autoBarDownsKey) ?? 0,
      manualBarDowns: prefs.getInt(_manualBarDownsKey) ?? 0,
    );
  }

  Future<void> _save(HighScoreSession session) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_shotsKey, session.shots);
    await prefs.setInt(_autoBarDownsKey, session.autoBarDowns);
    await prefs.setInt(_manualBarDownsKey, session.manualBarDowns);
  }
}
