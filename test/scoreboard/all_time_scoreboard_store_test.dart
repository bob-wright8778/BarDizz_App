import 'package:flutter_test/flutter_test.dart';
import 'package:hockey_shot_tracker/scoreboard/all_time_scoreboard_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('AllTimeScoreboard derived math', () {
    test('barDowns is auto plus manual', () {
      const scoreboard = AllTimeScoreboard(shots: 10, autoBarDowns: 3, manualBarDowns: 2);
      expect(scoreboard.barDowns, 5);
    });

    test('rate is barDowns over shots', () {
      const scoreboard = AllTimeScoreboard(shots: 10, autoBarDowns: 3, manualBarDowns: 2);
      expect(scoreboard.rate, closeTo(0.5, 1e-9));
    });

    test('rate is 0 when no shots have been taken', () {
      const scoreboard = AllTimeScoreboard(shots: 0, autoBarDowns: 0, manualBarDowns: 0);
      expect(scoreboard.rate, 0);
    });

    test('withSession adds session counts without mutating the original', () {
      const scoreboard = AllTimeScoreboard(shots: 10, autoBarDowns: 3, manualBarDowns: 2);
      final live = scoreboard.withSession(
        sessionShots: 4,
        sessionAutoBarDowns: 1,
        sessionManualBarDowns: 1,
      );

      expect(live.shots, 14);
      expect(live.autoBarDowns, 4);
      expect(live.manualBarDowns, 3);
      expect(scoreboard.shots, 10);
    });
  });

  group('AllTimeScoreboardStore', () {
    test('load returns zeroed totals before anything is saved', () async {
      const store = AllTimeScoreboardStore();
      final loaded = await store.load();

      expect(loaded.shots, 0);
      expect(loaded.autoBarDowns, 0);
      expect(loaded.manualBarDowns, 0);
    });

    test('foldInSession persists a session\'s counts into the totals', () async {
      const store = AllTimeScoreboardStore();

      await store.foldInSession(sessionShots: 10, sessionAutoBarDowns: 3, sessionManualBarDowns: 2);
      final loaded = await store.load();

      expect(loaded.shots, 10);
      expect(loaded.autoBarDowns, 3);
      expect(loaded.manualBarDowns, 2);
    });

    test('foldInSession accumulates across multiple sessions', () async {
      const store = AllTimeScoreboardStore();

      await store.foldInSession(sessionShots: 10, sessionAutoBarDowns: 3, sessionManualBarDowns: 2);
      await store.foldInSession(sessionShots: 5, sessionAutoBarDowns: 1, sessionManualBarDowns: 0);
      final loaded = await store.load();

      expect(loaded.shots, 15);
      expect(loaded.autoBarDowns, 4);
      expect(loaded.manualBarDowns, 2);
    });

    test('foldInSession does not affect a scoreboard computed via withSession before it ran', () async {
      const store = AllTimeScoreboardStore();
      final before = await store.load();
      final live = before.withSession(sessionShots: 10, sessionAutoBarDowns: 3, sessionManualBarDowns: 2);

      expect(live.shots, 10);
      final stillPersisted = await store.load();
      expect(stillPersisted.shots, 0);
    });

    test('reset zeroes all persisted counters', () async {
      const store = AllTimeScoreboardStore();
      await store.foldInSession(sessionShots: 10, sessionAutoBarDowns: 3, sessionManualBarDowns: 2);

      await store.reset();
      final loaded = await store.load();

      expect(loaded.shots, 0);
      expect(loaded.autoBarDowns, 0);
      expect(loaded.manualBarDowns, 0);
    });
  });
}
