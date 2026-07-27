import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'snapshot_models.dart';
import 'snapshots_client.dart';

const _cacheKey = 'leaderboard_cache_snapshots';
const _cacheFetchedAtKey = 'leaderboard_cache_fetched_at';

/// One leaderboard row: a snapshot enriched with whether it's the signed-in
/// user's own row. Null rate/count means no recorded high score ("--").
class LeaderboardEntry {
  const LeaderboardEntry({
    required this.userId,
    this.displayName,
    this.avatarId,
    this.barDownRate,
    this.barDownCount,
    required this.isSelf,
  });

  final String userId;
  final String? displayName;
  final String? avatarId;
  final double? barDownRate;
  final int? barDownCount;
  final bool isSelf;
}

/// An accepted friend's identity fields, so a friend who has not published a
/// snapshot yet can still appear on the leaderboard (with "--").
typedef LeaderboardFriend = ({String userId, String? displayName, String? avatarId});

/// Builds the ranked leaderboard from fetched snapshots + the accepted friends.
/// Inputs: RLS-scoped `snapshots` rows, the signed-in user's id/profile fields,
/// and the accepted-friends list.
/// Outputs: entries ranked by bar-down rate desc, ties by count desc (same
/// ordering as [HighScoreSession.bestOf]); self and every accepted friend
/// always appear, with "--" until they publish.
List<LeaderboardEntry> rankLeaderboard({
  required List<Snapshot> snapshots,
  required String myUserId,
  String? myDisplayName,
  String? myAvatarId,
  List<LeaderboardFriend> acceptedFriends = const [],
}) {
  final byUserId = <String, LeaderboardEntry>{};
  for (final s in snapshots) {
    byUserId[s.userId] = LeaderboardEntry(
      userId: s.userId,
      displayName: s.displayName,
      avatarId: s.avatarId,
      barDownRate: s.barDownRate,
      barDownCount: s.barDownCount,
      isSelf: s.userId == myUserId,
    );
  }
  for (final f in acceptedFriends) {
    byUserId.putIfAbsent(
      f.userId,
      () => LeaderboardEntry(userId: f.userId, displayName: f.displayName, avatarId: f.avatarId, isSelf: false),
    );
  }
  byUserId.putIfAbsent(
    myUserId,
    () => LeaderboardEntry(userId: myUserId, displayName: myDisplayName, avatarId: myAvatarId, isSelf: true),
  );
  final entries = byUserId.values.toList();
  entries.sort((a, b) {
    final rateCompare = (b.barDownRate ?? -1).compareTo(a.barDownRate ?? -1);
    if (rateCompare != 0) return rateCompare;
    return (b.barDownCount ?? -1).compareTo(a.barDownCount ?? -1);
  });
  return entries;
}

/// Inputs: a past timestamp and the current time.
/// Outputs: a short relative-time label for the offline indicator.
String formatRelativeTime(DateTime from, DateTime now) {
  final diff = now.difference(from);
  if (diff.inSeconds < 60) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  return '${diff.inDays}d ago';
}

/// Owns the leaderboard read path: fetch, client-side ranking, and an
/// offline fallback to the last successfully-fetched snapshots (cached via
/// [SharedPreferences]) with a last-updated timestamp. Never publishes --
/// that's [SnapshotSyncController]'s job.
class LeaderboardController extends ChangeNotifier {
  LeaderboardController({required this.client, required this.myUserId});

  final SnapshotsClient client;
  final String myUserId;

  bool loading = false;
  bool offline = false;
  DateTime? lastUpdated;
  List<LeaderboardEntry> entries = [];

  List<Snapshot> _snapshots = const [];
  List<LeaderboardFriend> _acceptedFriends = const [];
  String? _myDisplayName;
  String? _myAvatarId;

  /// Inputs: the caller's access token, current local profile fields, and the
  /// accepted friends list (so not-yet-published friends still rank in).
  /// Outputs: none; refreshes [entries]. On a failed fetch, falls back to the
  /// last cached snapshots and sets [offline] instead of surfacing an error.
  Future<void> load({
    required String accessToken,
    String? myDisplayName,
    String? myAvatarId,
    List<LeaderboardFriend> acceptedFriends = const [],
  }) async {
    loading = true;
    notifyListeners();

    _myDisplayName = myDisplayName;
    _myAvatarId = myAvatarId;
    _acceptedFriends = acceptedFriends;

    try {
      _snapshots = await client.fetchLeaderboard(accessToken: accessToken);
      offline = false;
      lastUpdated = DateTime.now();
      await _saveCache(_snapshots, lastUpdated!);
    } catch (_) {
      final cached = await _loadCache();
      _snapshots = cached.snapshots;
      offline = true;
      lastUpdated = cached.fetchedAt;
    }

    _rerank();
    loading = false;
    notifyListeners();
  }

  /// Inputs: the current accepted-friends list. Re-ranks against the
  /// last-fetched snapshots without re-fetching, so a friend who has not
  /// published yet appears (with "--") as soon as the friends list loads.
  void updateFriends(List<LeaderboardFriend> acceptedFriends) {
    _acceptedFriends = acceptedFriends;
    _rerank();
    notifyListeners();
  }

  void _rerank() {
    entries = rankLeaderboard(
      snapshots: _snapshots,
      myUserId: myUserId,
      myDisplayName: _myDisplayName,
      myAvatarId: _myAvatarId,
      acceptedFriends: _acceptedFriends,
    );
  }

  Future<void> _saveCache(List<Snapshot> snapshots, DateTime fetchedAt) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cacheKey, jsonEncode([for (final s in snapshots) s.toJson()]));
    await prefs.setString(_cacheFetchedAtKey, fetchedAt.toIso8601String());
  }

  Future<({List<Snapshot> snapshots, DateTime? fetchedAt})> _loadCache() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_cacheKey);
    final fetchedAtRaw = prefs.getString(_cacheFetchedAtKey);
    final snapshots = raw == null
        ? const <Snapshot>[]
        : [for (final row in jsonDecode(raw) as List) Snapshot.fromJson(row as Map<String, dynamic>)];
    final fetchedAt = fetchedAtRaw == null ? null : DateTime.tryParse(fetchedAtRaw);
    return (snapshots: snapshots, fetchedAt: fetchedAt);
  }
}
