import 'package:hockey_shot_tracker/backend/snapshot_models.dart';
import 'package:hockey_shot_tracker/backend/snapshots_client.dart';

/// Scriptable [SnapshotsClient] fake: no network, ever. Every response/error
/// is set up by the test before use; every request is recorded for assertions.
class FakeSnapshotsClient implements SnapshotsClient {
  List<Snapshot> leaderboard = [];
  Object? fetchError;
  Object? upsertError;

  int fetchCallCount = 0;
  int upsertCallCount = 0;
  String? lastUpsertAccessToken;
  String? lastUpsertUserId;
  String? lastUpsertDisplayName;
  String? lastUpsertAvatarId;
  double? lastUpsertRate;
  int? lastUpsertCount;

  @override
  Future<List<Snapshot>> fetchLeaderboard({required String accessToken}) async {
    fetchCallCount++;
    final error = fetchError;
    if (error != null) throw error;
    return leaderboard;
  }

  @override
  Future<void> upsertSnapshot({
    required String accessToken,
    required String userId,
    String? displayName,
    String? avatarId,
    required double barDownRate,
    required int barDownCount,
  }) async {
    upsertCallCount++;
    lastUpsertAccessToken = accessToken;
    lastUpsertUserId = userId;
    lastUpsertDisplayName = displayName;
    lastUpsertAvatarId = avatarId;
    lastUpsertRate = barDownRate;
    lastUpsertCount = barDownCount;
    final error = upsertError;
    if (error != null) throw error;
    leaderboard = [
      for (final s in leaderboard) if (s.userId != userId) s,
      Snapshot(
        userId: userId,
        displayName: displayName,
        avatarId: avatarId,
        barDownRate: barDownRate,
        barDownCount: barDownCount,
      ),
    ];
  }
}
