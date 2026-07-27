import 'package:flutter_test/flutter_test.dart';
import 'package:hockey_shot_tracker/backend/auth_controller.dart';
import 'package:hockey_shot_tracker/backend/auth_models.dart';
import 'package:hockey_shot_tracker/backend/snapshot_sync_controller.dart';
import 'package:hockey_shot_tracker/scoreboard/high_score_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_auth.dart';
import '../support/fake_snapshots.dart';

SnapshotSyncController _controller(FakeSnapshotsClient client) => SnapshotSyncController(client: client);

const _session = AuthSession(
  user: AuthUser(id: 'me', email: 'me@example.com'),
  accessToken: 'access-1',
  refreshToken: 'refresh-1',
);

Future<AuthController> _signedInAuth() async {
  final client = FakeAuthClient()
    ..exchangeResult = _session
    ..profile = const AuthProfile(name: 'Bob', avatarId: 'avatar-01');
  final browser = FakeOAuthBrowser(callbackUrl: 'bardizz://auth/callback?insforge_code=abc123');
  final controller = AuthController(client: client, browser: browser, tokenStore: FakeSecureTokenStore());
  await controller.signInWithGoogle();
  return controller;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('snapshotSignature', () {
    test('equal inputs produce equal signatures', () {
      final a = snapshotSignature(rate: 0.5, count: 10, displayName: 'Bob', avatarId: 'avatar-01');
      final b = snapshotSignature(rate: 0.5, count: 10, displayName: 'Bob', avatarId: 'avatar-01');
      expect(a, b);
    });

    test('a different rate changes the signature', () {
      final a = snapshotSignature(rate: 0.5, count: 10, displayName: 'Bob', avatarId: 'avatar-01');
      final b = snapshotSignature(rate: 0.6, count: 10, displayName: 'Bob', avatarId: 'avatar-01');
      expect(a, isNot(b));
    });

    test('a different count changes the signature', () {
      final a = snapshotSignature(rate: 0.5, count: 10, displayName: 'Bob', avatarId: 'avatar-01');
      final b = snapshotSignature(rate: 0.5, count: 11, displayName: 'Bob', avatarId: 'avatar-01');
      expect(a, isNot(b));
    });

    test('a different display name changes the signature', () {
      final a = snapshotSignature(rate: 0.5, count: 10, displayName: 'Bob', avatarId: 'avatar-01');
      final b = snapshotSignature(rate: 0.5, count: 10, displayName: 'Bobby', avatarId: 'avatar-01');
      expect(a, isNot(b));
    });

    test('a different avatar id changes the signature', () {
      final a = snapshotSignature(rate: 0.5, count: 10, displayName: 'Bob', avatarId: 'avatar-01');
      final b = snapshotSignature(rate: 0.5, count: 10, displayName: 'Bob', avatarId: 'avatar-02');
      expect(a, isNot(b));
    });
  });

  group('SnapshotSyncController.sync', () {
    test('does not publish when no high score has ever been recorded', () async {
      final client = FakeSnapshotsClient();
      final controller = _controller(client);

      final published = await controller.sync(
        userId: 'me',
        accessToken: 'token',
        displayName: 'Bob',
        avatarId: 'avatar-01',
      );

      expect(published, isFalse);
      expect(client.upsertCallCount, 0);
    });

    test('publishes on the first sync once a high score is recorded (new-high-score publish)', () async {
      const highScoreStore = HighScoreStore();
      await highScoreStore.considerSession(sessionShots: 10, sessionAutoBarDowns: 5, sessionManualBarDowns: 0);
      final client = FakeSnapshotsClient();
      final controller = SnapshotSyncController(client: client, highScoreStore: highScoreStore);

      final published = await controller.sync(
        userId: 'me',
        accessToken: 'token',
        displayName: 'Bob',
        avatarId: 'avatar-01',
      );

      expect(published, isTrue);
      expect(client.upsertCallCount, 1);
      expect(client.lastUpsertUserId, 'me');
      expect(client.lastUpsertAccessToken, 'token');
      expect(client.lastUpsertDisplayName, 'Bob');
      expect(client.lastUpsertAvatarId, 'avatar-01');
      expect(client.lastUpsertRate, 0.5);
      expect(client.lastUpsertCount, 5);
    });

    test('a non-high-score session does not change the local high score, so a repeat sync does not republish',
        () async {
      const highScoreStore = HighScoreStore();
      await highScoreStore.considerSession(sessionShots: 10, sessionAutoBarDowns: 8, sessionManualBarDowns: 0);
      final client = FakeSnapshotsClient();
      final controller = SnapshotSyncController(client: client, highScoreStore: highScoreStore);
      await controller.sync(userId: 'me', accessToken: 'token', displayName: 'Bob', avatarId: 'avatar-01');
      expect(client.upsertCallCount, 1);

      // A worse session is considered but does not win, so the stored high score is unchanged.
      await highScoreStore.considerSession(sessionShots: 10, sessionAutoBarDowns: 1, sessionManualBarDowns: 0);
      final published = await controller.sync(
        userId: 'me',
        accessToken: 'token',
        displayName: 'Bob',
        avatarId: 'avatar-01',
      );

      expect(published, isFalse);
      expect(client.upsertCallCount, 1, reason: 'signature unchanged, no republish');
    });

    test('a new higher high score republishes', () async {
      const highScoreStore = HighScoreStore();
      await highScoreStore.considerSession(sessionShots: 10, sessionAutoBarDowns: 5, sessionManualBarDowns: 0);
      final client = FakeSnapshotsClient();
      final controller = SnapshotSyncController(client: client, highScoreStore: highScoreStore);
      await controller.sync(userId: 'me', accessToken: 'token', displayName: 'Bob', avatarId: 'avatar-01');

      await highScoreStore.considerSession(sessionShots: 10, sessionAutoBarDowns: 9, sessionManualBarDowns: 0);
      final published = await controller.sync(
        userId: 'me',
        accessToken: 'token',
        displayName: 'Bob',
        avatarId: 'avatar-01',
      );

      expect(published, isTrue);
      expect(client.upsertCallCount, 2);
      expect(client.lastUpsertCount, 9);
    });

    test('a profile edit alone (display name change) republishes even with an unchanged high score (AC-F6)',
        () async {
      const highScoreStore = HighScoreStore();
      await highScoreStore.considerSession(sessionShots: 10, sessionAutoBarDowns: 5, sessionManualBarDowns: 0);
      final client = FakeSnapshotsClient();
      final controller = SnapshotSyncController(client: client, highScoreStore: highScoreStore);
      await controller.sync(userId: 'me', accessToken: 'token', displayName: 'Bob', avatarId: 'avatar-01');

      final published = await controller.sync(
        userId: 'me',
        accessToken: 'token',
        displayName: 'Bobby',
        avatarId: 'avatar-01',
      );

      expect(published, isTrue);
      expect(client.upsertCallCount, 2);
      expect(client.lastUpsertDisplayName, 'Bobby');
    });

    test('an avatar edit alone republishes even with an unchanged high score (AC-F6)', () async {
      const highScoreStore = HighScoreStore();
      await highScoreStore.considerSession(sessionShots: 10, sessionAutoBarDowns: 5, sessionManualBarDowns: 0);
      final client = FakeSnapshotsClient();
      final controller = SnapshotSyncController(client: client, highScoreStore: highScoreStore);
      await controller.sync(userId: 'me', accessToken: 'token', displayName: 'Bob', avatarId: 'avatar-01');

      final published = await controller.sync(
        userId: 'me',
        accessToken: 'token',
        displayName: 'Bob',
        avatarId: 'avatar-02',
      );

      expect(published, isTrue);
      expect(client.lastUpsertAvatarId, 'avatar-02');
    });

    test('a failed network write leaves the signature stale so the next sync retries (offline catch-up)',
        () async {
      const highScoreStore = HighScoreStore();
      await highScoreStore.considerSession(sessionShots: 10, sessionAutoBarDowns: 5, sessionManualBarDowns: 0);
      final client = FakeSnapshotsClient()..upsertError = Exception('offline');
      final controller = SnapshotSyncController(client: client, highScoreStore: highScoreStore);

      final firstAttempt = await controller.sync(
        userId: 'me',
        accessToken: 'token',
        displayName: 'Bob',
        avatarId: 'avatar-01',
      );
      expect(firstAttempt, isFalse);

      client.upsertError = null;
      final secondAttempt = await controller.sync(
        userId: 'me',
        accessToken: 'token',
        displayName: 'Bob',
        avatarId: 'avatar-01',
      );

      expect(secondAttempt, isTrue, reason: 'the unchanged-but-never-confirmed signature must retry');
      expect(client.upsertCallCount, 2);
    });

    test('awaiting sync never throws when the client throws', () async {
      const highScoreStore = HighScoreStore();
      await highScoreStore.considerSession(sessionShots: 10, sessionAutoBarDowns: 5, sessionManualBarDowns: 0);
      final client = FakeSnapshotsClient()..upsertError = Exception('boom');
      final controller = SnapshotSyncController(client: client, highScoreStore: highScoreStore);

      await expectLater(
        controller.sync(userId: 'me', accessToken: 'token', displayName: 'Bob', avatarId: 'avatar-01'),
        completion(isFalse),
      );
    });
  });

  group('SnapshotSyncController.syncFromAuth (the app-foreground publish hook)', () {
    test('is a no-op when signed out (no user/token)', () async {
      final auth = AuthController(
        client: FakeAuthClient(),
        browser: FakeOAuthBrowser(),
        tokenStore: FakeSecureTokenStore(),
      );
      final client = FakeSnapshotsClient();
      final controller = _controller(client);

      final published = await controller.syncFromAuth(auth);

      expect(published, isFalse);
      expect(client.upsertCallCount, 0);
    });

    test('publishes using the signed-in id/token/profile when a high score exists', () async {
      const highScoreStore = HighScoreStore();
      await highScoreStore.considerSession(sessionShots: 10, sessionAutoBarDowns: 5, sessionManualBarDowns: 0);
      final auth = await _signedInAuth();
      final client = FakeSnapshotsClient();
      final controller = SnapshotSyncController(client: client, highScoreStore: highScoreStore);

      final published = await controller.syncFromAuth(auth);

      expect(published, isTrue);
      expect(client.upsertCallCount, 1);
      expect(client.lastUpsertUserId, 'me');
      expect(client.lastUpsertAccessToken, 'access-1');
      expect(client.lastUpsertDisplayName, 'Bob');
      expect(client.lastUpsertAvatarId, 'avatar-01');
    });
  });
}
