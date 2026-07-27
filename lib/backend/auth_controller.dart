import 'package:flutter/foundation.dart';

import 'auth_client.dart';
import 'auth_models.dart';
import 'insforge_config.dart';
import 'oauth_browser.dart';
import 'pkce.dart';
import 'secure_token_store.dart';

enum AuthStatus {
  /// Checking for a stored refresh token at app launch.
  restoring,
  signedOut,

  /// Mid OAuth round-trip (browser open / exchanging the code).
  authenticating,

  /// Signed in but the profile is missing a name and/or avatar.
  needsProfileSetup,
  signedIn,
}

/// Owns the OAuth sign-in round-trip, session persistence/restore, and
/// profile state; the Session shot-tracking path never touches this.
class AuthController extends ChangeNotifier {
  AuthController({
    required this.client,
    required this.browser,
    required this.tokenStore,
    this.redirectUri = oauthRedirectUri,
    this.callbackUrlScheme = oauthCallbackUrlScheme,
  });

  final AuthClient client;
  final OAuthBrowser browser;
  final SecureTokenStore tokenStore;
  final String redirectUri;
  final String callbackUrlScheme;

  AuthStatus status = AuthStatus.restoring;
  AuthUser? user;
  AuthProfile? profile;
  String? errorMessage;
  String? _accessToken;

  /// Outputs: the current session's access token, for callers (e.g. the
  /// Friends tab) that need to authenticate their own API calls.
  String? get accessToken => _accessToken;

  /// Restores a session from a stored refresh token, if any; call once at
  /// app launch. Leaves status at [AuthStatus.signedOut] with no error on a
  /// clean first launch or an expired/invalid refresh token.
  Future<void> restore() async {
    final refreshToken = await tokenStore.readRefreshToken();
    if (refreshToken == null) {
      status = AuthStatus.signedOut;
      notifyListeners();
      return;
    }
    try {
      final session = await client.refresh(refreshToken: refreshToken);
      await _completeSession(session);
    } catch (_) {
      await tokenStore.clear();
      status = AuthStatus.signedOut;
      notifyListeners();
    }
  }

  Future<void> signInWithGoogle() => _signIn('google');

  Future<void> _signIn(String provider) async {
    status = AuthStatus.authenticating;
    errorMessage = null;
    notifyListeners();
    try {
      final verifier = generateCodeVerifier();
      final challenge = codeChallengeFor(verifier);
      final authUrl = await client.requestAuthUrl(
        provider: provider,
        redirectUri: redirectUri,
        codeChallenge: challenge,
      );
      final callback = await browser.authenticate(url: authUrl, callbackUrlScheme: callbackUrlScheme);
      final code = Uri.parse(callback).queryParameters['insforge_code'];
      if (code == null) {
        throw const AuthException('OAuth callback did not include insforge_code');
      }
      final session = await client.exchangeCode(code: code, codeVerifier: verifier);
      await _completeSession(session);
    } catch (e) {
      status = AuthStatus.signedOut;
      errorMessage = 'Sign-in failed. Please try again.';
      notifyListeners();
    }
  }

  Future<void> _completeSession(AuthSession session) async {
    await tokenStore.saveTokens(accessToken: session.accessToken, refreshToken: session.refreshToken);
    _accessToken = session.accessToken;
    user = session.user;
    final fetchedProfile = await client.fetchProfile(userId: session.user.id);
    profile = fetchedProfile;
    status = fetchedProfile.isComplete ? AuthStatus.signedIn : AuthStatus.needsProfileSetup;
    notifyListeners();
  }

  /// Inputs: a validated, trimmed display name and one chosen avatar id.
  /// Persists the profile and flips to [AuthStatus.signedIn] once complete.
  Future<void> saveProfile({required String displayName, required String avatarId}) async {
    final token = _accessToken;
    if (token == null) throw const AuthException('Not signed in');
    final updated = await client.updateProfile(
      accessToken: token,
      displayName: displayName,
      avatarId: avatarId,
    );
    profile = updated;
    status = updated.isComplete ? AuthStatus.signedIn : AuthStatus.needsProfileSetup;
    notifyListeners();
  }

  /// Clears stored tokens and local state immediately; the best-effort
  /// server-side logout call never blocks this.
  Future<void> signOut() async {
    final token = _accessToken;
    await tokenStore.clear();
    _accessToken = null;
    user = null;
    profile = null;
    errorMessage = null;
    status = AuthStatus.signedOut;
    notifyListeners();
    if (token != null) {
      try {
        await client.signOut(accessToken: token);
      } catch (_) {
        // Local sign-out already happened; server-side logout is best-effort.
      }
    }
  }
}
