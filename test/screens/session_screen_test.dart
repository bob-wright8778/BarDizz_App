import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hockey_shot_tracker/audio/mic_level_controller.dart';
import 'package:hockey_shot_tracker/history/session_history_store.dart';
import 'package:hockey_shot_tracker/screens/session_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _systemNavChannel = MethodChannel('hockey_shot_tracker/system_nav');

class FakeMicLevelController implements MicLevelController {
  final StreamController<double> _levelController =
      StreamController<double>.broadcast();
  final StreamController<int> _shotCountController =
      StreamController<int>.broadcast();
  bool started = false;
  bool stopped = false;
  Object? startError;

  @override
  Stream<double> get levels => _levelController.stream;

  @override
  Stream<int> get shotCount => _shotCountController.stream;

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

  void dispose() {
    _levelController.close();
    _shotCountController.close();
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

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(home: SessionScreen(controller: controller)),
    );
  }

  testWidgets('shows 0 shots, the default 10000 goal, and a Start button initially',
      (tester) async {
    await pumpScreen(tester);

    expect(find.text('0'), findsOneWidget);
    expect(find.text('of 10000'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Start Session'), findsOneWidget);
    expect(find.byKey(const Key('incrementButton')), findsNothing);
  });

  testWidgets('starting a session calls controller.start and reveals +/- controls',
      (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.byKey(const Key('sessionToggleButton')));
    await tester.pump();

    expect(controller.started, isTrue);
    expect(find.widgetWithText(ElevatedButton, 'End Session'), findsOneWidget);
    expect(find.byKey(const Key('incrementButton')), findsOneWidget);
    expect(find.byKey(const Key('decrementButton')), findsOneWidget);
  });

  testWidgets('count updates live as shots are auto-detected', (tester) async {
    await pumpScreen(tester);
    await tester.tap(find.byKey(const Key('sessionToggleButton')));
    await tester.pump();

    controller.emitShotCount(1);
    await tester.pump();
    expect(find.text('1'), findsOneWidget);

    controller.emitShotCount(3);
    await tester.pump();
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('the + button increments the count immediately', (tester) async {
    await pumpScreen(tester);
    await tester.tap(find.byKey(const Key('sessionToggleButton')));
    await tester.pump();

    await tester.tap(find.byKey(const Key('incrementButton')));
    await tester.pump();

    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('the - button decrements the count immediately, floored at 0',
      (tester) async {
    await pumpScreen(tester);
    await tester.tap(find.byKey(const Key('sessionToggleButton')));
    await tester.pump();

    await tester.tap(find.byKey(const Key('decrementButton')));
    await tester.pump();
    expect(find.text('0'), findsOneWidget);

    await tester.tap(find.byKey(const Key('incrementButton')));
    await tester.tap(find.byKey(const Key('incrementButton')));
    await tester.pump();
    expect(find.text('2'), findsOneWidget);

    await tester.tap(find.byKey(const Key('decrementButton')));
    await tester.pump();
    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('manual adjustments and auto-detections both contribute to the count',
      (tester) async {
    await pumpScreen(tester);
    await tester.tap(find.byKey(const Key('sessionToggleButton')));
    await tester.pump();

    await tester.tap(find.byKey(const Key('incrementButton')));
    await tester.pump();
    expect(find.text('1'), findsOneWidget);

    controller.emitShotCount(1);
    await tester.pump();
    expect(find.text('2'), findsOneWidget);

    controller.emitShotCount(2);
    await tester.pump();
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('progress bar reflects count against the goal', (tester) async {
    await pumpScreen(tester);
    await tester.tap(find.byKey(const Key('sessionToggleButton')));
    await tester.pump();

    controller.emitShotCount(5000);
    await tester.pump();

    final bar = tester.widget<LinearProgressIndicator>(
      find.byKey(const Key('progressBar')),
    );
    expect(bar.value, closeTo(0.5, 1e-9));
  });

  testWidgets('editing the goal updates the displayed goal and progress',
      (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.byKey(const Key('editGoalButton')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('goalInputField')), '100');
    await tester.tap(find.byKey(const Key('saveGoalButton')));
    await tester.pumpAndSettle();

    expect(find.text('of 100'), findsOneWidget);

    await tester.tap(find.byKey(const Key('sessionToggleButton')));
    await tester.pump();
    controller.emitShotCount(50);
    await tester.pump();

    final bar = tester.widget<LinearProgressIndicator>(
      find.byKey(const Key('progressBar')),
    );
    expect(bar.value, closeTo(0.5, 1e-9));
  });

  testWidgets('ending a session calls controller.stop and hides +/- controls',
      (tester) async {
    await pumpScreen(tester);
    await tester.tap(find.byKey(const Key('sessionToggleButton')));
    await tester.pump();

    await tester.tap(find.byKey(const Key('sessionToggleButton')));
    await tester.pump();

    expect(controller.stopped, isTrue);
    expect(find.widgetWithText(ElevatedButton, 'Start Session'), findsOneWidget);
    expect(find.byKey(const Key('incrementButton')), findsNothing);
  });

  testWidgets('shows an error message if starting the session fails', (tester) async {
    controller.startError = StateError('Microphone permission denied.');
    await pumpScreen(tester);

    await tester.tap(find.byKey(const Key('sessionToggleButton')));
    await tester.pump();

    expect(find.byKey(const Key('sessionErrorText')), findsOneWidget);
  });

  testWidgets('no settings button when onSettingsTap is not provided', (tester) async {
    await pumpScreen(tester);

    expect(find.byKey(const Key('settingsButton')), findsNothing);
  });

  testWidgets('tapping the settings button calls onSettingsTap', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: SessionScreen(controller: controller, onSettingsTap: () => tapped = true),
      ),
    );

    await tester.tap(find.byKey(const Key('settingsButton')));
    await tester.pump();

    expect(tapped, isTrue);
  });

  testWidgets('disposing mid-session stops the controller to release the mic',
      (tester) async {
    await pumpScreen(tester);
    await tester.tap(find.byKey(const Key('sessionToggleButton')));
    await tester.pump();

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));

    expect(controller.stopped, isTrue);
  });

  testWidgets('ending a session saves it to history with the final count and goal',
      (tester) async {
    await pumpScreen(tester);
    await tester.tap(find.byKey(const Key('sessionToggleButton')));
    await tester.pump();

    controller.emitShotCount(7);
    await tester.pump();
    await tester.tap(find.byKey(const Key('incrementButton')));
    await tester.pump();

    await tester.tap(find.byKey(const Key('sessionToggleButton')));
    await tester.pump();

    final saved = await const SessionHistoryStore().loadSessions();
    expect(saved, hasLength(1));
    expect(saved.single.shotCount, 8);
    expect(saved.single.goal, 10000);
  });

  testWidgets('disposing mid-session saves it to history, not just stopping the controller',
      (tester) async {
    await pumpScreen(tester);
    await tester.tap(find.byKey(const Key('sessionToggleButton')));
    await tester.pump();

    controller.emitShotCount(4);
    await tester.pump();

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));

    final saved = await const SessionHistoryStore().loadSessions();
    expect(saved, hasLength(1));
    expect(saved.single.shotCount, 4);
  });

  testWidgets(
      'a system back attempt while running asks Android to background the app '
      'instead of exiting', (tester) async {
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
    await tester.pump();

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

  testWidgets('no history button when onHistoryTap is not provided', (tester) async {
    await pumpScreen(tester);

    expect(find.byKey(const Key('historyButton')), findsNothing);
  });

  testWidgets('tapping the history button calls onHistoryTap', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: SessionScreen(controller: controller, onHistoryTap: () => tapped = true),
      ),
    );

    await tester.tap(find.byKey(const Key('historyButton')));
    await tester.pump();

    expect(tapped, isTrue);
  });
}
