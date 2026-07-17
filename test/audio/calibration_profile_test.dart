import 'package:flutter_test/flutter_test.dart';
import 'package:hockey_shot_tracker/audio/calibration_profile.dart';

void main() {
  group('deriveReferenceProfile', () {
    test('a single sample returns that sample unchanged', () {
      final profile = deriveReferenceProfile([
        [0.1, 0.2, 0.3, 0.4],
      ]);
      expect(profile, [0.1, 0.2, 0.3, 0.4]);
    });

    test('averages multiple samples band-wise', () {
      final profile = deriveReferenceProfile([
        [0.0, 1.0],
        [1.0, 0.0],
        [0.5, 0.5],
      ]);
      expect(profile[0], closeTo(0.5, 1e-9));
      expect(profile[1], closeTo(0.5, 1e-9));
    });

    test('averaging normalized profiles stays normalized (sums to ~1.0)', () {
      final profile = deriveReferenceProfile([
        [0.05, 0.10, 0.20, 0.25, 0.25, 0.15],
        [0.10, 0.15, 0.15, 0.20, 0.20, 0.20],
      ]);
      final sum = profile.fold<double>(0.0, (a, b) => a + b);
      expect(sum, closeTo(1.0, 1e-9));
    });

    test('throws on an empty sample list', () {
      expect(() => deriveReferenceProfile([]), throwsArgumentError);
    });
  });
}
