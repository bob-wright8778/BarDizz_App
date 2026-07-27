import 'package:flutter_test/flutter_test.dart';
import 'package:hockey_shot_tracker/backend/auth_controller.dart';
import 'package:hockey_shot_tracker/backend/auth_models.dart';

import '../support/fake_auth.dart';

const _user = AuthUser(id: 'user-1', email: 'user@example.com');
const _session = AuthSession(user: _user, accessToken: 'access-1', refreshToken: 'refresh-1');
const _rotatedSession =
    AuthSession(user: _user, accessToken: 'access-2', refreshToken: 'refresh-2');

AuthController _buildController({
  required FakeAuthClient client,
  required FakeOAuthBrowser browser,
  required FakeSecureTokenStore tokenStore,
}) {
  return AuthController(client: client, browser: browser, tokenStore: tokenStore);
}

void main() {
  group('restore', () {
    test('with no stored refresh token goes straight to signedOut', () async {
      final controller = _buildController(
        client: FakeAuthClient(),
        browser: FakeOAuthBrowser(),
        tokenStore: FakeSecureTokenStore(),
      );

      await controller.restore();

      expect(controller.status, AuthStatus.signedOut);
    });

    test('with a stored refresh token restores the session and persists the rotated refresh token',
        () async {
      final client = FakeAuthClient()..refreshResult = _rotatedSession;
      final tokenStore = FakeSecureTokenStore(initialRefreshToken: 'stale-refresh');
      final controller =
          _buildController(client: client, browser: FakeOAuthBrowser(), tokenStore: tokenStore);
      client.profile = const AuthProfile(name: 'Bob', avatarId: 'avatar-01');

      await controller.restore();

      expect(controller.status, AuthStatus.signedIn);
      expect(client.lastRefreshToken, 'stale-refresh');
      expect(tokenStore.accessToken, 'access-2');
      expect(tokenStore.refreshToken, 'refresh-2', reason: 'refresh rotates the token');
    });

    test('restores to needsProfileSetup when the profile has no name/avatar yet', () async {
      final client = FakeAuthClient()..refreshResult = _rotatedSession;
      final controller = _buildController(
        client: client,
        browser: FakeOAuthBrowser(),
        tokenStore: FakeSecureTokenStore(initialRefreshToken: 'stale-refresh'),
      );

      await controller.restore();

      expect(controller.status, AuthStatus.needsProfileSetup);
    });

    test('a failed refresh (e.g. expired token) clears storage and goes to signedOut', () async {
      final client = FakeAuthClient()..refreshError = Exception('401');
      final tokenStore = FakeSecureTokenStore(
        initialAccessToken: 'stale-access',
        initialRefreshToken: 'stale-refresh',
      );
      final controller =
          _buildController(client: client, browser: FakeOAuthBrowser(), tokenStore: tokenStore);

      await controller.restore();

      expect(controller.status, AuthStatus.signedOut);
      expect(tokenStore.accessToken, isNull);
      expect(tokenStore.refreshToken, isNull);
      expect(tokenStore.clearCallCount, 1);
    });
  });

  group('sign-in flow states', () {
    test('goes through authenticating before landing on needsProfileSetup for a first-time user',
        () async {
      final client = FakeAuthClient()..exchangeResult = _session;
      final browser = FakeOAuthBrowser(callbackUrl: 'bardizz://auth/callback?insforge_code=abc123');
      final controller =
          _buildController(client: client, browser: browser, tokenStore: FakeSecureTokenStore());

      final future = controller.signInWithGoogle();
      expect(controller.status, AuthStatus.authenticating);

      await future;

      expect(controller.status, AuthStatus.needsProfileSetup);
      expect(client.lastRequestedProvider, 'google');
      expect(client.lastExchangeCode, 'abc123');
      expect(browser.lastCallbackUrlScheme, 'bardizz');
    });

    test('lands on signedIn directly when the profile is already complete', () async {
      final client = FakeAuthClient()..exchangeResult = _session;
      client.profile = const AuthProfile(name: 'Bob', avatarId: 'avatar-01');
      final browser = FakeOAuthBrowser(callbackUrl: 'bardizz://auth/callback?insforge_code=abc123');
      final controller =
          _buildController(client: client, browser: browser, tokenStore: FakeSecureTokenStore());

      await controller.signInWithGoogle();

      expect(controller.status, AuthStatus.signedIn);
    });

    test('persists both tokens from the exchange', () async {
      final client = FakeAuthClient()..exchangeResult = _session;
      final browser = FakeOAuthBrowser(callbackUrl: 'bardizz://auth/callback?insforge_code=abc123');
      final tokenStore = FakeSecureTokenStore();
      final controller =
          _buildController(client: client, browser: browser, tokenStore: tokenStore);

      await controller.signInWithGoogle();

      expect(tokenStore.accessToken, 'access-1');
      expect(tokenStore.refreshToken, 'refresh-1');
    });

    test('a browser cancellation/error surfaces an error message and returns to signedOut',
        () async {
      final client = FakeAuthClient();
      final browser = FakeOAuthBrowser()..error = Exception('user cancelled');
      final controller =
          _buildController(client: client, browser: browser, tokenStore: FakeSecureTokenStore());

      await controller.signInWithGoogle();

      expect(controller.status, AuthStatus.signedOut);
      expect(controller.errorMessage, isNotNull);
    });

    test('a callback missing insforge_code surfaces an error instead of exchanging', () async {
      final client = FakeAuthClient();
      final browser = FakeOAuthBrowser(callbackUrl: 'bardizz://auth/callback?other=param');
      final controller =
          _buildController(client: client, browser: browser, tokenStore: FakeSecureTokenStore());

      await controller.signInWithGoogle();

      expect(controller.status, AuthStatus.signedOut);
      expect(controller.errorMessage, isNotNull);
      expect(client.lastExchangeCode, isNull);
    });
  });

  group('saveProfile', () {
    test('flips to signedIn once name and avatar are both set', () async {
      final client = FakeAuthClient()..exchangeResult = _session;
      final browser = FakeOAuthBrowser(callbackUrl: 'bardizz://auth/callback?insforge_code=abc123');
      final controller =
          _buildController(client: client, browser: browser, tokenStore: FakeSecureTokenStore());
      await controller.signInWithGoogle();
      expect(controller.status, AuthStatus.needsProfileSetup);

      await controller.saveProfile(displayName: 'Bob', avatarId: 'avatar-03');

      expect(controller.status, AuthStatus.signedIn);
      expect(controller.profile?.name, 'Bob');
      expect(controller.profile?.avatarId, 'avatar-03');
      expect(client.lastUpdateAccessToken, 'access-1');
    });
  });

  group('signOut', () {
    test('clears stored tokens and local state immediately', () async {
      final client = FakeAuthClient()..exchangeResult = _session;
      client.profile = const AuthProfile(name: 'Bob', avatarId: 'avatar-01');
      final browser = FakeOAuthBrowser(callbackUrl: 'bardizz://auth/callback?insforge_code=abc123');
      final tokenStore = FakeSecureTokenStore();
      final controller =
          _buildController(client: client, browser: browser, tokenStore: tokenStore);
      await controller.signInWithGoogle();
      expect(controller.status, AuthStatus.signedIn);

      await controller.signOut();

      expect(controller.status, AuthStatus.signedOut);
      expect(controller.user, isNull);
      expect(controller.profile, isNull);
      expect(tokenStore.accessToken, isNull);
      expect(tokenStore.refreshToken, isNull);
      expect(client.signOutCallCount, 1);
    });

    test('still clears local state even if the best-effort server logout call fails', () async {
      final client = FakeAuthClient()..exchangeResult = _session;
      client.profile = const AuthProfile(name: 'Bob', avatarId: 'avatar-01');
      final browser = FakeOAuthBrowser(callbackUrl: 'bardizz://auth/callback?insforge_code=abc123');
      final tokenStore = FakeSecureTokenStore();
      final controller =
          _buildController(client: client, browser: browser, tokenStore: tokenStore);
      await controller.signInWithGoogle();

      client.signOutError = Exception('network down');

      await controller.signOut();

      expect(controller.status, AuthStatus.signedOut);
      expect(tokenStore.accessToken, isNull);
    });
  });
}
