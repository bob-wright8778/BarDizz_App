import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hockey_shot_tracker/screens/video_calibration_screen.dart';

import '../support/fake_video_feed.dart';
import '../video/synthetic_frames.dart';

void main() {
  setUp(() {
    final view = TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.physicalSize = const Size(800, 2000);
    view.devicePixelRatio = 1.0;
    addTearDown(view.resetPhysicalSize);
    addTearDown(view.resetDevicePixelRatio);
  });

  Future<void> pump(WidgetTester tester, FakeVideoShotFeed feed) async {
    await tester.pumpWidget(MaterialApp(home: VideoCalibrationScreen(feed: feed)));
    // decodeImageFromPixels completes outside the fake clock.
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
  }

  double canvasAspect(WidgetTester tester) {
    final size = tester.getSize(find.byKey(const Key('calibrationCanvas')));
    return size.width / size.height;
  }

  /// Drags a box on the canvas between two normalized corners.
  Future<void> drawBox(WidgetTester tester, Offset from, Offset to) async {
    final canvas = find.byKey(const Key('calibrationCanvas'));
    final topLeft = tester.getTopLeft(canvas);
    final size = tester.getSize(canvas);
    Offset at(Offset n) => topLeft + Offset(n.dx * size.width, n.dy * size.height);
    final gesture = await tester.startGesture(at(from));
    await gesture.moveTo(at(Offset.lerp(from, to, 0.5)!));
    await gesture.moveTo(at(to));
    await gesture.up();
    await tester.pump();
  }

  Future<void> markZoneAndNet(WidgetTester tester) async {
    await drawBox(tester, const Offset(0.35, 0.6), const Offset(0.65, 0.95));
    await tester.tap(find.text('Net'));
    await tester.pump();
    await drawBox(tester, const Offset(0.4, 0.1), const Offset(0.6, 0.3));
  }

  testWidgets('says so when the camera is not running', (tester) async {
    await pump(tester, FakeVideoShotFeed());
    expect(find.byKey(const Key('calibrationNoCameraText')), findsOneWidget);
  });

  testWidgets('shows the still turned upright by the suggested rotation', (tester) async {
    // A landscape sensor frame, phone held upright: one clockwise turn.
    await pump(tester, FakeVideoShotFeed(still: syntheticFrame(), suggestedQuarterTurns: 1));
    expect(canvasAspect(tester), closeTo(frameH / frameW, 0.01));
  });

  testWidgets('Rotate turns the still a quarter turn', (tester) async {
    await pump(tester, FakeVideoShotFeed(still: syntheticFrame()));
    expect(canvasAspect(tester), closeTo(frameW / frameH, 0.01));

    await tester.tap(find.byKey(const Key('calibrationRotateButton')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();

    expect(canvasAspect(tester), closeTo(frameH / frameW, 0.01));
  });

  testWidgets('estimates the distance from the net and puck sizes and saves it', (tester) async {
    final feed = FakeVideoShotFeed(still: syntheticFrame(discs: [(0.5, 0.8, 0.03)]));
    await pump(tester, feed);

    await markZoneAndNet(tester);

    expect(find.text('Puck found.'), findsOneWidget);
    // A 3 in puck 0.03 of the frame wide and a 4 ft net 0.2 of the frame
    // tall put them ~6 ft and ~26 ft from a 69-degree lens: ~20 ft apart.
    final estimate = tester.widget<Text>(find.byKey(const Key('calibrationEstimateText'))).data!;
    expect(estimate, matches(RegExp(r'About (19|20|21) ft')));

    await tester.tap(find.byKey(const Key('calibrationSaveButton')));
    await tester.pumpAndSettle();

    final saved = feed.calibration!;
    expect(saved.distanceIsManual, isFalse);
    expect(saved.shotDistanceFeet, inInclusiveRange(18.5, 21.5));
    expect(saved.puckWidth, closeTo(0.03, 0.006));
    expect(saved.quarterTurns, 0);
  });

  testWidgets('a manually set distance is saved as manual', (tester) async {
    final feed = FakeVideoShotFeed(still: syntheticFrame(discs: [(0.5, 0.8, 0.03)]));
    await pump(tester, feed);
    await markZoneAndNet(tester);

    expect(find.byKey(const Key('calibrationDistanceSlider')), findsNothing);
    await tester.tap(find.byKey(const Key('calibrationManualDistanceSwitch')));
    await tester.pump();
    expect(find.byKey(const Key('calibrationDistanceSlider')), findsOneWidget);

    await tester.tap(find.byKey(const Key('calibrationSaveButton')));
    await tester.pumpAndSettle();

    expect(feed.calibration!.distanceIsManual, isTrue);
  });

  testWidgets('without a puck to measure, the typed-in distance is used', (tester) async {
    final feed = FakeVideoShotFeed(still: syntheticFrame());
    await pump(tester, feed);
    await markZoneAndNet(tester);

    expect(find.textContaining('No puck found'), findsOneWidget);
    await tester.tap(find.byKey(const Key('calibrationSaveButton')));
    await tester.pumpAndSettle();

    expect(feed.calibration!.distanceIsManual, isTrue);
    expect(feed.calibration!.shotDistanceFeet, 15);
  });
}
