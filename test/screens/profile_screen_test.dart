import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hockey_shot_tracker/backend/auth_controller.dart';
import 'package:hockey_shot_tracker/backend/auth_models.dart';
import 'package:hockey_shot_tracker/screens/profile_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_auth.dart';
import '../support/fake_snapshots.dart';

const _user = AuthUser(id: 'user-1', email: 'user@example.com');
const _session = AuthSession(user: _user, accessToken: 'access-1', refreshToken: 'refresh-1');

/// Signs in for real (through the OAuth exchange) rather than poking public
/// fields, so [AuthController]'s internal access token is set -- required
/// for saveProfile/signOut to behave as they would after a real sign-in.
Future<AuthController> _signedInController({String? name, String? avatarId}) async {
  final client = FakeAuthClient()
    ..exchangeResult = _session
    ..profile = AuthProfile(name: name ?? 'Bob', avatarId: avatarId ?? 'avatar-01');
  final browser = FakeOAuthBrowser(callbackUrl: 'bardizz://auth/callback?insforge_code=abc123');
  final controller =
      AuthController(client: client, browser: browser, tokenStore: FakeSecureTokenStore());
  await controller.signInWithGoogle();
  return controller;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'high_score_shots': 10,
      'high_score_auto_bar_downs': 6,
      'high_score_manual_bar_downs': 1,
    });
    // Widen past the default 800x600 test surface so the edit-profile
    // avatar grid and Save button below it aren't clipped below the fold.
    final view = TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.physicalSize = const Size(800, 1600);
    view.devicePixelRatio = 1.0;
    addTearDown(view.resetPhysicalSize);
    addTearDown(view.resetDevicePixelRatio);
  });

  testWidgets('signed-out user is shown the sign-in gate instead of the profile', (tester) async {
    final controller = AuthController(
      client: FakeAuthClient(),
      browser: FakeOAuthBrowser(),
      tokenStore: FakeSecureTokenStore(),
    )..status = AuthStatus.signedOut;

    await tester.pumpWidget(
      MaterialApp(home: ProfileScreen(authController: controller, snapshotsClient: FakeSnapshotsClient())),
    );

    expect(find.byKey(const Key('signInGoogleButton')), findsOneWidget);
    expect(find.byKey(const Key('profileDisplayName')), findsNothing);
  });

  testWidgets('shows the display name, avatar and high-score snapshot for a complete profile',
      (tester) async {
    final controller = await _signedInController(name: 'Bob', avatarId: 'avatar-05');

    await tester.pumpWidget(
      MaterialApp(home: ProfileScreen(authController: controller, snapshotsClient: FakeSnapshotsClient())),
    );
    await tester.pump();

    expect(find.text('Bob'), findsOneWidget);
    expect(find.byKey(const Key('profileAvatarImage')), findsOneWidget);
    expect(find.byKey(const Key('profileHighScoreText')), findsOneWidget);
  });

  testWidgets('never renders the user email anywhere on the profile tab', (tester) async {
    final controller = AuthController(
      client: FakeAuthClient(),
      browser: FakeOAuthBrowser(),
      tokenStore: FakeSecureTokenStore(),
    )
      ..status = AuthStatus.signedIn
      ..user = const AuthUser(id: 'user-1', email: 'secret@example.com')
      ..profile = const AuthProfile(name: 'Bob', avatarId: 'avatar-05');

    await tester.pumpWidget(
      MaterialApp(home: ProfileScreen(authController: controller, snapshotsClient: FakeSnapshotsClient())),
    );
    await tester.pump();

    expect(find.textContaining('secret@example.com'), findsNothing);
    expect(find.textContaining('@'), findsNothing);
  });

  testWidgets('editing the profile shows profile setup pre-filled and returns to the display view on save',
      (tester) async {
    final controller = await _signedInController(name: 'Bob', avatarId: 'avatar-05');
    await tester.pumpWidget(
      MaterialApp(home: ProfileScreen(authController: controller, snapshotsClient: FakeSnapshotsClient())),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('editProfileButton')));
    await tester.pump();

    final field = tester.widget<TextField>(find.byKey(const Key('displayNameField')));
    expect(field.controller?.text, 'Bob');
    expect(find.byKey(const Key('avatarTile_avatar-05')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('displayNameField')), 'Bobby');
    await tester.pump();
    await tester.tap(find.byKey(const Key('avatarTile_avatar-09')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('saveProfileButton')));
    await tester.pumpAndSettle();

    expect(find.text('Bobby'), findsOneWidget);
    expect(controller.profile?.name, 'Bobby');
    expect(controller.profile?.avatarId, 'avatar-09');
  });

  testWidgets('editing the profile publishes the updated snapshot (AC-F6)', (tester) async {
    final controller = await _signedInController(name: 'Bob', avatarId: 'avatar-05');
    final snapshotsClient = FakeSnapshotsClient();
    await tester.pumpWidget(
      MaterialApp(home: ProfileScreen(authController: controller, snapshotsClient: snapshotsClient)),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('editProfileButton')));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('displayNameField')), 'Bobby');
    await tester.pump();
    await tester.tap(find.byKey(const Key('avatarTile_avatar-09')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('saveProfileButton')));
    await tester.pumpAndSettle();

    expect(snapshotsClient.upsertCallCount, 1);
    expect(snapshotsClient.lastUpsertUserId, 'user-1');
    expect(snapshotsClient.lastUpsertDisplayName, 'Bobby');
    expect(snapshotsClient.lastUpsertAvatarId, 'avatar-09');
  });

  testWidgets('editing the profile with no recorded high score does not publish a fabricated snapshot',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final controller = await _signedInController(name: 'Bob', avatarId: 'avatar-05');
    final snapshotsClient = FakeSnapshotsClient();
    await tester.pumpWidget(
      MaterialApp(home: ProfileScreen(authController: controller, snapshotsClient: snapshotsClient)),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('editProfileButton')));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('displayNameField')), 'Bobby');
    await tester.pump();
    await tester.tap(find.byKey(const Key('avatarTile_avatar-09')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('saveProfileButton')));
    await tester.pumpAndSettle();

    expect(snapshotsClient.upsertCallCount, 0);
  });

  testWidgets('signing out clears the controller state and shows the sign-in gate again',
      (tester) async {
    final controller = await _signedInController();
    await tester.pumpWidget(
      MaterialApp(home: ProfileScreen(authController: controller, snapshotsClient: FakeSnapshotsClient())),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('signOutButton')));
    await tester.pumpAndSettle();

    expect(controller.status, AuthStatus.signedOut);
    expect(find.byKey(const Key('signInGoogleButton')), findsOneWidget);
  });
}
