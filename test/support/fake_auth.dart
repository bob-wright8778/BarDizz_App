import 'package:hockey_shot_tracker/backend/auth_client.dart';
import 'package:hockey_shot_tracker/backend/auth_models.dart';
import 'package:hockey_shot_tracker/backend/oauth_browser.dart';
import 'package:hockey_shot_tracker/backend/secure_token_store.dart';

/// Scriptable [AuthClient] fake: no network, ever. Every response/error is
/// set up by the test before use; every request is recorded for assertions.
class FakeAuthClient implements AuthClient {
  FakeAuthClient({this.authUrl = 'https://example.com/oauth'});

  final String authUrl;
  AuthSession? exchangeResult;
  Object? exchangeError;
  AuthSession? refreshResult;
  Object? refreshError;
  AuthProfile profile = const AuthProfile();

  String? lastRequestedProvider;
  String? lastCodeChallenge;
  String? lastExchangeCode;
  String? lastExchangeVerifier;
  String? lastRefreshToken;
  String? lastUpdateAccessToken;
  String? lastUpdatedName;
  String? lastUpdatedAvatarId;
  String? lastSignOutToken;
  int signOutCallCount = 0;
  Object? signOutError;

  @override
  Future<String> requestAuthUrl({
    required String provider,
    required String redirectUri,
    required String codeChallenge,
  }) async {
    lastRequestedProvider = provider;
    lastCodeChallenge = codeChallenge;
    return authUrl;
  }

  @override
  Future<AuthSession> exchangeCode({required String code, required String codeVerifier}) async {
    lastExchangeCode = code;
    lastExchangeVerifier = codeVerifier;
    final error = exchangeError;
    if (error != null) throw error;
    return exchangeResult!;
  }

  @override
  Future<AuthSession> refresh({required String refreshToken}) async {
    lastRefreshToken = refreshToken;
    final error = refreshError;
    if (error != null) throw error;
    return refreshResult!;
  }

  @override
  Future<AuthProfile> fetchProfile({required String userId}) async => profile;

  @override
  Future<AuthProfile> updateProfile({
    required String accessToken,
    required String displayName,
    required String avatarId,
  }) async {
    lastUpdateAccessToken = accessToken;
    lastUpdatedName = displayName;
    lastUpdatedAvatarId = avatarId;
    profile = AuthProfile(name: displayName, avatarId: avatarId);
    return profile;
  }

  @override
  Future<void> signOut({required String accessToken}) async {
    lastSignOutToken = accessToken;
    signOutCallCount++;
    final error = signOutError;
    if (error != null) throw error;
  }
}

/// Scriptable [OAuthBrowser] fake: returns a canned callback URL instead of
/// ever launching a real browser.
class FakeOAuthBrowser implements OAuthBrowser {
  FakeOAuthBrowser({this.callbackUrl});

  String? callbackUrl;
  Object? error;
  String? lastUrl;
  String? lastCallbackUrlScheme;

  @override
  Future<String> authenticate({required String url, required String callbackUrlScheme}) async {
    lastUrl = url;
    lastCallbackUrlScheme = callbackUrlScheme;
    final err = error;
    if (err != null) throw err;
    return callbackUrl!;
  }
}

/// In-memory [SecureTokenStore] fake.
class FakeSecureTokenStore implements SecureTokenStore {
  FakeSecureTokenStore({this.initialAccessToken, this.initialRefreshToken})
      : accessToken = initialAccessToken,
        refreshToken = initialRefreshToken;

  final String? initialAccessToken;
  final String? initialRefreshToken;
  String? accessToken;
  String? refreshToken;
  int clearCallCount = 0;

  @override
  Future<void> saveTokens({required String accessToken, required String refreshToken}) async {
    this.accessToken = accessToken;
    this.refreshToken = refreshToken;
  }

  @override
  Future<String?> readAccessToken() async => accessToken;

  @override
  Future<String?> readRefreshToken() async => refreshToken;

  @override
  Future<void> clear() async {
    accessToken = null;
    refreshToken = null;
    clearCallCount++;
  }
}
