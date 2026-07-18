import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hockey_shot_tracker/audio/calibration_controller.dart';
import 'package:hockey_shot_tracker/screens/calibration_screen.dart';

class FakeCalibrationController implements CalibrationController {
  FakeCalibrationController({this.targetSamples = 3});

  @override
  final int targetSamples;
  @override
  final double amplitudeThreshold = 0.35;

  final StreamController<int> _samplesController = StreamController<int>.broadcast();
  final StreamController<double> _levelsController = StreamController<double>.broadcast();
  int _recorded = 0;
  @override
  CalibrationStage stage = CalibrationStage.shot;
  bool started = false;
  bool finished = false;
  bool cancelled = false;
  Object? startError;
  Object? recordError;

  @override
  Stream<int> get samplesRecorded => _samplesController.stream;

  @override
  Stream<double> get levels => _levelsController.stream;

  void emitLevel(double level) => _levelsController.add(level);

  @override
  Future<void> start() async {
    started = true;
    if (startError != null) throw startError!;
  }

  @override
  Future<void> recordSample() async {
    if (recordError != null) throw recordError!;
    _recorded++;
    if (stage == CalibrationStage.shot && _recorded >= targetSamples) {
      stage = CalibrationStage.eww;
      _recorded = 0;
    }
    _samplesController.add(_recorded);
  }

  @override
  Future<void> finish() async {
    finished = true;
  }

  @override
  Future<void> cancel() async {
    cancelled = true;
  }

  void dispose() {
    _samplesController.close();
    _levelsController.close();
  }
}

void main() {
  late FakeCalibrationController controller;

  setUp(() {
    controller = FakeCalibrationController();
  });

  tearDown(() {
    controller.dispose();
  });

  Future<void> pumpScreen(WidgetTester tester, {VoidCallback? onComplete}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CalibrationScreen(controller: controller, onComplete: onComplete),
      ),
    );
    await tester.pump();
  }

  testWidgets('starts the controller and prompts for the first sample', (tester) async {
    await pumpScreen(tester);

    expect(controller.started, isTrue);
    expect(find.text('Take a shot to record sample 1 of 3.'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Record Shot'), findsOneWidget);
  });

  testWidgets('recording a sample advances the progress prompt', (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.byKey(const Key('recordSampleButton')));
    await tester.pumpAndSettle();

    expect(find.text('Take a shot to record sample 2 of 3.'), findsOneWidget);
  });

  testWidgets(
      'once shot samples are done, advances to the Eww step instead of finishing',
      (tester) async {
    await pumpScreen(tester);

    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byKey(const Key('recordSampleButton')));
      await tester.pumpAndSettle();
    }

    expect(controller.stage, CalibrationStage.eww);
    expect(find.text('Say "Eww!" to record sample 1 of 3.'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Record Eww'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Finish'), findsNothing);
  });

  testWidgets('once shot and Eww samples are both recorded, shows Finish',
      (tester) async {
    await pumpScreen(tester);

    for (var i = 0; i < 6; i++) {
      await tester.tap(find.byKey(const Key('recordSampleButton')));
      await tester.pumpAndSettle();
    }

    expect(find.text('All 3 sample shots and 3 Eww samples recorded.'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Finish'), findsOneWidget);
    expect(find.byKey(const Key('recordSampleButton')), findsNothing);
  });

  testWidgets('tapping Finish calls controller.finish and onComplete', (tester) async {
    var completed = false;
    await pumpScreen(tester, onComplete: () => completed = true);

    for (var i = 0; i < 6; i++) {
      await tester.tap(find.byKey(const Key('recordSampleButton')));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.byKey(const Key('finishCalibrationButton')));
    await tester.pumpAndSettle();

    expect(controller.finished, isTrue);
    expect(completed, isTrue);
  });

  testWidgets('shows an error message if starting the controller fails', (tester) async {
    controller.startError = StateError('Microphone permission denied.');
    await pumpScreen(tester);

    expect(find.byKey(const Key('calibrationErrorText')), findsOneWidget);
  });

  testWidgets('shows a live mic level while listening for a sample', (tester) async {
    await pumpScreen(tester);

    expect(find.text('Mic level: 0% (need 35%+)'), findsOneWidget);

    controller.emitLevel(0.6);
    await tester.pump();

    expect(find.text('Mic level: 60% (need 35%+)'), findsOneWidget);
    final meter = tester.widget<LinearProgressIndicator>(
      find.byKey(const Key('calibrationLevelMeter')),
    );
    expect(meter.value, closeTo(0.6, 1e-9));
  });

  testWidgets('shows an error message if recording a sample fails', (tester) async {
    await pumpScreen(tester);
    controller.recordError = StateError('boom');

    await tester.tap(find.byKey(const Key('recordSampleButton')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('calibrationErrorText')), findsOneWidget);
  });

  testWidgets('disposing without finishing cancels the controller to release the mic',
      (tester) async {
    await pumpScreen(tester);

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));

    expect(controller.cancelled, isTrue);
    expect(controller.finished, isFalse);
  });
}
