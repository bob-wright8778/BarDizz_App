import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:hockey_shot_tracker/backend/pkce.dart';

void main() {
  group('generateCodeVerifier', () {
    test('produces a 43-128 char base64url string with no padding', () {
      final verifier = generateCodeVerifier();

      expect(verifier.length, inInclusiveRange(43, 128));
      expect(verifier, matches(RegExp(r'^[A-Za-z0-9_-]+$')));
    });

    test('is randomized across calls', () {
      final a = generateCodeVerifier(Random(1));
      final b = generateCodeVerifier(Random(2));

      expect(a, isNot(equals(b)));
    });
  });

  group('codeChallengeFor', () {
    test('matches the RFC 7636 Appendix B worked example', () {
      // Golden vector: independently recomputed via `openssl dgst -sha256`
      // + base64url on the same verifier, not derived from this code.
      const verifier = 'dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk';
      const expectedChallenge = 'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM';

      expect(codeChallengeFor(verifier), expectedChallenge);
    });

    test('is deterministic for the same verifier', () {
      final verifier = generateCodeVerifier();

      expect(codeChallengeFor(verifier), codeChallengeFor(verifier));
    });
  });
}
