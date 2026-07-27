import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hockey_shot_tracker/audio/mic_level_controller.dart';
import 'package:hockey_shot_tracker/backend/auth_controller.dart';
import 'package:hockey_shot_tracker/screens/nav_shell.dart';
import 'package:hockey_shot_tracker/screens/session_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_auth.dart';
import '../support/fake_challenge.dart';
import '../support/fake_friends.dart';
import '../support/fake_snapshots.dart';

class FakeMicLevelController implements MicLevelController {
  final StreamController<double> _levelController = StreamController<double>.broadcast();
  final StreamController<int> _shotCountController = StreamController<int>.broadcast();
  final StreamController<int> _barDownCountController = StreamController<int>.broadcast();
  int startCallCount = 0;
  bool stopped = false;

  @override
  Stream<double> get levels => _levelController.stream;

  @override
  Stream<int> get shotCount => _shotCountController.stream;

  @override
  Stream<int> get barDownCount => _barDownCountController.stream;

  @override
  bool get isCapturing => startCallCount > 0 && !stopped;

  @override
  Future<void> start() async => startCallCount++;

  @override
  Future<void> stop() async => stopped = true;

  void emitShotCount(int count) => _shotCountController.add(count);

  void dispose() {
    _levelController.close();
    _shotCountController.close();
    _barDownCountController.close();
  }
}

void main() {
  late FakeMicLevelController controller;

  setUp(() {
    controller = FakeMicLevelController();
    SharedPreferences.setMockInitialValues({});
    // Widen past the default 800x600 test surface so the bottom nav bar and
    // session content aren't clipped below the fold.
    final view = TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.physicalSize = const Size(800, 1600);
    view.devicePixelRatio = 1.0;
    addTearDown(view.resetPhysicalSize);
    addTearDown(view.resetDevicePixelRatio);
  });

  tearDown(() {
    controller.dispose();
  });

  Future<void> pumpShell(
    WidgetTester tester, {
    Future<void> Function()? onSettingsTap,
  }) async {
    final authController = AuthController(
      client: FakeAuthClient(),
      browser: FakeOAuthBrowser(),
      tokenStore: FakeSecureTokenStore(),
    )..status = AuthStatus.signedOut;
    await tester.pumpWidget(
      MaterialApp(
        home: NavShell(
          sessionScreen: SessionScreen(
            controller: controller,
            onSettingsTap: onSettingsTap,
          ),
          authController: authController,
          friendsClient: FakeFriendsClient(),
          snapshotsClient: FakeSnapshotsClient(),
          challengeClient: FakeChallengeClient(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // The Friends leaderboard owns a ~30s poll Timer while active; dispose
    // the tree before the test ends so flutter_test doesn't flag it pending.
    addTearDown(() async {
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
    });
  }

  BottomNavigationBar bottomNav(WidgetTester tester) =>
      tester.widget<BottomNavigationBar>(find.byType(BottomNavigationBar));

  int? currentPage(WidgetTester tester) =>
      tester.widget<PageView>(find.byType(PageView)).controller?.page?.round();

  group('bottom nav bar', () {
    testWidgets('shows Session, Friends, Profile in that order with Session highlighted initially',
        (tester) async {
      await pumpShell(tester);

      final nav = bottomNav(tester);
      expect(nav.items.map((i) => i.label), ['Session', 'Friends', 'Profile']);
      expect(nav.currentIndex, 0);
      expect(find.text('Team'), findsNothing);
    });
  });

  group('tap navigation', () {
    testWidgets('tapping the Friends tab switches the page and updates the highlight',
        (tester) async {
      await pumpShell(tester);

      await tester.tap(find.byKey(const Key('friendsTabIcon')));
      await tester.pumpAndSettle();

      expect(bottomNav(tester).currentIndex, 1);
      expect(currentPage(tester), 1);
      expect(find.text('Friends'), findsWidgets);
    });

    testWidgets('tapping the Profile tab switches the page and updates the highlight',
        (tester) async {
      await pumpShell(tester);

      await tester.tap(find.byKey(const Key('profileTabIcon')));
      await tester.pumpAndSettle();

      expect(bottomNav(tester).currentIndex, 2);
      expect(currentPage(tester), 2);
      expect(find.text('Profile'), findsWidgets);
    });

    testWidgets('tapping back to Session returns to page 0 and re-highlights it', (tester) async {
      await pumpShell(tester);

      await tester.tap(find.byKey(const Key('profileTabIcon')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('sessionTabIcon')));
      await tester.pumpAndSettle();

      expect(bottomNav(tester).currentIndex, 0);
      expect(currentPage(tester), 0);
    });
  });

  group('swipe navigation', () {
    testWidgets('swiping left moves to the adjacent Friends tab and updates the highlight',
        (tester) async {
      await pumpShell(tester);

      await tester.drag(find.byType(PageView), const Offset(-600, 0));
      await tester.pumpAndSettle();

      expect(currentPage(tester), 1);
      expect(bottomNav(tester).currentIndex, 1);
    });

    testWidgets('swiping right from Friends moves back to Session and updates the highlight',
        (tester) async {
      await pumpShell(tester);
      await tester.tap(find.byKey(const Key('friendsTabIcon')));
      await tester.pumpAndSettle();

      await tester.drag(find.byType(PageView), const Offset(600, 0));
      await tester.pumpAndSettle();

      expect(currentPage(tester), 0);
      expect(bottomNav(tester).currentIndex, 0);
    });
  });

  testWidgets('the Session tab still hosts its gear icon opening Settings', (tester) async {
    var tapped = false;
    await pumpShell(tester, onSettingsTap: () async => tapped = true);

    await tester.tap(find.byKey(const Key('settingsButton')));
    await tester.pump();

    expect(tapped, isTrue);
  });

  testWidgets(
      'the Session screen keeps hosting the same mic controller unchanged across tab '
      'switches (not disposed/recreated)', (tester) async {
    await pumpShell(tester);
    expect(controller.startCallCount, 1);

    controller.emitShotCount(3);
    await tester.pump();
    await tester.pump();
    expect(tester.widget<Text>(find.byKey(const Key('sessionShotCountText'))).data, '3');

    await tester.tap(find.byKey(const Key('friendsTabIcon')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('profileTabIcon')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sessionTabIcon')));
    await tester.pumpAndSettle();

    expect(controller.startCallCount, 1, reason: 'no new start() call means no new controller/state');
    expect(controller.stopped, isFalse, reason: 'switching tabs must not stop the mic capture');
    expect(tester.widget<Text>(find.byKey(const Key('sessionShotCountText'))).data, '3',
        reason: 'the session dial state survived the tab switches');
  });
}
