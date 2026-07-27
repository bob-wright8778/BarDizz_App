import 'auth_models.dart';

/// The InsForge auth/profile REST surface this app depends on, abstracted so
/// the UI/state layer never imports `http` directly and tests can fake it.
abstract class AuthClient {
  /// Inputs: OAuth provider id (e.g. "google"), the app's redirect URI,
  /// and the PKCE code_challenge.
  /// Outputs: the provider's hosted authorization URL to open in a browser.
  Future<String> requestAuthUrl({
    required String provider,
    required String redirectUri,
    required String codeChallenge,
  });

  /// Inputs: the `insforge_code` captured from the OAuth redirect and the
  /// PKCE verifier that produced its challenge.
  /// Outputs: the new session (user + token pair).
  Future<AuthSession> exchangeCode({required String code, required String codeVerifier});

  /// Inputs: a previously stored refresh token.
  /// Outputs: a new session with a rotated refresh token.
  Future<AuthSession> refresh({required String refreshToken});

  /// Inputs: a user id.
  /// Outputs: that user's public profile (name/avatar only, never email).
  Future<AuthProfile> fetchProfile({required String userId});

  /// Inputs: the caller's access token and the new display name/avatar id.
  /// Outputs: the profile as persisted by the backend.
  Future<AuthProfile> updateProfile({
    required String accessToken,
    required String displayName,
    required String avatarId,
  });

  /// Inputs: the caller's access token.
  /// Best-effort server-side session invalidation; local token clearing does
  /// not depend on this succeeding.
  Future<void> signOut({required String accessToken});
}
