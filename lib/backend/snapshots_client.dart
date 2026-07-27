import 'snapshot_models.dart';

/// The InsForge `snapshots` REST surface this app depends on, abstracted so
/// the UI/state layer never imports `http` directly and tests can fake it.
abstract class SnapshotsClient {
  /// Inputs: the caller's access token.
  /// Outputs: every `snapshots` row visible to the caller under RLS (self
  /// plus accepted friends); unranked, ranking is the caller's job.
  Future<List<Snapshot>> fetchLeaderboard({required String accessToken});

  /// Inputs: the caller's own user id/access token and the fields to publish.
  /// Outputs: none; upserts the caller's own `snapshots` row.
  Future<void> upsertSnapshot({
    required String accessToken,
    required String userId,
    String? displayName,
    String? avatarId,
    required double barDownRate,
    required int barDownCount,
  });
}

/// Any failure talking to the InsForge `snapshots` API.
class SnapshotsException implements Exception {
  const SnapshotsException(this.message);

  final String message;

  @override
  String toString() => 'SnapshotsException: $message';
}
