import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hockey_shot_tracker/backend/auth_controller.dart';
import 'package:hockey_shot_tracker/backend/auth_models.dart';
import 'package:hockey_shot_tracker/screens/profile_setup_screen.dart';

import '../support/fake_auth.dart';

const _user = AuthUser(id: 'user-1', email: 'user@example.com');
const _session = AuthSession(user: _user, accessToken: 'access-1', refreshToken: 'refresh-1');

void main() {
  setUp(() {
    // Widen past the default 800x600 test surface so the 24-avatar grid and
    // the Save button below it aren't clipped below the fold.
    final view = TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.physicalSize = const Size(800, 1600);
    view.devicePixelRatio = 1.0;
    addTearDown(view.resetPhysicalSize);
    addTearDown(view.resetDevicePixelRatio);
  });

  Future<AuthController> pumpSignedInNeedingProfile(WidgetTester tester) async {
    final client = FakeAuthClient()..exchangeResult = _session;
    final browser = FakeOAuthBrowser(callbackUrl: 'bardizz://auth/callback?insforge_code=abc123');
    final controller =
        AuthController(client: client, browser: browser, tokenStore: FakeSecureTokenStore());
    await controller.signInWithGoogle();

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: ProfileSetupScreen(controller: controller))),
    );
    return controller;
  }

  testWidgets('renders the display name field and the full 24-avatar grid', (tester) async {
    await pumpSignedInNeedingProfile(tester);

    expect(find.byKey(const Key('displayNameField')), findsOneWidget);
    expect(find.byKey(const Key('avatarTile_avatar-01')), findsOneWidget);
    expect(find.byKey(const Key('avatarTile_avatar-24')), findsOneWidget);
  });

  testWidgets('saving with no name and no avatar shows a validation error and does not save',
      (tester) async {
    final controller = await pumpSignedInNeedingProfile(tester);

    await tester.tap(find.byKey(const Key('saveProfileButton')));
    await tester.pump();

    expect(find.byKey(const Key('profileSetupErrorText')), findsOneWidget);
    expect(controller.status, AuthStatus.needsProfileSetup);
  });

  testWidgets('saving with a name but no avatar selected shows an error asking to choose one',
      (tester) async {
    await pumpSignedInNeedingProfile(tester);

    await tester.enterText(find.byKey(const Key('displayNameField')), 'Bob');
    await tester.tap(find.byKey(const Key('saveProfileButton')));
    await tester.pump();

    expect(find.text('Choose an avatar'), findsWidgets);
  });

  testWidgets('selecting an avatar and a valid name persists the profile and completes setup',
      (tester) async {
    final controller = await pumpSignedInNeedingProfile(tester);

    await tester.enterText(find.byKey(const Key('displayNameField')), 'Bob');
    await tester.tap(find.byKey(const Key('avatarTile_avatar-07')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('saveProfileButton')));
    await tester.pumpAndSettle();

    expect(controller.status, AuthStatus.signedIn);
    expect(controller.profile?.name, 'Bob');
    expect(controller.profile?.avatarId, 'avatar-07');
  });

  testWidgets('trims the display name before saving', (tester) async {
    final controller = await pumpSignedInNeedingProfile(tester);

    await tester.enterText(find.byKey(const Key('displayNameField')), '  Bob  ');
    await tester.tap(find.byKey(const Key('avatarTile_avatar-03')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('saveProfileButton')));
    await tester.pumpAndSettle();

    expect(controller.profile?.name, 'Bob');
  });

  testWidgets('the display name field enforces the 20-char max via its own input formatter',
      (tester) async {
    await pumpSignedInNeedingProfile(tester);

    await tester.enterText(find.byKey(const Key('displayNameField')), 'a' * 25);

    final field = tester.widget<TextField>(find.byKey(const Key('displayNameField')));
    expect(field.controller?.text.length, 20);
  });
}
