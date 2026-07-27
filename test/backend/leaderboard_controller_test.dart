import 'package:flutter_test/flutter_test.dart';
import 'package:hockey_shot_tracker/backend/leaderboard_controller.dart';
import 'package:hockey_shot_tracker/backend/snapshot_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_snapshots.dart';

const _me = Snapshot(userId: 'me', displayName: 'Bob', avatarId: 'avatar-01', barDownRate: 0.5, barDownCount: 5);
const _friendHigher =
    Snapshot(userId: 'f1', displayName: 'Alice', avatarId: 'avatar-02', barDownRate: 0.8, barDownCount: 4);
const _friendTiedRateLowerCount =
    Snapshot(userId: 'f2', displayName: 'Carl', avatarId: 'avatar-03', barDownRate: 0.5, barDownCount: 3);
const _friendTiedRateHigherCount =
    Snapshot(userId: 'f3', displayName: 'Dana', avatarId: 'avatar-04', barDownRate: 0.5, barDownCount: 9);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('rankLeaderboard', () {
    test('ranks by bar-down rate descending', () {
      final entries = rankLeaderboard(snapshots: [_me, _friendHigher], myUserId: 'me');

      expect(entries.map((e) => e.userId).toList(), ['f1', 'me']);
    });

    test('ties are broken by bar-down count descending (matches HighScoreSession.bestOf)', () {
      final entries = rankLeaderboard(
        snapshots: [_me, _friendTiedRateLowerCount, _friendTiedRateHigherCount],
        myUserId: 'me',
      );

      expect(entries.map((e) => e.userId).toList(), ['f3', 'me', 'f2']);
    });

    test('the self row is always present even if absent from the fetched snapshots', () {
      final entries = rankLeaderboard(
        snapshots: [_friendHigher],
        myUserId: 'me',
        myDisplayName: 'Bob',
        myAvatarId: 'avatar-01',
      );

      final self = entries.singleWhere((e) => e.isSelf);
      expect(self.userId, 'me');
      expect(self.displayName, 'Bob');
      expect(self.avatarId, 'avatar-01');
      expect(self.barDownRate, isNull, reason: 'no recorded high score shows as "--"');
      expect(self.barDownCount, isNull);
    });

    test('a synthesized no-score self row ranks below a real 0%-rate row', () {
      const zeroRateFriend =
          Snapshot(userId: 'f4', displayName: 'Zed', avatarId: 'avatar-05', barDownRate: 0, barDownCount: 0);
      final entries = rankLeaderboard(snapshots: [zeroRateFriend], myUserId: 'me', myDisplayName: 'Bob');

      expect(entries.map((e) => e.userId).toList(), ['f4', 'me']);
    });

    test('only one self entry exists when the fetched snapshots already include the caller', () {
      final entries = rankLeaderboard(snapshots: [_me, _friendHigher], myUserId: 'me');

      expect(entries.where((e) => e.isSelf), hasLength(1));
      expect(entries.singleWhere((e) => e.isSelf).barDownRate, 0.5);
    });

    test('an accepted friend with no published snapshot still appears, with "--", ranked last', () {
      final entries = rankLeaderboard(
        snapshots: [_me],
        myUserId: 'me',
        acceptedFriends: const [(userId: 'f9', displayName: 'Newbie', avatarId: 'avatar-07')],
      );

      final newbie = entries.singleWhere((e) => e.userId == 'f9');
      expect(newbie.displayName, 'Newbie');
      expect(newbie.avatarId, 'avatar-07');
      expect(newbie.barDownRate, isNull, reason: 'never published -> "--"');
      expect(newbie.barDownCount, isNull);
      expect(newbie.isSelf, isFalse);
      expect(entries.map((e) => e.userId).toList(), ['me', 'f9'], reason: 'no-score friend ranks below a scored self');
    });

    test('a published snapshot wins over the friend-list fallback for the same user (no duplicate row)', () {
      final entries = rankLeaderboard(
        snapshots: [_me, _friendHigher],
        myUserId: 'me',
        acceptedFriends: const [(userId: 'f1', displayName: 'stale-name', avatarId: 'avatar-99')],
      );

      expect(entries.where((e) => e.userId == 'f1'), hasLength(1));
      final f1 = entries.singleWhere((e) => e.userId == 'f1');
      expect(f1.displayName, 'Alice', reason: 'the published snapshot, not the friend-list fallback, is shown');
      expect(f1.barDownRate, 0.8);
    });
  });

  group('formatRelativeTime', () {
    final now = DateTime(2026, 7, 26, 12, 0, 0);

    test('under a minute reads "just now"', () {
      expect(formatRelativeTime(now.subtract(const Duration(seconds: 30)), now), 'just now');
    });

    test('minutes ago', () {
      expect(formatRelativeTime(now.subtract(const Duration(minutes: 5)), now), '5m ago');
    });

    test('hours ago', () {
      expect(formatRelativeTime(now.subtract(const Duration(hours: 3)), now), '3h ago');
    });

    test('days ago', () {
      expect(formatRelativeTime(now.subtract(const Duration(days: 2)), now), '2d ago');
    });
  });

  group('LeaderboardController.load', () {
    test('a successful fetch populates ranked entries and marks online', () async {
      final client = FakeSnapshotsClient()..leaderboard = [_me, _friendHigher];
      final controller = LeaderboardController(client: client, myUserId: 'me');

      await controller.load(accessToken: 'token');

      expect(controller.offline, isFalse);
      expect(controller.loading, isFalse);
      expect(controller.lastUpdated, isNotNull);
      expect(controller.entries.map((e) => e.userId).toList(), ['f1', 'me']);
    });

    test('a failed fetch with no prior cache falls back to just the self row and marks offline', () async {
      final client = FakeSnapshotsClient()..fetchError = Exception('network down');
      final controller = LeaderboardController(client: client, myUserId: 'me');

      await controller.load(accessToken: 'token', myDisplayName: 'Bob', myAvatarId: 'avatar-01');

      expect(controller.offline, isTrue);
      expect(controller.entries, isNotEmpty, reason: 'self must still appear, not an empty screen');
      expect(controller.entries.single.userId, 'me');
      expect(controller.lastUpdated, isNull);
    });

    test('a failed fetch after a prior success falls back to the cached snapshots and offline indicator',
        () async {
      final client = FakeSnapshotsClient()..leaderboard = [_me, _friendHigher];
      final controller = LeaderboardController(client: client, myUserId: 'me');
      await controller.load(accessToken: 'token');
      final firstFetchTime = controller.lastUpdated;

      client.fetchError = Exception('network down');
      await controller.load(accessToken: 'token');

      expect(controller.offline, isTrue);
      expect(controller.entries.map((e) => e.userId).toList(), ['f1', 'me'],
          reason: 'last-synced snapshots are shown, not an empty/error screen');
      expect(controller.lastUpdated, firstFetchTime, reason: 'shows when it was last actually fetched');
    });

    test('a successful fetch after an offline period clears the offline flag again', () async {
      final client = FakeSnapshotsClient()..fetchError = Exception('network down');
      final controller = LeaderboardController(client: client, myUserId: 'me');
      await controller.load(accessToken: 'token');
      expect(controller.offline, isTrue);

      client.fetchError = null;
      client.leaderboard = [_me];
      await controller.load(accessToken: 'token');

      expect(controller.offline, isFalse);
    });

    test('a fetch includes not-yet-published accepted friends passed to load', () async {
      final client = FakeSnapshotsClient()..leaderboard = [_me];
      final controller = LeaderboardController(client: client, myUserId: 'me');

      await controller.load(
        accessToken: 'token',
        acceptedFriends: const [(userId: 'f9', displayName: 'Newbie', avatarId: 'avatar-07')],
      );

      expect(controller.entries.map((e) => e.userId).toSet(), {'me', 'f9'});
    });

    test('updateFriends re-ranks against the last fetch without re-fetching', () async {
      final client = FakeSnapshotsClient()..leaderboard = [_me];
      final controller = LeaderboardController(client: client, myUserId: 'me');
      await controller.load(accessToken: 'token');
      expect(controller.entries.map((e) => e.userId).toList(), ['me']);
      final fetchesBefore = client.fetchCallCount;

      controller.updateFriends(const [(userId: 'f9', displayName: 'Newbie', avatarId: 'avatar-07')]);

      expect(controller.entries.map((e) => e.userId).toSet(), {'me', 'f9'});
      expect(client.fetchCallCount, fetchesBefore, reason: 'a friends-list change must not trigger a network fetch');
    });
  });
}
