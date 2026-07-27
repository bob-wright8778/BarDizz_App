import 'package:flutter_test/flutter_test.dart';
import 'package:hockey_shot_tracker/backend/insforge_snapshots_client.dart';
import 'package:hockey_shot_tracker/backend/snapshots_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('fetchLeaderboard', () {
    test('parses a bare JSON array of records', () async {
      final mock = MockClient((request) async {
        return http.Response(
          '[{"user_id":"me","display_name":"Bob","avatar_id":"avatar-01","bar_down_rate":0.5,"bar_down_count":5}]',
          200,
        );
      });
      final client = InsforgeSnapshotsClient(httpClient: mock);

      final result = await client.fetchLeaderboard(accessToken: 'token');

      expect(result, hasLength(1));
      expect(result.single.userId, 'me');
      expect(result.single.barDownRate, 0.5);
    });

    test('parses a {"records": [...]} wrapped shape', () async {
      final mock = MockClient((request) async {
        return http.Response(
          '{"records":[{"user_id":"me","bar_down_rate":0.2,"bar_down_count":1}]}',
          200,
        );
      });
      final client = InsforgeSnapshotsClient(httpClient: mock);

      final result = await client.fetchLeaderboard(accessToken: 'token');

      expect(result.single.userId, 'me');
    });

    test('throws SnapshotsException on a non-2xx response', () async {
      final mock = MockClient((request) async => http.Response('error', 500));
      final client = InsforgeSnapshotsClient(httpClient: mock);

      expect(() => client.fetchLeaderboard(accessToken: 'token'), throwsA(isA<SnapshotsException>()));
    });
  });

  group('upsertSnapshot', () {
    test('a PATCH that matches an existing row does not fall back to POST', () async {
      var postCalled = false;
      final mock = MockClient((request) async {
        if (request.method == 'PATCH') {
          return http.Response('[{"user_id":"me"}]', 200);
        }
        postCalled = true;
        return http.Response('{}', 201);
      });
      final client = InsforgeSnapshotsClient(httpClient: mock);

      await client.upsertSnapshot(
        accessToken: 'token',
        userId: 'me',
        displayName: 'Bob',
        avatarId: 'avatar-01',
        barDownRate: 0.5,
        barDownCount: 5,
      );

      expect(postCalled, isFalse);
    });

    test('a PATCH that matches no row (empty array) falls back to POST', () async {
      final requestMethods = <String>[];
      final mock = MockClient((request) async {
        requestMethods.add(request.method);
        if (request.method == 'PATCH') {
          return http.Response('[]', 200);
        }
        return http.Response('{"user_id":"me"}', 201);
      });
      final client = InsforgeSnapshotsClient(httpClient: mock);

      await client.upsertSnapshot(
        accessToken: 'token',
        userId: 'me',
        displayName: 'Bob',
        avatarId: 'avatar-01',
        barDownRate: 0.5,
        barDownCount: 5,
      );

      expect(requestMethods, ['PATCH', 'POST']);
    });

    test('throws SnapshotsException if both PATCH-empty and the POST fallback fail', () async {
      final mock = MockClient((request) async {
        if (request.method == 'PATCH') return http.Response('[]', 200);
        return http.Response('error', 500);
      });
      final client = InsforgeSnapshotsClient(httpClient: mock);

      expect(
        () => client.upsertSnapshot(
          accessToken: 'token',
          userId: 'me',
          barDownRate: 0.5,
          barDownCount: 5,
        ),
        throwsA(isA<SnapshotsException>()),
      );
    });

    test('a hard PATCH failure (non-2xx) also falls back to POST', () async {
      final requestMethods = <String>[];
      final mock = MockClient((request) async {
        requestMethods.add(request.method);
        if (request.method == 'PATCH') return http.Response('not found', 404);
        return http.Response('{}', 201);
      });
      final client = InsforgeSnapshotsClient(httpClient: mock);

      await client.upsertSnapshot(
        accessToken: 'token',
        userId: 'me',
        barDownRate: 0.5,
        barDownCount: 5,
      );

      expect(requestMethods, ['PATCH', 'POST']);
    });
  });
}
