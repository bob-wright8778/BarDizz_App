/// The outcome of a "challenge a friend" send, mapped from the status code the
/// server-side edge function returns.
enum ChallengeOutcome {
  /// The email belongs to an existing BarDizz user: a pending friend request
  /// was created (or an existing one re-notified) and an "open the app" email
  /// sent.
  existingUser,

  /// The email isn't a user yet: an "install to beat it" invite was sent and a
  /// deferred request stored to resolve when they sign up.
  invited,

  /// The target email is the caller's own.
  selfChallenge,
  invalidEmail,

  /// Any server-side or transport failure.
  error;

  /// Inputs: the raw `status` string from the edge function's JSON body.
  /// Outputs: the matching outcome, defaulting to [error] for anything
  /// unrecognized.
  static ChallengeOutcome fromStatus(String status) {
    switch (status) {
      case 'existing_user':
        return ChallengeOutcome.existingUser;
      case 'invited':
        return ChallengeOutcome.invited;
      case 'self':
        return ChallengeOutcome.selfChallenge;
      case 'invalid_email':
        return ChallengeOutcome.invalidEmail;
      default:
        return ChallengeOutcome.error;
    }
  }
}

/// Sends a challenge-a-friend email through the server-side edge function,
/// abstracted so the UI never imports `http` directly and tests can fake it.
abstract class ChallengeClient {
  /// Inputs: the caller's access token and the target email.
  /// Outputs: the send outcome; throws [ChallengeException] on transport
  /// failure (as opposed to a business outcome like
  /// [ChallengeOutcome.selfChallenge]).
  Future<ChallengeOutcome> challenge({required String accessToken, required String targetEmail});
}

/// Any failure reaching or reading the challenge edge function.
class ChallengeException implements Exception {
  const ChallengeException(this.message);

  final String message;

  @override
  String toString() => 'ChallengeException: $message';
}
