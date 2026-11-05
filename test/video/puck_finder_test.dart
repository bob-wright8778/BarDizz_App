import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hockey_shot_tracker/video/luma_frame.dart';
import 'package:hockey_shot_tracker/video/norm_rect.dart';
import 'package:hockey_shot_tracker/video/puck_finder.dart';

import 'synthetic_frames.dart';

void main() {
  group('downsampleLuma', () {
    test('averages square blocks and skips stride padding', () {
      // 4x2 image with a 6-byte stride (2 padding bytes per row, set to 255).
      final plane = Uint8List.fromList([
        10, 20, 100, 100, 255, 255, //
        30, 40, 100, 100, 255, 255,
      ]);
      final frame = downsampleLuma(plane, width: 4, height: 2, bytesPerRow: 6, targetWidth: 2);
      expect(frame.width, 2);
      expect(frame.height, 1);
      expect(frame.pixels, [25, 100]);
    });

    test('keeps the source aspect ratio', () {
      final plane = Uint8List(640 * 480);
      final frame = downsampleLuma(plane, width: 640, height: 480, bytesPerRow: 640);
      expect(frame.width, lessThanOrEqualTo(analysisGridWidth));
      expect(frame.width / frame.height, closeTo(640 / 480, 0.05));
    });
  });

  group('medianLuma', () {
    test('reads the pad brightness, not the puck sitting on it', () {
      final frame = syntheticFrame(discs: [(0.5, 0.75, 0.03)]);
      expect(medianLuma(frame, testCalibration.shootingZone), 200);
    });
  });

  group('findPuckBlobs', () {
    final zone = testCalibration.shootingZone;
    late double area;

    setUp(() {
      area = expectedPuckArea(syntheticFrame(), testCalibration.effectivePuckDiameter);
    });

    test('finds a dark disc and reports its centre', () {
      final frame = syntheticFrame(discs: [(0.5, 0.75, 0.03)]);
      final blobs = findPuckBlobs(frame, zone, referenceLuma: 200, expectedArea: area);
      expect(blobs, hasLength(1));
      expect(blobs.single.x, closeTo(0.5, 0.01));
      expect(blobs.single.y, closeTo(0.75, 0.02));
    });

    test('rejects a long thin stick shaft', () {
      final frame = syntheticFrame(darkRects: [const NormRect(0.36, 0.7, 0.64, 0.72)]);
      expect(findPuckBlobs(frame, zone, referenceLuma: 200, expectedArea: area), isEmpty);
    });

    test('rejects a blob far bigger than a puck, like a skate or pant leg', () {
      final frame = syntheticFrame(discs: [(0.5, 0.75, 0.12)]);
      expect(findPuckBlobs(frame, zone, referenceLuma: 200, expectedArea: area), isEmpty);
    });

    test('ignores a grey mark that is not dark relative to the pad', () {
      final frame = syntheticFrame(discs: [(0.5, 0.75, 0.03)], dark: 150);
      expect(findPuckBlobs(frame, zone, referenceLuma: 200, expectedArea: area), isEmpty);
    });

    test('only looks inside the region', () {
      final frame = syntheticFrame(discs: [(0.1, 0.2, 0.03)]);
      expect(findPuckBlobs(frame, zone, referenceLuma: 200, expectedArea: area), isEmpty);
    });
  });

  group('measurePuckDiameter', () {
    test('measures a resting puck even when the guess is well off', () {
      final frame = syntheticFrame(discs: [(0.5, 0.75, 0.04)]);
      final d = measurePuckDiameter(frame, testCalibration.shootingZone, guessDiameter: 0.02);
      expect(d, closeTo(0.04, 0.005));
    });

    test('is null with no puck in the zone', () {
      expect(
        measurePuckDiameter(syntheticFrame(), testCalibration.shootingZone, guessDiameter: 0.02),
        isNull,
      );
    });
  });
}
