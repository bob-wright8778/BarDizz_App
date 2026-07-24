import 'package:flutter_test/flutter_test.dart';
import 'package:hockey_shot_tracker/scoreboard/all_time_scoreboard_store.dart';
import 'package:hockey_shot_tracker/scoreboard/high_score_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('HighScoreSession derived math', () {
    test('barDowns is auto plus manual', () {
      const session = HighScoreSession(shots: 20, autoBarDowns: 3, manualBarDowns: 2);
      expect(session.barDowns, 5);
    });

    test('rate is barDowns over shots', () {
      const session = HighScoreSession(shots: 20, autoBarDowns: 3, manualBarDowns: 2);
      expect(session.rate, closeTo(0.25, 1e-9));
    });

    test('rate is 0 when no shots were taken', () {
      const session = HighScoreSession(shots: 0, autoBarDowns: 0, manualBarDowns: 0);
      expect(session.rate, 0);
    });
  });

  group('HighScoreStore', () {
    test('load returns a zeroed session before anything is saved', () async {
      const store = HighScoreStore();
      final loaded = await store.load();

      expect(loaded.shots, 0);
      expect(loaded.autoBarDowns, 0);
      expect(loaded.manualBarDowns, 0);
    });

    test('considerSession sets the first high score from any session', () async {
      const store = HighScoreStore();

      await store.considerSession(sessionShots: 20, sessionAutoBarDowns: 15, sessionManualBarDowns: 5);
      final loaded = await store.load();

      expect(loaded.shots, 20);
      expect(loaded.barDowns, 20);
    });

    test('a strictly higher rate replaces the stored high score', () async {
      const store = HighScoreStore();
      await store.considerSession(sessionShots: 20, sessionAutoBarDowns: 10, sessionManualBarDowns: 0);

      await store.considerSession(sessionShots: 10, sessionAutoBarDowns: 8, sessionManualBarDowns: 0);
      final loaded = await store.load();

      expect(loaded.shots, 10, reason: '80% beats 50%');
      expect(loaded.barDowns, 8);
    });

    test('a strictly lower rate does not replace the stored high score', () async {
      const store = HighScoreStore();
      await store.considerSession(sessionShots: 10, sessionAutoBarDowns: 8, sessionManualBarDowns: 0);

      await store.considerSession(sessionShots: 20, sessionAutoBarDowns: 10, sessionManualBarDowns: 0);
      final loaded = await store.load();

      expect(loaded.shots, 10, reason: '80% beats 50%, order reversed from the test above');
      expect(loaded.barDowns, 8);
    });

    test('an equal rate with a higher bar-down total replaces the stored high score at 100%',
        () async {
      const store = HighScoreStore();
      await store.considerSession(sessionShots: 19, sessionAutoBarDowns: 19, sessionManualBarDowns: 0);

      await store.considerSession(sessionShots: 20, sessionAutoBarDowns: 20, sessionManualBarDowns: 0);
      final loaded = await store.load();

      expect(loaded.shots, 20, reason: '100% from 20 beats 100% from 19');
      expect(loaded.barDowns, 20);
    });

    test('an equal rate with a higher bar-down total replaces the stored high score below 100%',
        () async {
      const store = HighScoreStore();
      await store.considerSession(sessionShots: 10, sessionAutoBarDowns: 5, sessionManualBarDowns: 0);

      await store.considerSession(sessionShots: 16, sessionAutoBarDowns: 8, sessionManualBarDowns: 0);
      final loaded = await store.load();

      expect(loaded.shots, 16, reason: 'tiebreak generalizes to any tied rate, not just 100%');
      expect(loaded.barDowns, 8);
    });

    test('an equal rate with an equal or lower bar-down total does not replace the stored high score',
        () async {
      const store = HighScoreStore();
      await store.considerSession(sessionShots: 20, sessionAutoBarDowns: 10, sessionManualBarDowns: 0);

      await store.considerSession(sessionShots: 10, sessionAutoBarDowns: 5, sessionManualBarDowns: 0);
      final loaded = await store.load();

      expect(loaded.shots, 20, reason: 'same 50% rate but fewer bar downs must not win');
      expect(loaded.barDowns, 10);
    });

    test('a 0-shot session can still set the very first high score', () async {
      const store = HighScoreStore();

      await store.considerSession(sessionShots: 0, sessionAutoBarDowns: 0, sessionManualBarDowns: 0);
      final loaded = await store.load();

      expect(loaded.shots, 0);
      expect(loaded.barDowns, 0);
    });

    test(
        'a real first session with a 0% rate is still recorded as the high score, not mistaken for '
        '"nothing recorded yet"', () async {
      const store = HighScoreStore();

      await store.considerSession(sessionShots: 5, sessionAutoBarDowns: 0, sessionManualBarDowns: 0);
      final loaded = await store.load();

      expect(loaded.shots, 5,
          reason: 'a played 0%-rate session must overwrite the zeroed "no session yet" default');
      expect(loaded.barDowns, 0);
    });

    test('reset zeroes the persisted high score', () async {
      const store = HighScoreStore();
      await store.considerSession(sessionShots: 20, sessionAutoBarDowns: 10, sessionManualBarDowns: 0);

      await store.reset();
      final loaded = await store.load();

      expect(loaded.shots, 0);
      expect(loaded.autoBarDowns, 0);
      expect(loaded.manualBarDowns, 0);
    });

    test('after a reset, a fresh 0%-rate session can set the high score again', () async {
      const store = HighScoreStore();
      await store.considerSession(sessionShots: 20, sessionAutoBarDowns: 10, sessionManualBarDowns: 0);
      await store.reset();

      await store.considerSession(sessionShots: 8, sessionAutoBarDowns: 0, sessionManualBarDowns: 0);
      final loaded = await store.load();

      expect(loaded.shots, 8, reason: 'reset must clear back to "nothing recorded", not just to zeros');
    });

    test('resetting the high score leaves the independently-persisted all-time scoreboard untouched',
        () async {
      const highScoreStore = HighScoreStore();
      const allTimeStore = AllTimeScoreboardStore();
      await highScoreStore.considerSession(
        sessionShots: 20,
        sessionAutoBarDowns: 10,
        sessionManualBarDowns: 0,
      );
      await allTimeStore.foldInSession(
        sessionShots: 20,
        sessionAutoBarDowns: 10,
        sessionManualBarDowns: 0,
      );

      await highScoreStore.reset();

      final loadedHighScore = await highScoreStore.load();
      final loadedAllTime = await allTimeStore.load();
      expect(loadedHighScore.shots, 0);
      expect(loadedAllTime.shots, 20, reason: 'resetting one store must not touch the other');
    });
  });
}
