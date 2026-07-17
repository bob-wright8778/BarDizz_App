import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hockey_shot_tracker/history/session_history_store.dart';
import 'package:hockey_shot_tracker/history/session_record.dart';
import 'package:hockey_shot_tracker/screens/history_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _ThrowingHistoryStore extends SessionHistoryStore {
  const _ThrowingHistoryStore();

  @override
  Future<List<SessionRecord>> loadSessions() async => throw StateError('disk read failed');
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('shows an error message if loading history fails', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: HistoryScreen(store: _ThrowingHistoryStore())),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('historyErrorText')), findsOneWidget);
  });

  testWidgets('shows an empty message when there is no history', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: HistoryScreen()));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('historyEmptyText')), findsOneWidget);
  });

  testWidgets('lists saved sessions most-recent-first with count, duration, and goal',
      (tester) async {
    const store = SessionHistoryStore();
    await store.saveSession(
      SessionRecord(
        date: DateTime.utc(2026, 1, 1),
        duration: const Duration(minutes: 3),
        shotCount: 10,
        goal: 100,
      ),
    );
    await store.saveSession(
      SessionRecord(
        date: DateTime.utc(2026, 6, 1),
        duration: const Duration(minutes: 20),
        shotCount: 250,
        goal: 500,
      ),
    );

    await tester.pumpWidget(const MaterialApp(home: HistoryScreen()));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('historyList')), findsOneWidget);
    expect(find.textContaining('250 shots'), findsOneWidget);
    expect(find.textContaining('10 shots'), findsOneWidget);

    final firstShots = tester.widget<Text>(
      find.descendant(
        of: find.byKey(const Key('historyList')),
        matching: find.textContaining('shots'),
      ).first,
    );
    expect(firstShots.data, contains('250'));
  });
}
