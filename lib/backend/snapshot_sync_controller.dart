import 'package:shared_preferences/shared_preferences.dart';

import '../scoreboard/high_score_store.dart';
import 'auth_controller.dart';
import 'snapshots_client.dart';

const _lastPublishedKey = 'snapshot_last_published';

/// Inputs: the local high score/profile fields a publish would send.
/// Outputs: a stable string that is equal iff every input is equal.
String snapshotSignature({
  required double rate,
  required int count,
  String? displayName,
  String? avatarId,
}) =>
    '$rate|$count|${displayName ?? ''}|${avatarId ?? ''}';

/// Decouples publishing from the Session shot-tracking path: whenever [sync]
/// runs, it compares the current local high score plus profile against the
/// last-published signature and republishes only if something changed. This
/// single comparison covers a new high score, a profile edit, and offline
/// catch-up alike -- a non-high-score session never changes the local high
/// score, so it never triggers a publish.
class SnapshotSyncController {
  SnapshotSyncController({required this.client, this.highScoreStore = const HighScoreStore()});

  final SnapshotsClient client;
  final HighScoreStore highScoreStore;

  /// Inputs: the signed-in user's id/access token and current profile fields.
  /// Outputs: true if a publish happened this call. Never throws -- a failed
  /// write leaves the stored signature stale so the next call retries.
  Future<bool> sync({
    required String userId,
    required String accessToken,
    String? displayName,
    String? avatarId,
  }) async {
    final highScore = await highScoreStore.loadRecordedOrNull();
    if (highScore == null) return false;

    final signature = snapshotSignature(
      rate: highScore.rate,
      count: highScore.barDowns,
      displayName: displayName,
      avatarId: avatarId,
    );
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(_lastPublishedKey) == signature) return false;

    try {
      await client.upsertSnapshot(
        accessToken: accessToken,
        userId: userId,
        displayName: displayName,
        avatarId: avatarId,
        barDownRate: highScore.rate,
        barDownCount: highScore.barDowns,
      );
      await prefs.setString(_lastPublishedKey, signature);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Inputs: the signed-in [auth] state (id/token/profile).
  /// Outputs: true if a publish happened; a no-op returning false when not
  /// signed in. Convenience wrapper over [sync] for the profile-save callers.
  Future<bool> syncFromAuth(AuthController auth) {
    final userId = auth.user?.id;
    final accessToken = auth.accessToken;
    if (userId == null || accessToken == null) return Future.value(false);
    return sync(
      userId: userId,
      accessToken: accessToken,
      displayName: auth.profile?.name,
      avatarId: auth.profile?.avatarId,
    );
  }
}
