import 'dart:async';

import 'package:flutter/material.dart';

import 'audio/data_collection_controller.dart';
import 'audio/mic_level_controller.dart';
import 'backend/auth_controller.dart';
import 'backend/challenge_client.dart';
import 'backend/friends_client.dart';
import 'backend/insforge_auth_client.dart';
import 'backend/insforge_challenge_client.dart';
import 'backend/insforge_friends_client.dart';
import 'backend/insforge_snapshots_client.dart';
import 'backend/oauth_browser.dart';
import 'backend/secure_token_store.dart';
import 'backend/snapshot_sync_controller.dart';
import 'backend/snapshots_client.dart';
import 'screens/data_collection_screen.dart';
import 'screens/debug_meter_screen.dart';
import 'screens/nav_shell.dart';
import 'screens/session_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/video_calibration_screen.dart';
import 'settings/eww_always_bar_down_store.dart';
import 'settings/video_settings_store.dart';
import 'theme/app_theme.dart';
import 'video/video_shot_controller.dart';

void main() {
  runApp(const HockeyShotTrackerApp());
}

class HockeyShotTrackerApp extends StatelessWidget {
  const HockeyShotTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BarDizz',
      theme: AppTheme.dark,
      home: const AppHomeGate(),
    );
  }
}

/// Hosts the nav shell and the persistent camera+mic session controller
/// behind the session tab (settings/debug-meter navigation live here too).
class AppHomeGate extends StatefulWidget {
  const AppHomeGate({super.key});

  @override
  State<AppHomeGate> createState() => _AppHomeGateState();
}

class _AppHomeGateState extends State<AppHomeGate> with WidgetsBindingObserver {
  // Cached in memory (not re-read from SharedPreferences per audio chunk) so
  // the getters below stay synchronous; loaded once at startup and kept in
  // sync with Settings via _onEwwAlwaysBarDownChanged.
  bool _ewwAlwaysBarDown = ewwAlwaysBarDownDefault;
  bool _requireSound = requireSoundDefault;

  // Created once and reused across rebuilds (e.g. rotation), rather than
  // per-build, so a running session's controller is never swapped out from
  // under SessionScreen's stream subscription mid-session. Reads
  // _ewwAlwaysBarDown via a getter (not a fixed value) so toggling Settings
  // takes effect on the next classified window, no restart needed.
  // requireSound is read once per session start.
  late final LiveVideoShotController _sessionController = LiveVideoShotController(
    ewwAlwaysBarDown: _currentEwwAlwaysBarDown,
    requireSound: () => _requireSound,
  );

  // Owns Friends/Profile sign-in state for the whole app lifetime, restored
  // from a stored refresh token (if any) once at startup below. The Session
  // tab never reads this -- it stays free of any auth dependency.
  late final AuthController _authController = AuthController(
    client: InsforgeAuthClient(),
    browser: const FlutterWebAuthBrowser(),
    tokenStore: const FlutterSecureTokenStore(),
  );

  // Shared across the Friends tab's lifetime; FriendsScreen builds its own
  // FriendsController once signed in, using this client + the auth session.
  final FriendsClient _friendsClient = InsforgeFriendsClient();

  // Shared by the Friends leaderboard and both Friends/Profile's snapshot
  // publish-on-save hook.
  final SnapshotsClient _snapshotsClient = InsforgeSnapshotsClient();

  // Sends challenge-a-friend emails through the server-side edge function.
  final ChallengeClient _challengeClient = InsforgeChallengeClient();

  late final SnapshotSyncController _snapshotSyncController =
      SnapshotSyncController(client: _snapshotsClient);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadEwwAlwaysBarDown();
    _loadRequireSound();
    // Publish any pending high-score/profile change once a restored session is
    // known, so a new high score reaches the backend on the next app
    // foreground even if the user never opens the Friends tab (AC-F4).
    _authController.restore().then((_) => _publishSnapshotIfSignedIn());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _publishSnapshotIfSignedIn();
  }

  // Best-effort, non-blocking; a no-op when signed out. Never touches the
  // Session shot-tracking path.
  void _publishSnapshotIfSignedIn() {
    unawaited(_snapshotSyncController.syncFromAuth(_authController));
  }

  bool _currentEwwAlwaysBarDown() => _ewwAlwaysBarDown;

  Future<void> _loadEwwAlwaysBarDown() async {
    final loaded = await const EwwAlwaysBarDownStore().load();
    if (mounted) setState(() => _ewwAlwaysBarDown = loaded);
  }

  void _onEwwAlwaysBarDownChanged(bool value) {
    setState(() => _ewwAlwaysBarDown = value);
  }

  Future<void> _loadRequireSound() async {
    final loaded = await const VideoSettingsStore().loadRequireSound();
    if (mounted) setState(() => _requireSound = loaded);
  }

  void _openCalibration(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => VideoCalibrationScreen(feed: _sessionController)),
    );
  }

  Future<void> _openSettings(BuildContext context) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SettingsScreen(
          onDebugMeterTap: () => _openDebugMeter(context),
          onDataCollectionTap: () => _openDataCollectionMode(context),
          onEwwAlwaysBarDownChanged: _onEwwAlwaysBarDownChanged,
          onCalibrateTap: () => _openCalibration(context),
          onRequireSoundChanged: (v) => setState(() => _requireSound = v),
        ),
      ),
    );
  }

  void _openDebugMeter(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DebugMeterScreen(
          controller: LiveMicLevelController(ewwAlwaysBarDown: _currentEwwAlwaysBarDown),
        ),
      ),
    );
  }

  void _openDataCollectionMode(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DataCollectionScreen(controller: LiveDataCollectionController()),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return NavShell(
      sessionScreen: SessionScreen(
        controller: _sessionController,
        onSettingsTap: () => _openSettings(context),
        videoFeed: _sessionController,
        onCalibrateTap: () => _openCalibration(context),
      ),
      authController: _authController,
      friendsClient: _friendsClient,
      snapshotsClient: _snapshotsClient,
      challengeClient: _challengeClient,
    );
  }
}
