import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hockey_shot_tracker/backend/auth_controller.dart';
import 'package:hockey_shot_tracker/backend/auth_models.dart';
import 'package:hockey_shot_tracker/backend/challenge_client.dart';
import 'package:hockey_shot_tracker/backend/friends_models.dart';
import 'package:hockey_shot_tracker/backend/snapshot_models.dart';
import 'package:hockey_shot_tracker/screens/friends_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_auth.dart';
import '../support/fake_challenge.dart';
import '../support/fake_friends.dart';
import '../support/fake_snapshots.dart';

const _me = AuthUser(id: 'me', email: 'me@example.com');
const _session = AuthSession(user: _me, accessToken: 'access-1', refreshToken: 'refresh-1');

/// Signs in for real (through the OAuth exchange), matching how
/// profile_screen_test builds a signed-in controller, so [AuthController]'s
/// internal access token/user are populated the way FriendsScreen needs.
Future<AuthController> _signedInController() async {
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

  Future<void> pump(
    WidgetTester tester,
    AuthController controller, {
    FakeFriendsClient? friendsClient,
    FakeSnapshotsClient? snapshotsClient,
    FakeChallengeClient? challengeClient,
    bool isActive = true,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: FriendsScreen(
        authController: controller,
        friendsClient: friendsClient ?? FakeFriendsClient(),
        snapshotsClient: snapshotsClient ?? FakeSnapshotsClient(),
        challengeClient: challengeClient ?? FakeChallengeClient(),
        isActive: isActive,
      ),
    ));
    // The leaderboard owns a ~30s poll Timer; dispose the tree before the
    // test ends so flutter_test doesn't flag it as still pending.
    addTearDown(() async {
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('signed-out user is shown the sign-in gate instead of the friends list', (tester) async {
    final controller = AuthController(
      client: FakeAuthClient(),
      browser: FakeOAuthBrowser(),
      tokenStore: FakeSecureTokenStore(),
    )..status = AuthStatus.signedOut;

    await pump(tester, controller);

    expect(find.byKey(const Key('signInGoogleButton')), findsOneWidget);
    expect(find.byKey(const Key('signInGithubButton')), findsOneWidget);
    expect(find.byKey(const Key('addFriendButton')), findsNothing);
  });

  testWidgets('a signed-in user with an incomplete profile is shown profile setup, not the friends list',
      (tester) async {
    final controller = AuthController(
      client: FakeAuthClient(),
      browser: FakeOAuthBrowser(),
      tokenStore: FakeSecureTokenStore(),
    )..status = AuthStatus.needsProfileSetup;

    await pump(tester, controller);

    expect(find.byKey(const Key('displayNameField')), findsOneWidget);
    expect(find.byKey(const Key('addFriendButton')), findsNothing);
  });

  testWidgets('shows a restoring indicator while session restore is still in flight', (tester) async {
    final controller = AuthController(
      client: FakeAuthClient(),
      browser: FakeOAuthBrowser(),
      tokenStore: FakeSecureTokenStore(),
    );
    expect(controller.status, AuthStatus.restoring);

    await pump(tester, controller);

    expect(find.byKey(const Key('authRestoringIndicator')), findsOneWidget);
    expect(find.byKey(const Key('signInGoogleButton')), findsNothing);
  });

  testWidgets('a fully signed-in user sees the add-by-email field and button', (tester) async {
    final controller = await _signedInController();

    await pump(tester, controller);
    await tester.pump();

    expect(find.byKey(const Key('addFriendEmailField')), findsOneWidget);
    expect(find.byKey(const Key('addFriendButton')), findsOneWidget);
  });

  testWidgets('adding an existing user by email shows the requested confirmation', (tester) async {
    final controller = await _signedInController();
    final friendsClient = FakeFriendsClient()..requestFriendResult = 'requested';

    await pump(tester, controller, friendsClient: friendsClient);
    await tester.pump();
    await tester.enterText(find.byKey(const Key('addFriendEmailField')), 'friend@example.com');
    await tester.tap(find.byKey(const Key('addFriendButton')));
    await tester.pumpAndSettle();

    expect(friendsClient.lastRequestedEmail, 'friend@example.com');
    expect(find.text('Friend request sent.'), findsOneWidget);
  });

  testWidgets('a self-request shows a clear message and does not crash', (tester) async {
    final controller = await _signedInController();
    final friendsClient = FakeFriendsClient()..requestFriendResult = 'self';

    await pump(tester, controller, friendsClient: friendsClient);
    await tester.pump();
    await tester.enterText(find.byKey(const Key('addFriendEmailField')), 'me@example.com');
    await tester.tap(find.byKey(const Key('addFriendButton')));
    await tester.pumpAndSettle();

    expect(find.text("You can't add yourself."), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a duplicate request shows a clear message and does not crash', (tester) async {
    final controller = await _signedInController();
    final friendsClient = FakeFriendsClient()..requestFriendResult = 'duplicate';

    await pump(tester, controller, friendsClient: friendsClient);
    await tester.pump();
    await tester.enterText(find.byKey(const Key('addFriendEmailField')), 'friend@example.com');
    await tester.tap(find.byKey(const Key('addFriendButton')));
    await tester.pumpAndSettle();

    expect(find.text("You're already connected (or a request is pending)."), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an invalid email shows a clear message and does not crash', (tester) async {
    final controller = await _signedInController();
    final friendsClient = FakeFriendsClient()..requestFriendResult = 'invalid_email';

    await pump(tester, controller, friendsClient: friendsClient);
    await tester.pump();
    await tester.enterText(find.byKey(const Key('addFriendEmailField')), 'not-an-email');
    await tester.tap(find.byKey(const Key('addFriendButton')));
    await tester.pumpAndSettle();

    expect(find.text('Enter a valid email.'), findsOneWidget);
  });

  testWidgets('a non-user email offers a challenge invite that actually sends one', (tester) async {
    final controller = await _signedInController();
    final friendsClient = FakeFriendsClient()..requestFriendResult = 'not_a_user';
    final challengeClient = FakeChallengeClient()..result = ChallengeOutcome.invited;

    await pump(tester, controller, friendsClient: friendsClient, challengeClient: challengeClient);
    await tester.pump();
    await tester.enterText(find.byKey(const Key('addFriendEmailField')), 'nobody@example.com');
    await tester.tap(find.byKey(const Key('addFriendButton')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('inviteChallengeButton')), findsOneWidget);

    await tester.tap(find.byKey(const Key('inviteChallengeButton')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('inviteChallengeButton')), findsNothing);
    expect(challengeClient.callCount, 1, reason: 'the invite button must trigger a real challenge send');
    expect(challengeClient.lastTargetEmail, 'nobody@example.com');
    expect(find.text("Invite sent -- they'll be added once they join BarDizz."), findsOneWidget);
  });

  testWidgets('a signed-in user sees the challenge button', (tester) async {
    final controller = await _signedInController();

    await pump(tester, controller);
    await tester.pump();

    expect(find.byKey(const Key('challengeFriendButton')), findsOneWidget);
  });

  testWidgets('challenging an existing user shows the existing-user confirmation', (tester) async {
    final controller = await _signedInController();
    final challengeClient = FakeChallengeClient()..result = ChallengeOutcome.existingUser;

    await pump(tester, controller, challengeClient: challengeClient);
    await tester.pump();
    await tester.enterText(find.byKey(const Key('addFriendEmailField')), 'friend@example.com');
    await tester.tap(find.byKey(const Key('challengeFriendButton')));
    await tester.pumpAndSettle();

    expect(challengeClient.lastTargetEmail, 'friend@example.com');
    expect(find.text("Challenge sent -- they'll get your request in the app."), findsOneWidget);
  });

  testWidgets('challenging a non-user shows the invited confirmation', (tester) async {
    final controller = await _signedInController();
    final challengeClient = FakeChallengeClient()..result = ChallengeOutcome.invited;

    await pump(tester, controller, challengeClient: challengeClient);
    await tester.pump();
    await tester.enterText(find.byKey(const Key('addFriendEmailField')), 'stranger@example.com');
    await tester.tap(find.byKey(const Key('challengeFriendButton')));
    await tester.pumpAndSettle();

    expect(find.text("Invite sent -- they'll be added once they join BarDizz."), findsOneWidget);
  });

  testWidgets('challenging yourself is guarded locally without calling the server', (tester) async {
    final controller = await _signedInController();
    final challengeClient = FakeChallengeClient();

    await pump(tester, controller, challengeClient: challengeClient);
    await tester.pump();
    // _me is me@example.com; upper-cased to prove the guard normalizes case.
    await tester.enterText(find.byKey(const Key('addFriendEmailField')), 'ME@example.com');
    await tester.tap(find.byKey(const Key('challengeFriendButton')));
    await tester.pumpAndSettle();

    expect(find.text("You can't challenge yourself."), findsOneWidget);
    expect(challengeClient.callCount, 0, reason: 'a self-challenge must never round-trip');
  });

  testWidgets('challenging a malformed email is guarded locally without calling the server', (tester) async {
    final controller = await _signedInController();
    final challengeClient = FakeChallengeClient();

    await pump(tester, controller, challengeClient: challengeClient);
    await tester.pump();
    await tester.enterText(find.byKey(const Key('addFriendEmailField')), 'not-an-email');
    await tester.tap(find.byKey(const Key('challengeFriendButton')));
    await tester.pumpAndSettle();

    expect(find.text('Enter a valid email.'), findsOneWidget);
    expect(challengeClient.callCount, 0, reason: 'an invalid email must never round-trip');
  });

  testWidgets('a challenge transport failure shows a retry message and does not crash', (tester) async {
    final controller = await _signedInController();
    final challengeClient = FakeChallengeClient()..error = const ChallengeException('down');

    await pump(tester, controller, challengeClient: challengeClient);
    await tester.pump();
    await tester.enterText(find.byKey(const Key('addFriendEmailField')), 'friend@example.com');
    await tester.tap(find.byKey(const Key('challengeFriendButton')));
    await tester.pumpAndSettle();

    expect(find.text("Couldn't send the challenge. Try again."), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('incoming pending requests can be accepted, moving them into friends', (tester) async {
    final controller = await _signedInController();
    final friendsClient = FakeFriendsClient()
      ..links = [
        const FriendLink(id: 'l1', requesterId: 'other-1', addresseeId: 'me', status: FriendLinkStatus.pending),
      ]
      ..profilesByUserId = {'other-1': const AuthProfile(name: 'Alice', avatarId: 'avatar-02')};

    await pump(tester, controller, friendsClient: friendsClient);
    await tester.pumpAndSettle();

    expect(find.text('Alice'), findsOneWidget);
    expect(find.byKey(const Key('acceptButton_l1')), findsOneWidget);

    await tester.tap(find.byKey(const Key('acceptButton_l1')));
    await tester.pumpAndSettle();

    expect(friendsClient.lastAcceptedLinkId, 'l1');
    expect(find.byKey(const Key('acceptButton_l1')), findsNothing);
  });

  testWidgets('incoming pending requests can be declined, removing the link', (tester) async {
    final controller = await _signedInController();
    final friendsClient = FakeFriendsClient()
      ..links = [
        const FriendLink(id: 'l1', requesterId: 'other-1', addresseeId: 'me', status: FriendLinkStatus.pending),
      ]
      ..profilesByUserId = {'other-1': const AuthProfile(name: 'Alice', avatarId: 'avatar-02')};

    await pump(tester, controller, friendsClient: friendsClient);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('declineButton_l1')));
    await tester.pumpAndSettle();

    expect(friendsClient.lastDeletedLinkId, 'l1');
    expect(find.text('Alice'), findsNothing);
    expect(find.text('No incoming requests'), findsOneWidget);
  });

  testWidgets('outgoing pending requests are visible', (tester) async {
    final controller = await _signedInController();
    final friendsClient = FakeFriendsClient()
      ..links = [
        const FriendLink(id: 'l2', requesterId: 'me', addresseeId: 'other-2', status: FriendLinkStatus.pending),
      ]
      ..profilesByUserId = {'other-2': const AuthProfile(name: 'Carl', avatarId: 'avatar-03')};

    await pump(tester, controller, friendsClient: friendsClient);
    await tester.pumpAndSettle();

    expect(find.text('Carl'), findsOneWidget);
    expect(find.byKey(const Key('friendRow_l2')), findsOneWidget);
  });

  testWidgets('never renders the user email anywhere on the friends tab', (tester) async {
    final controller = await _signedInController();
    final friendsClient = FakeFriendsClient()
      ..links = [
        const FriendLink(id: 'l3', requesterId: 'me', addresseeId: 'other-3', status: FriendLinkStatus.accepted),
      ]
      ..profilesByUserId = {'other-3': const AuthProfile(name: 'Dana', avatarId: 'avatar-04')};
    final snapshotsClient = FakeSnapshotsClient()
      ..leaderboard = [
        const Snapshot(userId: 'other-3', displayName: 'Dana', avatarId: 'avatar-04', barDownRate: 0.4, barDownCount: 4),
      ];

    await pump(tester, controller, friendsClient: friendsClient, snapshotsClient: snapshotsClient);
    await tester.pumpAndSettle();

    expect(find.textContaining('@'), findsNothing);
  });

  group('leaderboard', () {
    testWidgets('self always appears, showing "--" for rate/count with no recorded high score', (tester) async {
      final controller = await _signedInController();

      await pump(tester, controller);
      await tester.pumpAndSettle();

      expect(find.text('Bob (You)'), findsOneWidget);
      expect(find.byKey(const Key('leaderboardRate_me')), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('leaderboardRate_me'))).data, '—');
      expect(tester.widget<Text>(find.byKey(const Key('leaderboardCount_me'))).data, '—');
    });

    testWidgets('ranks a friend above self by rate and highlights self distinctly', (tester) async {
      final controller = await _signedInController();
      final friendsClient = FakeFriendsClient()
        ..links = [
          const FriendLink(id: 'l1', requesterId: 'me', addresseeId: 'f1', status: FriendLinkStatus.accepted),
        ]
        ..profilesByUserId = {'f1': const AuthProfile(name: 'Alice', avatarId: 'avatar-02')};
      final snapshotsClient = FakeSnapshotsClient()
        ..leaderboard = [
          const Snapshot(userId: 'me', displayName: 'Bob', avatarId: 'avatar-01', barDownRate: 0.4, barDownCount: 4),
          const Snapshot(userId: 'f1', displayName: 'Alice', avatarId: 'avatar-02', barDownRate: 0.8, barDownCount: 8),
        ];

      await pump(tester, controller, friendsClient: friendsClient, snapshotsClient: snapshotsClient);
      await tester.pumpAndSettle();

      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Bob (You)'), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('leaderboardRate_f1'))).data, '80%');
      expect(tester.widget<Text>(find.byKey(const Key('leaderboardRate_me'))).data, '40%');

      // Alice's row (rank 1, higher rate) must come before Bob's in the render order.
      final aliceRowCenter = tester.getCenter(find.byKey(const Key('leaderboardRow_f1')));
      final bobRowCenter = tester.getCenter(find.byKey(const Key('leaderboardRow_me')));
      expect(aliceRowCenter.dy, lessThan(bobRowCenter.dy));
    });

    testWidgets('shows a prompt to add a friend when there are no accepted friends yet', (tester) async {
      final controller = await _signedInController();

      await pump(tester, controller);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('leaderboardEmptyFriendsPrompt')), findsOneWidget);
    });

    testWidgets('the prompt disappears once an accepted friend exists', (tester) async {
      final controller = await _signedInController();
      final friendsClient = FakeFriendsClient()
        ..links = [
          const FriendLink(id: 'l1', requesterId: 'me', addresseeId: 'f1', status: FriendLinkStatus.accepted),
        ]
        ..profilesByUserId = {'f1': const AuthProfile(name: 'Alice', avatarId: 'avatar-02')};

      await pump(tester, controller, friendsClient: friendsClient);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('leaderboardEmptyFriendsPrompt')), findsNothing);
    });

    testWidgets('an accepted friend who has not published a snapshot yet still appears, with "--"', (tester) async {
      final controller = await _signedInController();
      final friendsClient = FakeFriendsClient()
        ..links = [
          const FriendLink(id: 'l1', requesterId: 'me', addresseeId: 'f1', status: FriendLinkStatus.accepted),
        ]
        ..profilesByUserId = {'f1': const AuthProfile(name: 'Alice', avatarId: 'avatar-02')};
      // No snapshot rows at all: neither self nor the friend has published.
      final snapshotsClient = FakeSnapshotsClient();

      await pump(tester, controller, friendsClient: friendsClient, snapshotsClient: snapshotsClient);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('leaderboardRow_f1')), findsOneWidget, reason: 'accepted friend must appear (AC-F1)');
      expect(find.text('Alice'), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('leaderboardRate_f1'))).data, '—');
      expect(tester.widget<Text>(find.byKey(const Key('leaderboardCount_f1'))).data, '—');
    });

    testWidgets('removing an accepted friend from the leaderboard unfriends them and refreshes the board',
        (tester) async {
      final controller = await _signedInController();
      final friendsClient = FakeFriendsClient()
        ..links = [
          const FriendLink(id: 'l3', requesterId: 'me', addresseeId: 'other-3', status: FriendLinkStatus.accepted),
        ]
        ..profilesByUserId = {'other-3': const AuthProfile(name: 'Dana', avatarId: 'avatar-04')};
      final snapshotsClient = FakeSnapshotsClient()
        ..leaderboard = [
          const Snapshot(userId: 'other-3', displayName: 'Dana', avatarId: 'avatar-04', barDownRate: 0.4, barDownCount: 4),
        ];

      await pump(tester, controller, friendsClient: friendsClient, snapshotsClient: snapshotsClient);
      await tester.pumpAndSettle();

      expect(find.text('Dana'), findsOneWidget);
      final fetchesBeforeRemove = snapshotsClient.fetchCallCount;

      await tester.tap(find.byKey(const Key('removeButton_l3')));
      await tester.pumpAndSettle();

      expect(friendsClient.lastDeletedLinkId, 'l3');
      expect(find.byKey(const Key('leaderboardEmptyFriendsPrompt')), findsOneWidget);
      expect(snapshotsClient.fetchCallCount, greaterThan(fetchesBeforeRemove),
          reason: 'unfriending should refresh the leaderboard read side');
    });

    testWidgets('offline shows the last-synced snapshots with an offline indicator, not an error/empty screen',
        (tester) async {
      final controller = await _signedInController();
      final friendsClient = FakeFriendsClient()
        ..links = [
          const FriendLink(id: 'l1', requesterId: 'me', addresseeId: 'f1', status: FriendLinkStatus.accepted),
        ]
        ..profilesByUserId = {'f1': const AuthProfile(name: 'Alice', avatarId: 'avatar-02')};
      final snapshotsClient = FakeSnapshotsClient()
        ..leaderboard = [
          const Snapshot(userId: 'f1', displayName: 'Alice', avatarId: 'avatar-02', barDownRate: 0.8, barDownCount: 8),
        ];

      await pump(tester, controller, friendsClient: friendsClient, snapshotsClient: snapshotsClient);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('leaderboardOfflineIndicator')), findsNothing);

      snapshotsClient.fetchError = Exception('network down');
      final refreshIndicator =
          tester.widget<RefreshIndicator>(find.byKey(const Key('leaderboardRefreshIndicator')));
      await refreshIndicator.onRefresh();
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('leaderboardOfflineIndicator')), findsOneWidget);
      expect(find.text('Alice'), findsOneWidget, reason: 'last-synced data stays visible, not an empty screen');
    });

    testWidgets('pull-to-refresh (the RefreshIndicator callback) re-fetches the leaderboard', (tester) async {
      final controller = await _signedInController();
      final snapshotsClient = FakeSnapshotsClient();

      await pump(tester, controller, snapshotsClient: snapshotsClient);
      await tester.pumpAndSettle();
      final initialFetches = snapshotsClient.fetchCallCount;

      final refreshIndicator =
          tester.widget<RefreshIndicator>(find.byKey(const Key('leaderboardRefreshIndicator')));
      await refreshIndicator.onRefresh();
      await tester.pumpAndSettle();

      expect(snapshotsClient.fetchCallCount, initialFetches + 1);
    });

    testWidgets('polls again after ~30s while the tab is active and the app is foregrounded', (tester) async {
      final controller = await _signedInController();
      final snapshotsClient = FakeSnapshotsClient();

      await pump(tester, controller, snapshotsClient: snapshotsClient, isActive: true);
      await tester.pumpAndSettle();
      expect(snapshotsClient.fetchCallCount, 1);

      await tester.pump(const Duration(seconds: 31));
      await tester.pump();

      expect(snapshotsClient.fetchCallCount, 2);
    });

    testWidgets('does not poll while the tab is not active', (tester) async {
      final controller = await _signedInController();
      final snapshotsClient = FakeSnapshotsClient();

      await pump(tester, controller, snapshotsClient: snapshotsClient, isActive: false);
      await tester.pumpAndSettle();
      expect(snapshotsClient.fetchCallCount, 1, reason: 'one fetch on mount regardless of active tab');

      await tester.pump(const Duration(seconds: 31));
      await tester.pump();

      expect(snapshotsClient.fetchCallCount, 1, reason: 'no poll while not the active tab');
    });

    testWidgets('starts polling once the tab becomes active (isActive false -> true)', (tester) async {
      final controller = await _signedInController();
      final friendsClient = FakeFriendsClient();
      final snapshotsClient = FakeSnapshotsClient();
      addTearDown(() async {
        await tester.pumpAndSettle();
        await tester.pumpWidget(const SizedBox());
      });

      final challengeClient = FakeChallengeClient();
      await tester.pumpWidget(MaterialApp(
        home: FriendsScreen(
          authController: controller,
          friendsClient: friendsClient,
          snapshotsClient: snapshotsClient,
          challengeClient: challengeClient,
          isActive: false,
        ),
      ));
      await tester.pumpAndSettle();
      expect(snapshotsClient.fetchCallCount, 1);

      await tester.pumpWidget(MaterialApp(
        home: FriendsScreen(
          authController: controller,
          friendsClient: friendsClient,
          snapshotsClient: snapshotsClient,
          challengeClient: challengeClient,
          isActive: true,
        ),
      ));
      await tester.pumpAndSettle();
      expect(snapshotsClient.fetchCallCount, 2, reason: 'becoming active triggers an immediate refresh');

      await tester.pump(const Duration(seconds: 31));
      await tester.pump();
      expect(snapshotsClient.fetchCallCount, 3, reason: 'polling now runs since the tab is active');
    });
  });
}
