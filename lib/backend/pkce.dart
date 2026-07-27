import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// Outputs: a random 43-character base64url PKCE code verifier (RFC 7636),
/// within its required 43-128 char range.
String generateCodeVerifier([Random? random]) {
  final rand = random ?? Random.secure();
  final bytes = List<int>.generate(32, (_) => rand.nextInt(256));
  return base64Url.encode(bytes).replaceAll('=', '');
}

/// Inputs: a PKCE code verifier.
/// Outputs: its S256 code_challenge -- base64url(SHA256(verifier)), unpadded.
String codeChallengeFor(String verifier) {
  final digest = sha256.convert(ascii.encode(verifier));
  return base64Url.encode(digest.bytes).replaceAll('=', '');
}
