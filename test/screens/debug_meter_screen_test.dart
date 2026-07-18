import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hockey_shot_tracker/audio/mic_level_controller.dart';
import 'package:hockey_shot_tracker/screens/debug_meter_screen.dart';

class FakeMicLevelController implements MicLevelController {
  final StreamController<double> _controller =
      StreamController<double>.broadcast();
  final StreamController<int> _shotCountController =
      StreamController<int>.broadcast();
  final StreamController<int> _barDownCountController =
      StreamController<int>.broadcast();
  bool started = false;
  bool stopped = false;

  @override
  Stream<double> get levels => _controller.stream;

  @override
  Stream<int> get shotCount => _shotCountController.stream;

  @override
  Stream<int> get barDownCount => _barDownCountController.stream;

  @override
  bool get isCapturing => started && !stopped;

  @override
  Future<void> start() async {
    started = true;
  }

  @override
  Future<void> stop() async {
    stopped = true;
  }

  void emit(double level) => _controller.add(level);

  void emitShotCount(int count) => _shotCountController.add(count);

  void emitBarDownCount(int count) => _barDownCountController.add(count);

  void dispose() {
    _controller.close();
    _shotCountController.close();
    _barDownCountController.close();
  }
}

void main() {
  late FakeMicLevelController controller;

  setUp(() {
    controller = FakeMicLevelController();
  });

  tearDown(() {
    controller.dispose();
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(home: DebugMeterScreen(controller: controller)),
    );
  }

  testWidgets('shows a 0% level and a Start button initially',
      (tester) async {
    await pumpScreen(tester);

    expect(find.text('Level: 0%'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Start'), findsOneWidget);
  });

  testWidgets('tapping Start calls controller.start and flips to Stop',
      (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.byKey(const Key('toggleButton')));
    await tester.pump();

    expect(controller.started, isTrue);
    expect(find.widgetWithText(ElevatedButton, 'Stop'), findsOneWidget);
  });

  testWidgets('meter updates live as the level stream emits',
      (tester) async {
    await pumpScreen(tester);
    await tester.tap(find.byKey(const Key('toggleButton')));
    await tester.pump();

    controller.emit(0.75);
    await tester.pump();

    expect(find.text('Level: 75%'), findsOneWidget);
    final meter =
        tester.widget<LinearProgressIndicator>(find.byKey(const Key('levelMeter')));
    expect(meter.value, 0.75);
  });

  testWidgets('shows a 0 shot count initially, and updates live as shots are detected',
      (tester) async {
    await pumpScreen(tester);

    expect(find.text('Shots: 0'), findsOneWidget);

    controller.emitShotCount(1);
    await tester.pump();

    expect(find.text('Shots: 1'), findsOneWidget);
  });

  testWidgets('tapping Stop after Start calls controller.stop',
      (tester) async {
    await pumpScreen(tester);
    await tester.tap(find.byKey(const Key('toggleButton')));
    await tester.pump();

    await tester.tap(find.byKey(const Key('toggleButton')));
    await tester.pump();

    expect(controller.stopped, isTrue);
    expect(find.widgetWithText(ElevatedButton, 'Start'), findsOneWidget);
  });

  testWidgets('no settings button when onSettingsTap is not provided',
      (tester) async {
    await pumpScreen(tester);

    expect(find.byKey(const Key('settingsButton')), findsNothing);
  });

  testWidgets('tapping the settings button calls onSettingsTap', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: DebugMeterScreen(
          controller: controller,
          onSettingsTap: () => tapped = true,
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('settingsButton')));
    await tester.pump();

    expect(tapped, isTrue);
  });
}
