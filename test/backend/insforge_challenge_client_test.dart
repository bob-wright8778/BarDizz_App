import 'package:flutter_test/flutter_test.dart';
import 'package:hockey_shot_tracker/backend/challenge_client.dart';
import 'package:hockey_shot_tracker/backend/insforge_challenge_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('parseChallengeStatus', () {
    test('reads the status field from the function body', () {
      expect(parseChallengeStatus('{"status":"invited"}'), 'invited');
    });

    test('maps a blank body to error', () {
      expect(parseChallengeStatus(''), 'error');
    });

    test('maps a body without a string status to error', () {
      expect(parseChallengeStatus('{"foo":1}'), 'error');
    });

    test('maps a malformed (non-JSON) body to error without throwing', () {
      expect(parseChallengeStatus('<html>502 Bad Gateway</html>'), 'error');
    });
  });

  group('InsforgeChallengeClient.challenge', () {
    test('posts the target email to the challenge-friend function and maps the outcome', () async {
      late String capturedBody;
      final client = InsforgeChallengeClient(
        httpClient: MockClient((request) async {
          capturedBody = request.body;
          expect(request.url.path, endsWith('/functions/challenge-friend'));
          expect(request.headers['Authorization'], 'Bearer token-1');
          return http.Response('{"status":"existing_user"}', 200);
        }),
      );

      final outcome = await client.challenge(accessToken: 'token-1', targetEmail: 'a@b.com');

      expect(outcome, ChallengeOutcome.existingUser);
      expect(capturedBody, contains('a@b.com'));
    });

    test('maps each known status string to its outcome', () async {
      Future<ChallengeOutcome> outcomeFor(String status) {
        final client = InsforgeChallengeClient(
          httpClient: MockClient((_) async => http.Response('{"status":"$status"}', 200)),
        );
        return client.challenge(accessToken: 't', targetEmail: 'a@b.com');
      }

      expect(await outcomeFor('existing_user'), ChallengeOutcome.existingUser);
      expect(await outcomeFor('invited'), ChallengeOutcome.invited);
      expect(await outcomeFor('self'), ChallengeOutcome.selfChallenge);
      expect(await outcomeFor('invalid_email'), ChallengeOutcome.invalidEmail);
      expect(await outcomeFor('anything_else'), ChallengeOutcome.error);
    });

    test('throws ChallengeException on a non-2xx response', () async {
      final client = InsforgeChallengeClient(
        httpClient: MockClient((_) async => http.Response('nope', 500)),
      );

      expect(
        () => client.challenge(accessToken: 't', targetEmail: 'a@b.com'),
        throwsA(isA<ChallengeException>()),
      );
    });

    test('throws ChallengeException when the request cannot be sent', () async {
      final client = InsforgeChallengeClient(
        httpClient: MockClient((_) async => throw http.ClientException('offline')),
      );

      expect(
        () => client.challenge(accessToken: 't', targetEmail: 'a@b.com'),
        throwsA(isA<ChallengeException>()),
      );
    });
  });
}
