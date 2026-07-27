import 'package:flutter_test/flutter_test.dart';
import 'package:hockey_shot_tracker/backend/profile_validation.dart';

void main() {
  group('validateDisplayName', () {
    test('rejects an empty string', () {
      expect(validateDisplayName(''), isNotNull);
    });

    test('rejects whitespace-only input', () {
      expect(validateDisplayName('   '), isNotNull);
    });

    test('rejects more than 20 trimmed characters', () {
      expect(validateDisplayName('a' * 21), isNotNull);
    });

    test('accepts exactly 20 trimmed characters', () {
      expect(validateDisplayName('a' * 20), isNull);
    });

    test('accepts a normal 1-char name', () {
      expect(validateDisplayName('A'), isNull);
    });

    test('trims before checking length so surrounding whitespace does not count', () {
      expect(validateDisplayName('  ${'a' * 20}  '), isNull);
    });
  });

  group('normalizeDisplayName', () {
    test('trims leading and trailing whitespace', () {
      expect(normalizeDisplayName('  Bob  '), 'Bob');
    });
  });
}
