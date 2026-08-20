import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hockey_shot_tracker/audio/collection_label.dart';
import 'package:hockey_shot_tracker/audio/data_collection_controller.dart';
import 'package:hockey_shot_tracker/screens/data_collection_screen.dart';

class FakeDataCollectionController implements DataCollectionController {
  final StreamController<CollectionTally> _tallyController =
      StreamController<CollectionTally>.broadcast();
  final List<CollectionLabel> tagged = [];
  bool started = false;
  bool stopped = false;
  bool undoCalled = false;
  bool throwOnStart = false;
  CollectionTally _tally = CollectionTally.empty;

  @override
  bool get isCapturing => started && !stopped;

  @override
  Stream<CollectionTally> get tally => _tallyController.stream;

  @override
  CollectionTally get currentTally => _tally;

  void emitTally(CollectionTally next) {
    _tally = next;
    _tallyController.add(next);
  }

  @override
  Future<void> start() async {
    if (throwOnStart) throw StateError('Microphone permission not granted.');
    started = true;
  }

  @override
  Future<void> stop() async {
    stopped = true;
  }

  @override
  Future<void> tag(CollectionLabel label) async {
    tagged.add(label);
  }

  @override
  Future<void> undoLast() async {
    undoCalled = true;
  }

  void dispose() => _tallyController.close();
}

void main() {
  late FakeDataCollectionController controller;

  setUp(() {
    controller = FakeDataCollectionController();
  });

  tearDown(() {
    controller.dispose();
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(home: DataCollectionScreen(controller: controller)));
  }

  testWidgets('shows a Start button and zero tallies initially', (tester) async {
    await pumpScreen(tester);

    expect(find.widgetWithText(ElevatedButton, 'Start'), findsOneWidget);
    expect(find.text('0'), findsNWidgets(3));
  });

  testWidgets('label buttons are disabled until capture starts', (tester) async {
    await pumpScreen(tester);

    final button = tester.widget<ElevatedButton>(find.byKey(const Key('shotTagButton')));
    expect(button.onPressed, isNull);
  });

  testWidgets('tapping Start begins capture and enables label buttons', (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.byKey(const Key('captureToggleButton')));
    await tester.pump();

    expect(controller.started, isTrue);
    expect(find.widgetWithText(ElevatedButton, 'Stop'), findsOneWidget);
    final button = tester.widget<ElevatedButton>(find.byKey(const Key('shotTagButton')));
    expect(button.onPressed, isNotNull);
  });

  testWidgets('a failed Start shows an error and does not flip to Stop', (tester) async {
    controller.throwOnStart = true;
    await pumpScreen(tester);

    await tester.tap(find.byKey(const Key('captureToggleButton')));
    await tester.pump();

    expect(find.byKey(const Key('errorText')), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Start'), findsOneWidget);
  });

  testWidgets('tapping a label button while capturing calls tag on the controller',
      (tester) async {
    await pumpScreen(tester);
    await tester.tap(find.byKey(const Key('captureToggleButton')));
    await tester.pump();

    await tester.tap(find.byKey(const Key('bar-hitTagButton')));
    await tester.pump();

    expect(controller.tagged, [CollectionLabel.barHit]);
  });

  testWidgets('tally updates live as the controller stream emits', (tester) async {
    await pumpScreen(tester);

    controller.emitTally(const CollectionTally(counts: {CollectionLabel.eww: 3}, canUndo: true));
    await tester.pump();

    expect(find.byKey(const Key('ewwCountText')), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('Undo last is disabled until a clip has been recorded', (tester) async {
    await pumpScreen(tester);

    final undoButton = tester.widget<OutlinedButton>(find.byKey(const Key('undoLastButton')));
    expect(undoButton.onPressed, isNull);

    controller.emitTally(const CollectionTally(counts: {CollectionLabel.shot: 1}, canUndo: true));
    await tester.pump();

    final enabledButton = tester.widget<OutlinedButton>(find.byKey(const Key('undoLastButton')));
    expect(enabledButton.onPressed, isNotNull);
  });

  testWidgets('tapping Undo last calls undoLast on the controller', (tester) async {
    controller.emitTally(const CollectionTally(counts: {CollectionLabel.shot: 1}, canUndo: true));
    await pumpScreen(tester);

    await tester.tap(find.byKey(const Key('undoLastButton')));
    await tester.pump();

    expect(controller.undoCalled, isTrue);
  });
}
