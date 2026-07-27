import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../backend/auth_controller.dart';
import '../backend/avatars.dart';
import '../backend/snapshot_sync_controller.dart';
import '../backend/snapshots_client.dart';
import '../scoreboard/high_score_store.dart';
import '../theme/design_tokens.dart';
import 'profile_setup_screen.dart';
import 'sign_in_gate.dart';

/// Profile tab: same sign-in/profile-setup gating as Friends, then shows the
/// user's avatar, display name, and local high-score snapshot, with actions
/// to edit the profile or sign out. Never displays the user's email. Editing
/// the profile also best-effort publishes the updated snapshot (AC-F6).
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    required this.authController,
    required this.snapshotsClient,
    this.highScoreStore = const HighScoreStore(),
  });

  final AuthController authController;
  final SnapshotsClient snapshotsClient;
  final HighScoreStore highScoreStore;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  HighScoreSession? _highScore;
  bool _editing = false;
  late final SnapshotSyncController _snapshotSyncController =
      SnapshotSyncController(client: widget.snapshotsClient, highScoreStore: widget.highScoreStore);

  @override
  void initState() {
    super.initState();
    _loadHighScore();
  }

  Future<void> _syncAfterProfileSave() => _snapshotSyncController.syncFromAuth(widget.authController);

  Future<void> _loadHighScore() async {
    final loaded = await widget.highScoreStore.load();
    if (mounted) setState(() => _highScore = loaded);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: AnimatedBuilder(
          animation: widget.authController,
          builder: (context, _) {
            switch (widget.authController.status) {
              case AuthStatus.restoring:
                return const Center(
                  child: CircularProgressIndicator(key: Key('authRestoringIndicator')),
                );
              case AuthStatus.signedOut:
              case AuthStatus.authenticating:
                return Center(child: SignInGate(controller: widget.authController));
              case AuthStatus.needsProfileSetup:
                return ProfileSetupScreen(controller: widget.authController, onSaved: _syncAfterProfileSave);
              case AuthStatus.signedIn:
                return _buildProfile();
            }
          },
        ),
      ),
    );
  }

  Widget _buildProfile() {
    if (_editing) {
      final profile = widget.authController.profile;
      return ProfileSetupScreen(
        controller: widget.authController,
        initialDisplayName: profile?.name ?? '',
        initialAvatarId: profile?.avatarId,
        submitLabel: 'Update profile',
        onSaved: () {
          setState(() => _editing = false);
          _syncAfterProfileSave();
        },
      );
    }

    final profile = widget.authController.profile;
    final avatarId = profile?.avatarId;
    final highScore = _highScore;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (avatarId != null)
            Center(
              child: SizedBox(
                width: 96,
                height: 96,
                child: SvgPicture.asset(avatarAssetPath(avatarId), key: const Key('profileAvatarImage')),
              ),
            ),
          const SizedBox(height: AppSpacing.lg),
          Center(
            child: Text(
              profile?.name ?? '',
              key: const Key('profileDisplayName'),
              style: AppTypography.h2,
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          if (highScore != null)
            Text(
              'High score: ${highScore.barDowns}/${highScore.shots} bar downs',
              key: const Key('profileHighScoreText'),
              style: AppTypography.body,
              textAlign: TextAlign.center,
            ),
          const SizedBox(height: AppSpacing.xl),
          ElevatedButton(
            key: const Key('editProfileButton'),
            onPressed: () => setState(() => _editing = true),
            child: const Text('Edit profile'),
          ),
          const SizedBox(height: AppSpacing.md),
          OutlinedButton(
            key: const Key('signOutButton'),
            onPressed: widget.authController.signOut,
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
  }
}
