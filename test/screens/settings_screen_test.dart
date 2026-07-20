import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hockey_shot_tracker/scoreboard/all_time_scoreboard_store.dart';
import 'package:hockey_shot_tracker/screens/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('no debug meter entry when onDebugMeterTap is not provided', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: const SettingsScreen()),
    );

    expect(find.byKey(const Key('debugMeterTile')), findsNothing);
  });

  testWidgets('tapping Debug meter calls onDebugMeterTap', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsScreen(onDebugMeterTap: () => tapped = true),
      ),
    );

    await tester.tap(find.byKey(const Key('debugMeterTile')));
    await tester.pump();

    expect(tapped, isTrue);
  });

  group('all-time bar-down breakdown', () {
    testWidgets('displays sound-only and manually-added counts summing to the bar-down total',
        (tester) async {
      const store = AllTimeScoreboardStore();
      await store.foldInSession(sessionShots: 20, sessionAutoBarDowns: 5, sessionManualBarDowns: 3);

      await tester.pumpWidget(
        MaterialApp(home: SettingsScreen(scoreboardStore: store)),
      );
      await tester.pumpAndSettle();

      final soundOnly = tester.widget<Text>(find.byKey(const Key('soundOnlyBarDownsValue')));
      final manual = tester.widget<Text>(find.byKey(const Key('manualBarDownsValue')));
      expect(soundOnly.data, contains('5'));
      expect(manual.data, contains('3'));

      final loaded = await store.load();
      expect(loaded.autoBarDowns + loaded.manualBarDowns, loaded.barDowns);
      expect(loaded.barDowns, 8);
    });

    testWidgets('reflects zeroed counts when nothing has been recorded yet', (tester) async {
      const store = AllTimeScoreboardStore();

      await tester.pumpWidget(
        MaterialApp(home: SettingsScreen(scoreboardStore: store)),
      );
      await tester.pumpAndSettle();

      final soundOnly = tester.widget<Text>(find.byKey(const Key('soundOnlyBarDownsValue')));
      final manual = tester.widget<Text>(find.byKey(const Key('manualBarDownsValue')));
      expect(soundOnly.data, contains('0'));
      expect(manual.data, contains('0'));
    });
  });

  group('Reset Scoreboard', () {
    testWidgets('tapping Reset Scoreboard opens a confirmation dialog without resetting yet',
        (tester) async {
      const store = AllTimeScoreboardStore();
      await store.foldInSession(sessionShots: 20, sessionAutoBarDowns: 5, sessionManualBarDowns: 3);

      await tester.pumpWidget(
        MaterialApp(home: SettingsScreen(scoreboardStore: store)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('resetScoreboardTile')));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      final loaded = await store.load();
      expect(loaded.shots, 20);
    });

    testWidgets('cancelling the confirmation dialog leaves the scoreboard untouched', (tester) async {
      const store = AllTimeScoreboardStore();
      await store.foldInSession(sessionShots: 20, sessionAutoBarDowns: 5, sessionManualBarDowns: 3);

      await tester.pumpWidget(
        MaterialApp(home: SettingsScreen(scoreboardStore: store)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('resetScoreboardTile')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('resetScoreboardCancelButton')));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      final loaded = await store.load();
      expect(loaded.shots, 20);
      expect(loaded.autoBarDowns, 5);
      expect(loaded.manualBarDowns, 3);
    });

    testWidgets('confirming the dialog zeroes shots, bar downs, and the breakdown counters',
        (tester) async {
      const store = AllTimeScoreboardStore();
      await store.foldInSession(sessionShots: 20, sessionAutoBarDowns: 5, sessionManualBarDowns: 3);

      await tester.pumpWidget(
        MaterialApp(home: SettingsScreen(scoreboardStore: store)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('resetScoreboardTile')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('resetScoreboardConfirmButton')));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      final loaded = await store.load();
      expect(loaded.shots, 0);
      expect(loaded.autoBarDowns, 0);
      expect(loaded.manualBarDowns, 0);

      final soundOnly = tester.widget<Text>(find.byKey(const Key('soundOnlyBarDownsValue')));
      final manual = tester.widget<Text>(find.byKey(const Key('manualBarDownsValue')));
      expect(soundOnly.data, contains('0'));
      expect(manual.data, contains('0'));
    });
  });
}
