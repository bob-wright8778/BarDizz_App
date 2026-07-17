import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hockey_shot_tracker/screens/settings_screen.dart';

void main() {
  testWidgets('tapping Redo calibration calls onRecalibrate', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsScreen(onRecalibrate: () => tapped = true),
      ),
    );

    await tester.tap(find.byKey(const Key('recalibrateTile')));
    await tester.pump();

    expect(tapped, isTrue);
  });

  testWidgets('no debug meter entry when onDebugMeterTap is not provided', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: SettingsScreen(onRecalibrate: () {})),
    );

    expect(find.byKey(const Key('debugMeterTile')), findsNothing);
  });

  testWidgets('tapping Debug meter calls onDebugMeterTap', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsScreen(onRecalibrate: () {}, onDebugMeterTap: () => tapped = true),
      ),
    );

    await tester.tap(find.byKey(const Key('debugMeterTile')));
    await tester.pump();

    expect(tapped, isTrue);
  });
}
