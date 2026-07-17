import 'package:flutter_test/flutter_test.dart';
import 'package:hockey_shot_tracker/history/session_history_store.dart';
import 'package:hockey_shot_tracker/history/session_record.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('SessionHistoryStore', () {
    test('loadSessions returns an empty list before anything is saved', () async {
      const store = SessionHistoryStore();
      expect(await store.loadSessions(), isEmpty);
    });

    test('saveSession then loadSessions round-trips the same values', () async {
      const store = SessionHistoryStore();
      final session = SessionRecord(
        date: DateTime.utc(2026, 7, 16, 10),
        duration: const Duration(minutes: 5),
        shotCount: 42,
        goal: 500,
      );

      await store.saveSession(session);
      final loaded = await store.loadSessions();

      expect(loaded, hasLength(1));
      expect(loaded.single.shotCount, 42);
      expect(loaded.single.goal, 500);
      expect(loaded.single.duration, const Duration(minutes: 5));
    });

    test('sessions persist across separate store instances (survives restart)', () async {
      await const SessionHistoryStore().saveSession(
        SessionRecord(
          date: DateTime.utc(2026, 1, 1),
          duration: const Duration(minutes: 1),
          shotCount: 1,
          goal: 100,
        ),
      );

      final loaded = await const SessionHistoryStore().loadSessions();

      expect(loaded, hasLength(1));
    });

    test('loadSessions returns most-recent-first', () async {
      const store = SessionHistoryStore();
      await store.saveSession(
        SessionRecord(
          date: DateTime.utc(2026, 1, 1),
          duration: const Duration(minutes: 1),
          shotCount: 1,
          goal: 100,
        ),
      );
      await store.saveSession(
        SessionRecord(
          date: DateTime.utc(2026, 6, 1),
          duration: const Duration(minutes: 1),
          shotCount: 2,
          goal: 100,
        ),
      );

      final loaded = await store.loadSessions();

      expect(loaded.map((s) => s.shotCount), [2, 1]);
    });
  });
}
