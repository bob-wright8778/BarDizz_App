import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hockey_shot_tracker/audio/mic_level_controller.dart';
import 'package:hockey_shot_tracker/scoreboard/all_time_scoreboard_store.dart';
import 'package:hockey_shot_tracker/screens/session_screen.dart';
import 'package:hockey_shot_tracker/theme/design_tokens.dart';
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
  int startCallCount = 0;
  Object? startError;
  // When set, start() waits on this before resolving/throwing, so tests can
  // hold a start() call open to exercise races (dispose-while-starting,
  // double-tap-while-starting).
  Completer<void>? startGate;

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
    startCallCount++;
    if (startGate != null) await startGate!.future;
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

// Wraps the real store to let tests hold a save open (gate) or make it fail
// (throwError, applied to the first call only -- e.g. dispose's own
// unrelated fold shouldn't also be made to throw), for exercising races
// around _saveSession.
class GatedScoreboardStore extends AllTimeScoreboardStore {
  GatedScoreboardStore({this.gate, this.throwError});

  final Completer<void>? gate;
  final Object? throwError;
  int _calls = 0;

  @override
  Future<AllTimeScoreboard> foldInSession({
    required int sessionShots,
    required int sessionAutoBarDowns,
    required int sessionManualBarDowns,
  }) async {
    if (gate != null) await gate!.future;
    final isFirstCall = _calls == 0;
    _calls++;
    if (throwError != null && isFirstCall) throw throwError!;
    return super.foldInSession(
      sessionShots: sessionShots,
      sessionAutoBarDowns: sessionAutoBarDowns,
      sessionManualBarDowns: sessionManualBarDowns,
    );
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
    });

    testWidgets('auto-starts capture on load and shows Save Session with correction buttons',
        (tester) async {
      await pumpScreen(tester);

      expect(controller.started, isTrue);
      expect(find.widgetWithText(ElevatedButton, 'Save Session'), findsOneWidget);
      expect(find.byKey(const Key('shotIncrementButton')), findsOneWidget);
      expect(find.byKey(const Key('shotDecrementButton')), findsOneWidget);
      expect(find.byKey(const Key('barDownIncrementButton')), findsOneWidget);
      expect(find.byKey(const Key('barDownDecrementButton')), findsOneWidget);
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

    testWidgets(
        'shows an error and offers Start Session as retry when auto-start fails',
        (tester) async {
      controller.startError = StateError('Microphone permission denied.');
      await pumpScreen(tester);

      expect(find.byKey(const Key('sessionErrorText')), findsOneWidget);
      expect(find.widgetWithText(ElevatedButton, 'Start Session'), findsOneWidget);
      expect(find.byKey(const Key('shotIncrementButton')), findsNothing);
      expect(find.byKey(const Key('barDownIncrementButton')), findsNothing);

      controller.startError = null;
      await tester.tap(find.byKey(const Key('sessionActionButton')));
      await tester.pumpAndSettle();

      expect(controller.started, isTrue);
      expect(find.byKey(const Key('sessionErrorText')), findsNothing);
      expect(find.widgetWithText(ElevatedButton, 'Save Session'), findsOneWidget);
      expect(find.byKey(const Key('shotIncrementButton')), findsOneWidget);
    });
  });

  void expectBarDownGlow(TextStyle style) {
    expect(style.color, AppColors.iceBluePressed);
    expect(style.shadows, hasLength(2));
    expect(style.shadows![0].color, AppColors.iceBluePrimary.withValues(alpha: 0.6));
    expect(style.shadows![1].color, AppColors.iceBluePrimary.withValues(alpha: 0.35));
  }

  group('bar down design accents', () {
    testWidgets(
        'session bar down number uses the pressed ice-blue color with a primary-accent glow',
        (tester) async {
      await pumpScreen(tester);

      expectBarDownGlow(textAt(tester, 'sessionBarDownCountText').style!);
    });

    testWidgets("all-time bar downs stat matches the session dial's color and glow",
        (tester) async {
      const store = AllTimeScoreboardStore();
      await store.foldInSession(sessionShots: 1, sessionAutoBarDowns: 1, sessionManualBarDowns: 0);
      await pumpScreen(tester, scoreboardStore: store);

      expectBarDownGlow(textAt(tester, 'allTimeBarDownsValue').style!);
    });

    testWidgets('"THE BAR DOWN CHALLENGE" text uses the primary ice-blue accent', (tester) async {
      await pumpScreen(tester);

      final style = tester.widget<Text>(find.text('THE BAR DOWN CHALLENGE')).style!;
      expect(style.color, AppColors.iceBluePrimary);
    });
  });

  group('saving a session', () {
    testWidgets(
        'tapping Save Session folds the session shot/auto/manual counts into the persisted '
        'all-time totals, resets both dials to 0, and keeps capturing', (tester) async {
      const store = AllTimeScoreboardStore();
      await store.foldInSession(sessionShots: 20, sessionAutoBarDowns: 5, sessionManualBarDowns: 3);

      await pumpScreen(tester, scoreboardStore: store);

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

      await tester.tap(find.byKey(const Key('sessionActionButton')));
      await tester.pumpAndSettle();

      expect(controller.stopped, isFalse, reason: 'saving must not stop capture');
      expect(find.widgetWithText(ElevatedButton, 'Save Session'), findsOneWidget);
      expect(find.byKey(const Key('shotIncrementButton')), findsOneWidget);
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
        'saving after the scoreboard was reset elsewhere reflects the fresh persisted totals, '
        'not the stale in-memory copy loaded at startup', (tester) async {
      const store = AllTimeScoreboardStore();
      await store.foldInSession(sessionShots: 20, sessionAutoBarDowns: 5, sessionManualBarDowns: 3);

      await pumpScreen(tester, scoreboardStore: store);
      expect(textAt(tester, 'allTimeShotsValue').data, '20');

      controller.emitShotCount(2);
      await pumpAfterStreamEvent(tester);

      // Simulates Settings resetting the scoreboard on disk while this screen
      // stays alive underneath with its stale in-memory `_persisted` still
      // showing the pre-reset totals (no re-fetch happens on navigating back).
      await store.reset();

      await tester.tap(find.byKey(const Key('sessionActionButton')));
      await tester.pumpAndSettle();

      expect(textAt(tester, 'allTimeShotsValue').data, '2');
      final loaded = await store.load();
      expect(loaded.shots, 2);
    });
  });

  group('live all-time strip updates', () {
    testWidgets('all-time shots update live as auto-detected shots arrive, before a save',
        (tester) async {
      const store = AllTimeScoreboardStore();
      await store.foldInSession(sessionShots: 10, sessionAutoBarDowns: 0, sessionManualBarDowns: 0);

      await pumpScreen(tester, scoreboardStore: store);

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

      controller.emitBarDownCount(1);
      await pumpAfterStreamEvent(tester);
      expect(textAt(tester, 'sessionBarDownCountText').data, '1');

      await tester.tap(find.byKey(const Key('barDownIncrementButton')));
      await tester.pump();
      expect(textAt(tester, 'sessionBarDownCountText').data, '2');

      await tester.tap(find.byKey(const Key('sessionActionButton')));
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

      await tester.tap(find.byKey(const Key('barDownDecrementButton')));
      await tester.pump();
      expect(textAt(tester, 'sessionBarDownCountText').data, '0');

      controller.emitBarDownCount(1);
      await pumpAfterStreamEvent(tester);
      expect(textAt(tester, 'sessionBarDownCountText').data, '1');

      await tester.tap(find.byKey(const Key('barDownDecrementButton')));
      await tester.pump();
      expect(textAt(tester, 'sessionBarDownCountText').data, '1');

      await tester.tap(find.byKey(const Key('sessionActionButton')));
      await tester.pumpAndSettle();

      final loaded = await store.load();
      expect(loaded.autoBarDowns, 1);
      expect(loaded.manualBarDowns, 0);
    });
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

  testWidgets('disposing while capturing stops the controller to release the mic', (tester) async {
    await pumpScreen(tester);

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));

    expect(controller.stopped, isTrue);
  });

  testWidgets('disposing while capturing folds the in-progress session into the scoreboard',
      (tester) async {
    const store = AllTimeScoreboardStore();
    await pumpScreen(tester, scoreboardStore: store);

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
      'a system back attempt while capturing asks Android to background the app instead of exiting',
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

    final popScope = tester.widget<PopScope>(find.byWidgetPredicate((w) => w is PopScope));
    expect(popScope.canPop, isFalse);
    popScope.onPopInvokedWithResult!(false, null);

    expect(calls, hasLength(1));
    expect(calls.single.method, 'moveTaskToBack');
  });

  testWidgets('back is allowed to pop normally when capture failed to start', (tester) async {
    controller.startError = StateError('Microphone permission denied.');
    await pumpScreen(tester);

    final popScope = tester.widget<PopScope>(find.byWidgetPredicate((w) => w is PopScope));
    expect(popScope.canPop, isTrue);
  });

  group('lifecycle and re-entrancy races', () {
    testWidgets(
        'disposing while the initial auto-start is still in flight releases capture once it '
        'resolves instead of leaking it', (tester) async {
      final gate = Completer<void>();
      controller.startGate = gate;

      await pumpScreen(tester);
      expect(controller.stopped, isFalse, reason: 'nothing to stop yet -- start() has not resolved');

      await tester.pumpWidget(const MaterialApp(home: SizedBox()));

      gate.complete();
      await tester.pump();
      await tester.pump();

      expect(controller.started, isTrue, reason: 'the in-flight start() still completed');
      expect(controller.stopped, isTrue,
          reason: 'the now-orphaned capture must be released once start() resolves post-dispose');
    });

    testWidgets('the button disables while the initial auto-start is in flight', (tester) async {
      final gate = Completer<void>();
      controller.startGate = gate;

      await pumpScreen(tester);

      var button = tester.widget<ElevatedButton>(find.byKey(const Key('sessionActionButton')));
      expect(button.onPressed, isNull);

      gate.complete();
      await tester.pumpAndSettle();

      button = tester.widget<ElevatedButton>(find.byKey(const Key('sessionActionButton')));
      expect(button.onPressed, isNotNull);
    });

    testWidgets(
        'a tap while the initial auto-start is in flight does not trigger a second start() call',
        (tester) async {
      final gate = Completer<void>();
      controller.startGate = gate;

      await pumpScreen(tester);

      await tester.tap(find.byKey(const Key('sessionActionButton')));
      await tester.pump();

      expect(controller.startCallCount, 1);

      gate.complete();
      await tester.pumpAndSettle();
    });

    testWidgets(
        'auto-detected shots keep counting correctly across a save (the raw baseline is not '
        'reset mid-capture, only session-scoped counts are)', (tester) async {
      await pumpScreen(tester);

      controller.emitShotCount(3);
      await pumpAfterStreamEvent(tester);
      expect(textAt(tester, 'sessionShotCountText').data, '3');

      await tester.tap(find.byKey(const Key('sessionActionButton')));
      await tester.pumpAndSettle();
      expect(textAt(tester, 'sessionShotCountText').data, '0');

      // The controller's absolute count keeps climbing across the save (it
      // never resets mid-capture) -- this must still translate into the
      // correct +1 delta, not a bogus jump from a wrongly-reset raw baseline.
      controller.emitShotCount(4);
      await pumpAfterStreamEvent(tester);
      expect(textAt(tester, 'sessionShotCountText').data, '1');
    });

    testWidgets(
        'the button disables while a save is in flight, preventing a double-tap double-fold',
        (tester) async {
      final gate = Completer<void>();
      final store = GatedScoreboardStore(gate: gate);

      await pumpScreen(tester, scoreboardStore: store);
      controller.emitShotCount(5);
      await pumpAfterStreamEvent(tester);

      await tester.tap(find.byKey(const Key('sessionActionButton')));
      await tester.pump();

      final button = tester.widget<ElevatedButton>(find.byKey(const Key('sessionActionButton')));
      expect(button.onPressed, isNull);

      gate.complete();
      await tester.pumpAndSettle();

      final buttonAfter =
          tester.widget<ElevatedButton>(find.byKey(const Key('sessionActionButton')));
      expect(buttonAfter.onPressed, isNotNull);

      final loaded = await store.load();
      expect(loaded.shots, 5, reason: 'exactly one fold should have happened');
    });

    testWidgets(
        'disposing while a save is in flight does not double-fold the counts already handed '
        'off to that save', (tester) async {
      final gate = Completer<void>();
      final store = GatedScoreboardStore(gate: gate);

      await pumpScreen(tester, scoreboardStore: store);
      controller.emitShotCount(5);
      await pumpAfterStreamEvent(tester);

      await tester.tap(find.byKey(const Key('sessionActionButton')));
      await tester.pump();
      expect(textAt(tester, 'sessionShotCountText').data, '0',
          reason: 'the save optimistically zeroed the live dial before awaiting the fold');

      await tester.pumpWidget(const MaterialApp(home: SizedBox()));

      gate.complete();
      await tester.pump();
      await tester.pump();

      final loaded = await store.load();
      expect(loaded.shots, 5,
          reason: 'dispose skips its own fold while a save is in flight, so only the '
              "in-flight save's own fold of the 5 shots applies -- not a double-count");
    });

    testWidgets(
        'a shot arriving between tapping Save Session and disposing is folded once the save '
        'settles, not silently lost', (tester) async {
      final gate = Completer<void>();
      final store = GatedScoreboardStore(gate: gate);

      await pumpScreen(tester, scoreboardStore: store);
      controller.emitShotCount(5);
      await pumpAfterStreamEvent(tester);

      await tester.tap(find.byKey(const Key('sessionActionButton')));
      await tester.pump();

      // Lands after the save's optimistic reset but before it resolves --
      // belongs to the next session. Dispose skips its own fold (a save is
      // in flight), so this save's own finally block must fold it instead.
      controller.emitShotCount(6);
      await pumpAfterStreamEvent(tester);
      expect(textAt(tester, 'sessionShotCountText').data, '1');

      await tester.pumpWidget(const MaterialApp(home: SizedBox()));

      gate.complete();
      await tester.pump();
      await tester.pump();

      final loaded = await store.load();
      expect(loaded.shots, 6,
          reason: '5 from the in-flight save + 1 from its own finally-block fold of '
              'the post-reset shot, nothing lost');
    });

    testWidgets('a save error after the widget is disposed does not throw (mounted guard)',
        (tester) async {
      final gate = Completer<void>();
      final store = GatedScoreboardStore(gate: gate, throwError: StateError('disk full'));

      await pumpScreen(tester, scoreboardStore: store);

      await tester.tap(find.byKey(const Key('sessionActionButton')));
      await tester.pump();

      await tester.pumpWidget(const MaterialApp(home: SizedBox()));

      gate.complete();
      // If _saveSession's catch block were missing its mounted guard, this
      // would call setState after dispose and fail the test.
      await tester.pump();
      await tester.pump();
    });

    testWidgets(
        'a save that fails after the widget is disposed does not lose the shots it was '
        'folding', (tester) async {
      final gate = Completer<void>();
      final store = GatedScoreboardStore(gate: gate, throwError: StateError('disk full'));

      await pumpScreen(tester, scoreboardStore: store);
      controller.emitShotCount(5);
      await pumpAfterStreamEvent(tester);

      await tester.tap(find.byKey(const Key('sessionActionButton')));
      await tester.pump();

      await tester.pumpWidget(const MaterialApp(home: SizedBox()));

      gate.complete();
      // The first foldInSession call throws; the catch block must restore
      // the 5 shots unconditionally (not just if mounted) so the finally
      // block's leftover-fold can persist them via a second call instead of
      // losing them silently.
      await tester.pump();
      await tester.pump();

      final loaded = await store.load();
      expect(loaded.shots, 5,
          reason: 'the failed fold must not lose the shots it was trying to save');
    });

    testWidgets(
        'back-pop stays blocked immediately after a successful save (capture is still running)',
        (tester) async {
      await pumpScreen(tester);

      await tester.tap(find.byKey(const Key('sessionActionButton')));
      await tester.pumpAndSettle();

      final popScope = tester.widget<PopScope>(find.byWidgetPredicate((w) => w is PopScope));
      expect(popScope.canPop, isFalse);
    });
  });
}
