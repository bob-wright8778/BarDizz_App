import 'dart:convert';

import 'package:http/http.dart' as http;

import 'challenge_client.dart';
import 'insforge_config.dart';

/// [ChallengeClient] backed by the InsForge `challenge-friend` edge function,
/// which does the existing-vs-non-user branching and the Resend send
/// server-side; the app only ever sees the returned status code.
class InsforgeChallengeClient implements ChallengeClient {
  InsforgeChallengeClient({http.Client? httpClient, this.baseUrl = insforgeBaseUrl})
      : _client = httpClient ?? http.Client();

  final http.Client _client;
  final String baseUrl;

  @override
  Future<ChallengeOutcome> challenge({required String accessToken, required String targetEmail}) async {
    final uri = Uri.parse('$baseUrl/functions/challenge-friend');
    final http.Response response;
    try {
      response = await _client.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $accessToken',
        },
        body: jsonEncode({'target_email': targetEmail}),
      );
    } catch (e) {
      throw ChallengeException('Could not reach the challenge service: $e');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ChallengeException('Challenge send failed (HTTP ${response.statusCode})');
    }
    return ChallengeOutcome.fromStatus(parseChallengeStatus(response.body));
  }
}

/// Inputs: the raw response body from the `challenge-friend` function.
/// Outputs: the `status` field, or `'error'` when the body is blank, malformed,
/// or lacks one (never throws -- an unreadable body maps to `'error'`).
String parseChallengeStatus(String body) {
  if (body.isEmpty) return 'error';
  try {
    final decoded = jsonDecode(body);
    if (decoded is Map && decoded['status'] is String) return decoded['status'] as String;
  } on FormatException {
    return 'error';
  }
  return 'error';
}
