import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hockey_shot_tracker/audio/mic_level_controller.dart';
import 'package:hockey_shot_tracker/scoreboard/all_time_scoreboard_store.dart';
import 'package:hockey_shot_tracker/screens/session_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _systemNavChannel = MethodChannel('hockey_shot_tracker/system_nav');

class FakeMicLevelController implements MicLevelController {
  final StreamController<double> _levelController =
      StreamController<double>.broadcast();
  final StreamController<int> _shotCountController =
      StreamController<int>.broadcast();
  final StreamController<int> _barDownCountController =
      StreamController<int>.broadcast();
  bool started = false;
  bool stopped = false;
  Object? startError;

  @override
  Stream<double> get levels => _levelController.stream;

  @override
  Stream<int> get shotCount => _shotCountController.stream;

  @override
  Stream<int> get barDownCount => _barDownCountController.stream;

  @override
  bool get isCapturing => started && !stopped;

  @override
  Future<void> start() async {
    if (startError != null) throw startError!;
    started = true;
  }

  @override
  Future<void> stop() async {
    stopped = true;
  }

  void emitShotCount(int count) => _shotCountController.add(count);

  void emitBarDownCount(int count) => _barDownCountController.add(count);

  void dispose() {
    _levelController.close();
    _shotCountController.close();
    _barDownCountController.close();
  }
}

void main() {
  late FakeMicLevelController controller;

  setUp(() {
    controller = FakeMicLevelController();
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    controller.dispose();
  });

  Future<void> pumpScreen(
    WidgetTester tester, {
    AllTimeScoreboardStore scoreboardStore = const AllTimeScoreboardStore(),
    VoidCallback? onSettingsTap,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SessionScreen(
          controller: controller,
          scoreboardStore: scoreboardStore,
          onSettingsTap: onSettingsTap,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Text textAt(WidgetTester tester, String key) =>
      tester.widget<Text>(find.byKey(Key(key)));

  // A stream event's setState lands on the microtask queue behind the pump
  // call that's already in flight, so the widget needs one settling pump
  // after the render pump before its rebuilt output is observable.
  Future<void> pumpAfterStreamEvent(WidgetTester tester) async {
    await tester.pump();
    await tester.pump();
  }

  group('initial render', () {
    testWidgets('shows the BAR DIZZ banner and no goal/progress/history widgets',
        (tester) async {
      await pumpScreen(tester);

      expect(find.text('BAR DIZZ'), findsOneWidget);
      expect(find.text('THE BAR DOWN CHALLENGE'), findsOneWidget);

      expect(find.byKey(const Key('editGoalButton')), findsNothing);
      expect(find.byKey(const Key('goalText')), findsNothing);
      expect(find.byKey(const Key('goalInputField')), findsNothing);
      expect(find.byKey(const Key('saveGoalButton')), findsNothing);
      expect(find.byKey(const Key('progressBar')), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.textContaining('of '), findsNothing);
      expect(find.byKey(const Key('historyButton')), findsNothing);
      expect(find.widgetWithText(ElevatedButton, 'Start Session'), findsOneWidget);
    });

    testWidgets('both session dials show 0 and the all-time strip shows the persisted totals',
        (tester) async {
      const store = AllTimeScoreboardStore();
      await store.foldInSession(sessionShots: 20, sessionAutoBarDowns: 5, sessionManualBarDowns: 3);

      await pumpScreen(tester, scoreboardStore: store);

      expect(textAt(tester, 'sessionShotCountText').data, '0');
      expect(textAt(tester, 'sessionBarDownCountText').data, '0');
      expect(textAt(tester, 'allTimeShotsValue').data, '20');
      expect(textAt(tester, 'allTimeBarDownsValue').data, '8');
      expect(textAt(tester, 'allTimeRateValue').data, '40.0%');
    });

    testWidgets('all-time strip shows zeroed totals when nothing is persisted yet',
        (tester) async {
      await pumpScreen(tester);

      expect(textAt(tester, 'allTimeShotsValue').data, '0');
      expect(textAt(tester, 'allTimeBarDownsValue').data, '0');
      expect(textAt(tester, 'allTimeRateValue').data, '0.0%');
    });

    testWidgets('correction buttons are hidden until a session is running', (tester) async {
      await pumpScreen(tester);

      expect(find.byKey(const Key('shotIncrementButton')), findsNothing);
      expect(find.byKey(const Key('shotDecrementButton')), findsNothing);
      expect(find.byKey(const Key('barDownIncrementButton')), findsNothing);
      expect(find.byKey(const Key('barDownDecrementButton')), findsNothing);
    });
  });

  group('starting and ending a session', () {
    testWidgets('starting a session calls controller.start and reveals correction buttons',
        (tester) async {
      await pumpScreen(tester);

      await tester.tap(find.byKey(const Key('sessionToggleButton')));
      await tester.pumpAndSettle();

      expect(controller.started, isTrue);
      expect(find.widgetWithText(ElevatedButton, 'End Session'), findsOneWidget);
      expect(find.byKey(const Key('shotIncrementButton')), findsOneWidget);
      expect(find.byKey(const Key('shotDecrementButton')), findsOneWidget);
      expect(find.byKey(const Key('barDownIncrementButton')), findsOneWidget);
      expect(find.byKey(const Key('barDownDecrementButton')), findsOneWidget);
    });

    testWidgets('ending a session calls controller.stop and hides correction buttons',
        (tester) async {
      await pumpScreen(tester);
      await tester.tap(find.byKey(const Key('sessionToggleButton')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('sessionToggleButton')));
      await tester.pumpAndSettle();

      expect(controller.stopped, isTrue);
      expect(find.widgetWithText(ElevatedButton, 'Start Session'), findsOneWidget);
      expect(find.byKey(const Key('shotIncrementButton')), findsNothing);
    });

    testWidgets(
        'ending a session folds the session shot/auto/manual counts into the persisted '
        'all-time totals and resets both dials to 0', (tester) async {
      const store = AllTimeScoreboardStore();
      await store.foldInSession(sessionShots: 20, sessionAutoBarDowns: 5, sessionManualBarDowns: 3);

      await pumpScreen(tester, scoreboardStore: store);
      await tester.tap(find.byKey(const Key('sessionToggleButton')));
      await tester.pumpAndSettle();

      controller.emitShotCount(5);
      await pumpAfterStreamEvent(tester);
      await tester.tap(find.byKey(const Key('shotIncrementButton')));
      await tester.tap(find.byKey(const Key('shotIncrementButton')));
      await tester.pump();
      expect(textAt(tester, 'sessionShotCountText').data, '7');

      controller.emitBarDownCount(2);
      await pumpAfterStreamEvent(tester);
      await tester.tap(find.byKey(const Key('barDownIncrementButton')));
      await tester.pump();
      expect(textAt(tester, 'sessionBarDownCountText').data, '3');

      await tester.tap(find.byKey(const Key('sessionToggleButton')));
      await tester.pumpAndSettle();

      expect(textAt(tester, 'sessionShotCountText').data, '0');
      expect(textAt(tester, 'sessionBarDownCountText').data, '0');
      expect(textAt(tester, 'allTimeShotsValue').data, '27');
      expect(textAt(tester, 'allTimeBarDownsValue').data, '11');

      final loaded = await store.load();
      expect(loaded.shots, 27);
      expect(loaded.autoBarDowns, 7);
      expect(loaded.manualBarDowns, 4);
    });

    testWidgets(
        'ending a session after the scoreboard was reset elsewhere reflects the fresh '
        'persisted totals, not the stale in-memory copy loaded at startup', (tester) async {
      const store = AllTimeScoreboardStore();
      await store.foldInSession(sessionShots: 20, sessionAutoBarDowns: 5, sessionManualBarDowns: 3);

      await pumpScreen(tester, scoreboardStore: store);
      expect(textAt(tester, 'allTimeShotsValue').data, '20');

      await tester.tap(find.byKey(const Key('sessionToggleButton')));
      await tester.pumpAndSettle();

      controller.emitShotCount(2);
      await pumpAfterStreamEvent(tester);

      // Simulates Settings resetting the scoreboard on disk while this screen
      // stays alive underneath with its stale in-memory `_persisted` still
      // showing the pre-reset totals (no re-fetch happens on navigating back).
      await store.reset();

      await tester.tap(find.byKey(const Key('sessionToggleButton')));
      await tester.pumpAndSettle();

      expect(textAt(tester, 'allTimeShotsValue').data, '2');
      final loaded = await store.load();
      expect(loaded.shots, 2);
    });
  });

  group('live all-time strip updates', () {
    testWidgets('all-time shots update live as auto-detected shots arrive, before session end',
        (tester) async {
      const store = AllTimeScoreboardStore();
      await store.foldInSession(sessionShots: 10, sessionAutoBarDowns: 0, sessionManualBarDowns: 0);

      await pumpScreen(tester, scoreboardStore: store);
      await tester.tap(find.byKey(const Key('sessionToggleButton')));
      await tester.pumpAndSettle();

      controller.emitShotCount(1);
      await pumpAfterStreamEvent(tester);
      expect(textAt(tester, 'sessionShotCountText').data, '1');
      expect(textAt(tester, 'allTimeShotsValue').data, '11');

      controller.emitShotCount(4);
      await pumpAfterStreamEvent(tester);
      expect(textAt(tester, 'sessionShotCountText').data, '4');
      expect(textAt(tester, 'allTimeShotsValue').data, '14');
    });

    testWidgets('all-time shots update live from manual +/- correction on the shot dial',
        (tester) async {
      await pumpScreen(tester);
      await tester.tap(find.byKey(const Key('sessionToggleButton')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('shotIncrementButton')));
      await tester.pump();
      expect(textAt(tester, 'sessionShotCountText').data, '1');
      expect(textAt(tester, 'allTimeShotsValue').data, '1');

      await tester.tap(find.byKey(const Key('shotDecrementButton')));
      await tester.pump();
      expect(textAt(tester, 'sessionShotCountText').data, '0');
      expect(textAt(tester, 'allTimeShotsValue').data, '0');
    });

    testWidgets('all-time bar downs and rate update live as the bar down dial changes',
        (tester) async {
      const store = AllTimeScoreboardStore();
      await store.foldInSession(sessionShots: 8, sessionAutoBarDowns: 2, sessionManualBarDowns: 0);

      await pumpScreen(tester, scoreboardStore: store);
      await tester.tap(find.byKey(const Key('sessionToggleButton')));
      await tester.pumpAndSettle();

      controller.emitShotCount(2);
      controller.emitBarDownCount(1);
      await pumpAfterStreamEvent(tester);
      expect(textAt(tester, 'allTimeShotsValue').data, '10');
      expect(textAt(tester, 'allTimeBarDownsValue').data, '3');
      expect(textAt(tester, 'allTimeRateValue').data, '30.0%');

      await tester.tap(find.byKey(const Key('barDownIncrementButton')));
      await tester.pump();
      expect(textAt(tester, 'allTimeBarDownsValue').data, '4');
      expect(textAt(tester, 'allTimeRateValue').data, '40.0%');
    });
  });

  group('sound-confirmed vs. manual bar down bucketing', () {
    testWidgets(
        'a sound-confirmed bar down and a manual + both raise the dial, but land in the '
        'auto vs. manual bucket respectively', (tester) async {
      const store = AllTimeScoreboardStore();

      await pumpScreen(tester, scoreboardStore: store);
      await tester.tap(find.byKey(const Key('sessionToggleButton')));
      await tester.pumpAndSettle();

      controller.emitBarDownCount(1);
      await pumpAfterStreamEvent(tester);
      expect(textAt(tester, 'sessionBarDownCountText').data, '1');

      await tester.tap(find.byKey(const Key('barDownIncrementButton')));
      await tester.pump();
      expect(textAt(tester, 'sessionBarDownCountText').data, '2');

      await tester.tap(find.byKey(const Key('sessionToggleButton')));
      await tester.pumpAndSettle();

      final loaded = await store.load();
      expect(loaded.autoBarDowns, 1);
      expect(loaded.manualBarDowns, 1);
    });

    testWidgets(
        'the bar down dial\'s - floors the manual tally at 0 without ever going negative or '
        'touching the auto (sound-confirmed) count', (tester) async {
      const store = AllTimeScoreboardStore();

      await pumpScreen(tester, scoreboardStore: store);
      await tester.tap(find.byKey(const Key('sessionToggleButton')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('barDownDecrementButton')));
      await tester.pump();
      expect(textAt(tester, 'sessionBarDownCountText').data, '0');

      controller.emitBarDownCount(1);
      await pumpAfterStreamEvent(tester);
      expect(textAt(tester, 'sessionBarDownCountText').data, '1');

      await tester.tap(find.byKey(const Key('barDownDecrementButton')));
      await tester.pump();
      expect(textAt(tester, 'sessionBarDownCountText').data, '1');

      await tester.tap(find.byKey(const Key('sessionToggleButton')));
      await tester.pumpAndSettle();

      final loaded = await store.load();
      expect(loaded.autoBarDowns, 1);
      expect(loaded.manualBarDowns, 0);
    });
  });

  testWidgets('shows an error message if starting the session fails', (tester) async {
    controller.startError = StateError('Microphone permission denied.');
    await pumpScreen(tester);

    await tester.tap(find.byKey(const Key('sessionToggleButton')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('sessionErrorText')), findsOneWidget);
  });

  testWidgets('no settings button when onSettingsTap is not provided', (tester) async {
    await pumpScreen(tester);

    expect(find.byKey(const Key('settingsButton')), findsNothing);
  });

  testWidgets('tapping the settings button calls onSettingsTap', (tester) async {
    var tapped = false;
    await pumpScreen(tester, onSettingsTap: () => tapped = true);

    await tester.tap(find.byKey(const Key('settingsButton')));
    await tester.pump();

    expect(tapped, isTrue);
  });

  testWidgets('disposing mid-session stops the controller to release the mic', (tester) async {
    await pumpScreen(tester);
    await tester.tap(find.byKey(const Key('sessionToggleButton')));
    await tester.pumpAndSettle();

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));

    expect(controller.stopped, isTrue);
  });

  testWidgets('disposing mid-session folds the in-progress session into the scoreboard', (tester) async {
    const store = AllTimeScoreboardStore();
    await pumpScreen(tester, scoreboardStore: store);
    await tester.tap(find.byKey(const Key('sessionToggleButton')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('shotIncrementButton')));
    await tester.tap(find.byKey(const Key('shotIncrementButton')));
    await tester.tap(find.byKey(const Key('barDownIncrementButton')));
    await tester.pump();
    controller.emitBarDownCount(1);
    await pumpAfterStreamEvent(tester);

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));

    final persisted = await store.load();
    expect(persisted.shots, 2, reason: 'the two manual shot corrections should not be lost');
    expect(persisted.autoBarDowns, 1, reason: 'the sound-confirmed bar down should not be lost');
    expect(persisted.manualBarDowns, 1, reason: 'the manual bar-down correction should not be lost');
  });

  testWidgets(
      'a system back attempt while running asks Android to background the app instead of exiting',
      (tester) async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      _systemNavChannel,
      (call) async {
        calls.add(call);
        return null;
      },
    );
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_systemNavChannel, null);
    });

    await pumpScreen(tester);
    await tester.tap(find.byKey(const Key('sessionToggleButton')));
    await tester.pumpAndSettle();

    final popScope = tester.widget<PopScope>(find.byWidgetPredicate((w) => w is PopScope));
    expect(popScope.canPop, isFalse);
    popScope.onPopInvokedWithResult!(false, null);

    expect(calls, hasLength(1));
    expect(calls.single.method, 'moveTaskToBack');
  });

  testWidgets('back is allowed to pop normally when no session is running', (tester) async {
    await pumpScreen(tester);

    final popScope = tester.widget<PopScope>(find.byWidgetPredicate((w) => w is PopScope));
    expect(popScope.canPop, isTrue);
  });
}
