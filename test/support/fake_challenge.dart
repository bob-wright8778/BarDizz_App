import 'package:hockey_shot_tracker/backend/challenge_client.dart';

/// Scriptable [ChallengeClient] fake: no network, ever. The outcome (or a
/// thrown error) is set up by the test; every call is recorded for assertions.
class FakeChallengeClient implements ChallengeClient {
  ChallengeOutcome result = ChallengeOutcome.existingUser;
  Object? error;

  int callCount = 0;
  String? lastTargetEmail;
  String? lastAccessToken;

  @override
  Future<ChallengeOutcome> challenge({required String accessToken, required String targetEmail}) async {
    callCount++;
    lastAccessToken = accessToken;
    lastTargetEmail = targetEmail;
    final e = error;
    if (e != null) throw e;
    return result;
  }
}
