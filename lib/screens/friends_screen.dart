import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../backend/auth_controller.dart';
import '../backend/avatars.dart';
import '../backend/challenge_client.dart';
import '../backend/friends_client.dart';
import '../backend/friends_controller.dart';
import '../backend/friends_models.dart';
import '../backend/leaderboard_controller.dart';
import '../backend/snapshot_sync_controller.dart';
import '../backend/snapshots_client.dart';
import '../theme/design_tokens.dart';
import 'profile_setup_screen.dart';
import 'sign_in_gate.dart';

/// Cheap client-side sanity check before a challenge round-trip; the edge
/// function is the authority (returns `invalid_email` for anything it rejects).
final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

bool _looksLikeEmail(String value) => _emailPattern.hasMatch(value);

/// Friends tab: signed-out users see the sign-in gate, signed-in users with
/// an incomplete profile see profile setup, and everyone else sees friend
/// management (add by email, accept/decline requests) plus a ranked
/// leaderboard of the user + accepted friends. [isActive] gates the
/// leaderboard's ~30s poll -- it should be true only while this tab is the
/// foregrounded one (threaded down from `NavShell`'s selected tab).
class FriendsScreen extends StatefulWidget {
  const FriendsScreen({
    super.key,
    required this.authController,
    required this.friendsClient,
    required this.snapshotsClient,
    required this.challengeClient,
    this.isActive = true,
  });

  final AuthController authController;
  final FriendsClient friendsClient;
  final SnapshotsClient snapshotsClient;
  final ChallengeClient challengeClient;
  final bool isActive;

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  FriendsController? _friendsController;
  LeaderboardController? _leaderboardController;
  SnapshotSyncController? _snapshotSyncController;

  /// Outputs: the [FriendsController] for the current session, creating (and
  /// kicking off the first load for) one exactly once per sign-in.
  FriendsController _friendsControllerFor(AuthController auth) {
    final existing = _friendsController;
    if (existing != null) return existing;
    final created = FriendsController(
      client: widget.friendsClient,
      myUserId: auth.user!.id,
      accessToken: auth.accessToken!,
    );
    _friendsController = created;
    created.load();
    return created;
  }

  /// Outputs: the [LeaderboardController] for the current session, created
  /// exactly once per sign-in; [_FriendsContent] drives its first fetch.
  LeaderboardController _leaderboardControllerFor(AuthController auth) {
    return _leaderboardController ??= LeaderboardController(client: widget.snapshotsClient, myUserId: auth.user!.id);
  }

  SnapshotSyncController _snapshotSyncControllerFor() {
    return _snapshotSyncController ??= SnapshotSyncController(client: widget.snapshotsClient);
  }

  /// Best-effort publish after a profile save completes (first-time setup or
  /// a later edit) -- covers AC-F6.
  Future<void> _syncAfterProfileSave() => _snapshotSyncControllerFor().syncFromAuth(widget.authController);

  @override
  void dispose() {
    _friendsController?.dispose();
    _leaderboardController?.dispose();
    super.dispose();
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
                return _FriendsContent(
                  auth: widget.authController,
                  friendsController: _friendsControllerFor(widget.authController),
                  leaderboardController: _leaderboardControllerFor(widget.authController),
                  snapshotSyncController: _snapshotSyncControllerFor(),
                  challengeClient: widget.challengeClient,
                  isActive: widget.isActive,
                );
            }
          },
        ),
      ),
    );
  }
}

class _FriendsContent extends StatefulWidget {
  const _FriendsContent({
    required this.auth,
    required this.friendsController,
    required this.leaderboardController,
    required this.snapshotSyncController,
    required this.challengeClient,
    required this.isActive,
  });

  final AuthController auth;
  final FriendsController friendsController;
  final LeaderboardController leaderboardController;
  final SnapshotSyncController snapshotSyncController;
  final ChallengeClient challengeClient;
  final bool isActive;

  @override
  State<_FriendsContent> createState() => _FriendsContentState();
}

class _FriendsContentState extends State<_FriendsContent> with WidgetsBindingObserver {
  final _emailController = TextEditingController();
  bool _submitting = false;
  String? _statusMessage;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.friendsController.addListener(_onFriendsChanged);
    _refreshLeaderboard(runSync: true);
    _updatePolling();
  }

  /// Maps the current accepted friends into the leaderboard so any who have
  /// not published a snapshot yet still appear (with "--"), without a refetch.
  void _onFriendsChanged() {
    widget.leaderboardController.updateFriends(_acceptedFriendRecords());
  }

  List<LeaderboardFriend> _acceptedFriendRecords() => [
        for (final f in widget.friendsController.friends)
          (userId: f.otherUserId, displayName: f.displayName, avatarId: f.avatarId),
      ];

  @override
  void didUpdateWidget(covariant _FriendsContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      _refreshLeaderboard(runSync: true);
    }
    _updatePolling();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && widget.isActive) {
      _refreshLeaderboard(runSync: true);
    }
    _updatePolling();
  }

  /// Outputs: whether the host app is in the foreground, treating an unknown
  /// (null, e.g. before the first frame) lifecycle state as foregrounded.
  bool get _appIsForegrounded {
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    return lifecycle == null || lifecycle == AppLifecycleState.resumed;
  }

  /// Starts/stops the ~30s poll so it only ever runs while this tab is both
  /// the active one and the app is foregrounded.
  void _updatePolling() {
    final shouldPoll = widget.isActive && _appIsForegrounded;
    if (shouldPoll && _pollTimer == null) {
      _pollTimer = Timer.periodic(const Duration(seconds: 30), (_) => _refreshLeaderboard(runSync: false));
    } else if (!shouldPoll && _pollTimer != null) {
      _pollTimer!.cancel();
      _pollTimer = null;
    }
  }

  /// Inputs: whether to also attempt a best-effort publish first.
  /// Outputs: none; refreshes the leaderboard read side. A no-op if not
  /// actually signed in yet (auth/token not populated).
  Future<void> _refreshLeaderboard({required bool runSync}) async {
    final accessToken = widget.auth.accessToken;
    final userId = widget.auth.user?.id;
    if (accessToken == null || userId == null) return;
    if (runSync) {
      unawaited(widget.snapshotSyncController.sync(
        userId: userId,
        accessToken: accessToken,
        displayName: widget.auth.profile?.name,
        avatarId: widget.auth.profile?.avatarId,
      ));
    }
    await widget.leaderboardController.load(
      accessToken: accessToken,
      myDisplayName: widget.auth.profile?.name,
      myAvatarId: widget.auth.profile?.avatarId,
      acceptedFriends: _acceptedFriendRecords(),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.friendsController.removeListener(_onFriendsChanged);
    _pollTimer?.cancel();
    _emailController.dispose();
    super.dispose();
  }

  String _messageFor(String status) {
    switch (status) {
      case 'requested':
        return 'Friend request sent.';
      case 'self':
        return "You can't add yourself.";
      case 'duplicate':
        return "You're already connected (or a request is pending).";
      case 'invalid_email':
        return 'Enter a valid email.';
      case 'not_a_user':
        return "That email isn't a BarDizz user yet.";
      default:
        return 'Something went wrong. Try again.';
    }
  }

  Future<void> _submitAdd() async {
    final email = _emailController.text.trim();
    setState(() {
      _submitting = true;
      _statusMessage = null;
    });
    try {
      final status = await widget.friendsController.addByEmail(email);
      if (!mounted) return;
      setState(() => _statusMessage = _messageFor(status));
      if (status == 'requested') _emailController.clear();
      if (status == 'not_a_user') _offerChallengeInvite(email);
    } catch (_) {
      if (mounted) setState(() => _statusMessage = 'Something went wrong. Try again.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// Sends a challenge email server-side. Guards an empty/malformed address and
  /// a self-challenge locally (no round-trip); everything else -- including the
  /// existing-vs-non-user branch -- is decided by the edge function and mapped
  /// to copy from its returned outcome. [email] defaults to the shared field so
  /// the "not a user" invite dialog can pass the address it already has.
  Future<void> _submitChallenge({String? email}) async {
    final target = (email ?? _emailController.text).trim();
    if (!_looksLikeEmail(target)) {
      setState(() => _statusMessage = _challengeMessageFor(ChallengeOutcome.invalidEmail));
      return;
    }
    if (_isOwnEmail(target)) {
      setState(() => _statusMessage = _challengeMessageFor(ChallengeOutcome.selfChallenge));
      return;
    }
    setState(() {
      _submitting = true;
      _statusMessage = null;
    });
    try {
      final outcome = await widget.challengeClient.challenge(
        accessToken: widget.auth.accessToken!,
        targetEmail: target,
      );
      if (!mounted) return;
      setState(() => _statusMessage = _challengeMessageFor(outcome));
      if (outcome == ChallengeOutcome.existingUser || outcome == ChallengeOutcome.invited) {
        _emailController.clear();
      }
    } catch (_) {
      if (mounted) setState(() => _statusMessage = _challengeMessageFor(ChallengeOutcome.error));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  bool _isOwnEmail(String email) {
    final own = widget.auth.user?.email;
    return own != null && own.trim().toLowerCase() == email.toLowerCase();
  }

  String _challengeMessageFor(ChallengeOutcome outcome) {
    switch (outcome) {
      case ChallengeOutcome.existingUser:
        return "Challenge sent -- they'll get your request in the app.";
      case ChallengeOutcome.invited:
        return "Invite sent -- they'll be added once they join BarDizz.";
      case ChallengeOutcome.selfChallenge:
        return "You can't challenge yourself.";
      case ChallengeOutcome.invalidEmail:
        return 'Enter a valid email.';
      case ChallengeOutcome.error:
        return 'Couldn\'t send the challenge. Try again.';
    }
  }

  void _offerChallengeInvite(String email) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text("They're not on BarDizz yet"),
        content: Text('Want to invite $email to a challenge instead?'),
        actions: [
          TextButton(
            key: const Key('dismissChallengeInviteButton'),
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Not now'),
          ),
          ElevatedButton(
            key: const Key('inviteChallengeButton'),
            onPressed: () {
              Navigator.of(dialogContext).pop();
              _submitChallenge(email: email);
            },
            child: const Text('Invite them'),
          ),
        ],
      ),
    );
  }

  Future<void> _removeFriend(String linkId) async {
    await widget.friendsController.remove(linkId);
    await _refreshLeaderboard(runSync: false);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([widget.friendsController, widget.leaderboardController]),
      builder: (context, _) {
        final friendsController = widget.friendsController;
        final leaderboardController = widget.leaderboardController;
        return RefreshIndicator(
          key: const Key('leaderboardRefreshIndicator'),
          onRefresh: () => _refreshLeaderboard(runSync: true),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Friends', style: AppTypography.h2),
                const SizedBox(height: AppSpacing.lg),
                TextField(
                  key: const Key('addFriendEmailField'),
                  controller: _emailController,
                  decoration: const InputDecoration(labelText: "Friend's email"),
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        key: const Key('addFriendButton'),
                        onPressed: _submitting ? null : _submitAdd,
                        child: const Text('Add friend'),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: OutlinedButton(
                        key: const Key('challengeFriendButton'),
                        onPressed: _submitting ? null : () => _submitChallenge(),
                        child: const Text('Challenge'),
                      ),
                    ),
                  ],
                ),
                if (_statusMessage != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    _statusMessage!,
                    key: const Key('addFriendStatusText'),
                    style: AppTypography.body,
                  ),
                ],
                const SizedBox(height: AppSpacing.xl),
                if (friendsController.loading)
                  const Center(child: CircularProgressIndicator(key: Key('friendsLoadingIndicator'))),
                if (friendsController.errorMessage != null)
                  Text(
                    friendsController.errorMessage!,
                    key: const Key('friendsErrorText'),
                    style: AppTypography.errorText,
                  ),
                _FriendSection(
                  title: 'Incoming requests',
                  emptyText: 'No incoming requests',
                  items: friendsController.incoming,
                  actionsBuilder: (item) => [
                    IconButton(
                      key: Key('acceptButton_${item.link.id}'),
                      icon: const Icon(Icons.check),
                      onPressed: () => friendsController.accept(item.link.id),
                    ),
                    IconButton(
                      key: Key('declineButton_${item.link.id}'),
                      icon: const Icon(Icons.close),
                      onPressed: () => friendsController.decline(item.link.id),
                    ),
                  ],
                ),
                _FriendSection(
                  title: 'Outgoing requests',
                  emptyText: 'No outgoing requests',
                  items: friendsController.outgoing,
                  actionsBuilder: (item) => const [],
                ),
                const SizedBox(height: AppSpacing.lg),
                _LeaderboardSection(
                  friends: friendsController.friends,
                  entries: leaderboardController.entries,
                  loading: leaderboardController.loading,
                  offline: leaderboardController.offline,
                  lastUpdated: leaderboardController.lastUpdated,
                  onRemoveFriend: _removeFriend,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// One labeled block of the Friends tab (incoming/outgoing), each row
/// showing the other party's avatar + display name plus caller-supplied
/// per-row actions. Never renders an email.
class _FriendSection extends StatelessWidget {
  const _FriendSection({
    required this.title,
    required this.emptyText,
    required this.items,
    required this.actionsBuilder,
  });

  final String title;
  final String emptyText;
  final List<FriendListItem> items;
  final List<Widget> Function(FriendListItem item) actionsBuilder;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: AppTypography.label),
          const SizedBox(height: AppSpacing.sm),
          if (items.isEmpty)
            Text(emptyText, style: AppTypography.caption)
          else
            for (final item in items)
              Padding(
                key: Key('friendRow_${item.link.id}'),
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                child: Row(
                  children: [
                    SizedBox(
                      width: 40,
                      height: 40,
                      child: item.avatarId != null
                          ? SvgPicture.asset(avatarAssetPath(item.avatarId!), key: Key('friendAvatar_${item.link.id}'))
                          : null,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(item.displayName ?? '', key: Key('friendName_${item.link.id}')),
                    ),
                    ...actionsBuilder(item),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

/// Ranked leaderboard of the user + accepted friends: self always appears
/// (highlighted, suffixed "(You)"), each row shows avatar/name/rate/count
/// ("--" when no recorded high score), an offline/last-updated indicator
/// replaces an error when the last fetch failed, and a prompt to add a
/// friend shows whenever the user has no accepted friends yet.
class _LeaderboardSection extends StatelessWidget {
  const _LeaderboardSection({
    required this.friends,
    required this.entries,
    required this.loading,
    required this.offline,
    required this.lastUpdated,
    required this.onRemoveFriend,
  });

  final List<FriendListItem> friends;
  final List<LeaderboardEntry> entries;
  final bool loading;
  final bool offline;
  final DateTime? lastUpdated;
  final void Function(String linkId) onRemoveFriend;

  String? _linkIdFor(String userId) {
    for (final friend in friends) {
      if (friend.otherUserId == userId) return friend.link.id;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Leaderboard', style: AppTypography.label),
        const SizedBox(height: AppSpacing.sm),
        if (offline) ...[
          Text(
            lastUpdated == null
                ? 'Offline'
                : 'Offline · last updated ${formatRelativeTime(lastUpdated!, DateTime.now())}',
            key: const Key('leaderboardOfflineIndicator'),
            style: AppTypography.caption,
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        if (loading && entries.isEmpty)
          const Center(child: CircularProgressIndicator(key: Key('leaderboardLoadingIndicator'))),
        if (friends.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Text(
              'No friends yet — add one above to start a leaderboard.',
              key: const Key('leaderboardEmptyFriendsPrompt'),
              style: AppTypography.caption,
            ),
          ),
        for (final entry in entries) _LeaderboardRow(entry: entry, linkId: _linkIdFor(entry.userId), onRemove: onRemoveFriend),
      ],
    );
  }
}

class _LeaderboardRow extends StatelessWidget {
  const _LeaderboardRow({required this.entry, required this.linkId, required this.onRemove});

  final LeaderboardEntry entry;
  final String? linkId;
  final void Function(String linkId) onRemove;

  @override
  Widget build(BuildContext context) {
    final rateText = entry.barDownRate == null ? '—' : '${(entry.barDownRate! * 100).round()}%';
    final countText = entry.barDownCount == null ? '—' : '${entry.barDownCount}';
    return Container(
      key: Key('leaderboardRow_${entry.userId}'),
      margin: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
      decoration: entry.isSelf
          ? BoxDecoration(
              color: AppColors.iceBluePrimary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            )
          : null,
      child: Row(
        children: [
          SizedBox(
            width: 40,
            height: 40,
            child: entry.avatarId != null
                ? SvgPicture.asset(avatarAssetPath(entry.avatarId!), key: Key('leaderboardAvatar_${entry.userId}'))
                : null,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              entry.isSelf ? '${entry.displayName ?? ''} (You)' : entry.displayName ?? '',
              key: Key('leaderboardName_${entry.userId}'),
            ),
          ),
          Text(rateText, key: Key('leaderboardRate_${entry.userId}')),
          const SizedBox(width: AppSpacing.sm),
          Text(countText, key: Key('leaderboardCount_${entry.userId}')),
          if (!entry.isSelf && linkId != null)
            IconButton(
              key: Key('removeButton_$linkId'),
              icon: const Icon(Icons.person_remove),
              onPressed: () => onRemove(linkId!),
            ),
        ],
      ),
    );
  }
}
