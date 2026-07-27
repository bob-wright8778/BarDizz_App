import 'package:flutter/material.dart';

import '../backend/auth_controller.dart';
import '../backend/challenge_client.dart';
import '../backend/friends_client.dart';
import '../backend/snapshots_client.dart';
import 'friends_screen.dart';
import 'profile_screen.dart';

/// Persistent bottom nav wrapping Session/Friends/Profile as swipeable pages,
/// kept in sync between tab taps and swipes. Hosts the caller-built
/// [sessionScreen] as tab 0 unchanged, so its mic controller is never
/// recreated by the shell. [authController]/[friendsClient]/[snapshotsClient]
/// are only ever read by the Friends/Profile tabs -- the session tab stays
/// free of any auth import. The Friends tab is told whether it's the current
/// tab so its leaderboard poll only runs while foregrounded.
class NavShell extends StatefulWidget {
  const NavShell({
    super.key,
    required this.sessionScreen,
    required this.authController,
    required this.friendsClient,
    required this.snapshotsClient,
    required this.challengeClient,
  });

  final Widget sessionScreen;
  final AuthController authController;
  final FriendsClient friendsClient;
  final SnapshotsClient snapshotsClient;
  final ChallengeClient challengeClient;

  @override
  State<NavShell> createState() => _NavShellState();
}

class _NavShellState extends State<NavShell> {
  final PageController _pageController = PageController();
  int _currentIndex = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onTabTapped(int index) {
    setState(() => _currentIndex = index);
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
    );
  }

  void _onPageChanged(int index) => setState(() => _currentIndex = index);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PageView(
        controller: _pageController,
        onPageChanged: _onPageChanged,
        children: [
          _KeepAlivePage(child: widget.sessionScreen),
          _KeepAlivePage(
            child: FriendsScreen(
              authController: widget.authController,
              friendsClient: widget.friendsClient,
              snapshotsClient: widget.snapshotsClient,
              challengeClient: widget.challengeClient,
              isActive: _currentIndex == 1,
            ),
          ),
          _KeepAlivePage(
            child: ProfileScreen(authController: widget.authController, snapshotsClient: widget.snapshotsClient),
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: _onTabTapped,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.sports_hockey, key: Key('sessionTabIcon')),
            label: 'Session',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.people, key: Key('friendsTabIcon')),
            label: 'Friends',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person, key: Key('profileTabIcon')),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

/// Keeps a PageView child's State alive once scrolled out of the cache
/// extent (e.g. jumping Session -> Profile -> Session), so tab switches never
/// tear down and recreate the session screen -- and its mic controller --
/// mid-session.
class _KeepAlivePage extends StatefulWidget {
  const _KeepAlivePage({required this.child});

  final Widget child;

  @override
  State<_KeepAlivePage> createState() => _KeepAlivePageState();
}

class _KeepAlivePageState extends State<_KeepAlivePage> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
