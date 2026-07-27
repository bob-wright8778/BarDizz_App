import 'package:flutter_test/flutter_test.dart';
import 'package:hockey_shot_tracker/backend/auth_models.dart';
import 'package:hockey_shot_tracker/backend/friends_controller.dart';
import 'package:hockey_shot_tracker/backend/friends_models.dart';

import '../support/fake_friends.dart';

const _myId = 'me';
const _friendId = 'friend-1';
const _otherId = 'other-2';

FriendsController _controller(FakeFriendsClient client) =>
    FriendsController(client: client, myUserId: _myId, accessToken: 'token-1');

void main() {
  group('load', () {
    test('splits links into incoming, outgoing, and accepted friends', () async {
      final client = FakeFriendsClient()
        ..links = [
          const FriendLink(id: 'l1', requesterId: _otherId, addresseeId: _myId, status: FriendLinkStatus.pending),
          const FriendLink(id: 'l2', requesterId: _myId, addresseeId: _otherId, status: FriendLinkStatus.pending),
          const FriendLink(id: 'l3', requesterId: _myId, addresseeId: _friendId, status: FriendLinkStatus.accepted),
        ]
        ..profilesByUserId = {
          _otherId: const AuthProfile(name: 'Other', avatarId: 'avatar-02'),
          _friendId: const AuthProfile(name: 'Friend', avatarId: 'avatar-03'),
        };
      final controller = _controller(client);

      await controller.load();

      expect(controller.incoming, hasLength(1));
      expect(controller.incoming.single.link.id, 'l1');
      expect(controller.incoming.single.displayName, 'Other');
      expect(controller.outgoing, hasLength(1));
      expect(controller.outgoing.single.link.id, 'l2');
      expect(controller.friends, hasLength(1));
      expect(controller.friends.single.link.id, 'l3');
      expect(controller.friends.single.displayName, 'Friend');
      expect(controller.loading, isFalse);
      expect(controller.errorMessage, isNull);
    });

    test('an accepted link is a friend regardless of who requested it', () async {
      final client = FakeFriendsClient()
        ..links = [
          const FriendLink(id: 'l1', requesterId: _otherId, addresseeId: _myId, status: FriendLinkStatus.accepted),
        ];
      final controller = _controller(client);

      await controller.load();

      expect(controller.friends, hasLength(1));
      expect(controller.incoming, isEmpty);
      expect(controller.outgoing, isEmpty);
    });

    test('a failed load surfaces an error message instead of throwing', () async {
      final client = FakeFriendsClient()..listLinksError = Exception('network down');
      final controller = _controller(client);

      await controller.load();

      expect(controller.errorMessage, isNotNull);
      expect(controller.loading, isFalse);
    });
  });

  group('accept', () {
    test('flips the link to accepted and it now shows in friends, not incoming', () async {
      final client = FakeFriendsClient()
        ..links = [
          const FriendLink(id: 'l1', requesterId: _otherId, addresseeId: _myId, status: FriendLinkStatus.pending),
        ];
      final controller = _controller(client);
      await controller.load();
      expect(controller.incoming, hasLength(1));

      await controller.accept('l1');

      expect(client.lastAcceptedLinkId, 'l1');
      expect(controller.incoming, isEmpty);
      expect(controller.friends, hasLength(1));
    });

    test('a failed accept surfaces an error message instead of throwing', () async {
      final client = FakeFriendsClient()
        ..links = [
          const FriendLink(id: 'l1', requesterId: _otherId, addresseeId: _myId, status: FriendLinkStatus.pending),
        ]
        ..acceptError = Exception('RLS denied');
      final controller = _controller(client);
      await controller.load();

      await controller.accept('l1');

      expect(controller.errorMessage, isNotNull);
    });
  });

  group('decline', () {
    test('deletes the link and it disappears from incoming', () async {
      final client = FakeFriendsClient()
        ..links = [
          const FriendLink(id: 'l1', requesterId: _otherId, addresseeId: _myId, status: FriendLinkStatus.pending),
        ];
      final controller = _controller(client);
      await controller.load();

      await controller.decline('l1');

      expect(client.lastDeletedLinkId, 'l1');
      expect(controller.incoming, isEmpty);
      expect(controller.friends, isEmpty);
    });
  });

  group('remove (unfriend)', () {
    test('deletes an accepted link and it disappears from friends', () async {
      final client = FakeFriendsClient()
        ..links = [
          const FriendLink(id: 'l1', requesterId: _myId, addresseeId: _friendId, status: FriendLinkStatus.accepted),
        ];
      final controller = _controller(client);
      await controller.load();
      expect(controller.friends, hasLength(1));

      await controller.remove('l1');

      expect(client.lastDeletedLinkId, 'l1');
      expect(controller.friends, isEmpty);
    });
  });

  group('addByEmail', () {
    test('requested reloads the lists', () async {
      final client = FakeFriendsClient()..requestFriendResult = 'requested';
      final controller = _controller(client);

      final status = await controller.addByEmail('friend@example.com');

      expect(status, 'requested');
      expect(client.lastRequestedEmail, 'friend@example.com');
      expect(client.lastRequestAccessToken, 'token-1');
    });

    test('self is returned without crashing and without reloading', () async {
      final client = FakeFriendsClient()..requestFriendResult = 'self';
      final controller = _controller(client);

      final status = await controller.addByEmail('me@example.com');

      expect(status, 'self');
    });

    test('duplicate is returned without crashing', () async {
      final client = FakeFriendsClient()..requestFriendResult = 'duplicate';
      final controller = _controller(client);

      final status = await controller.addByEmail('friend@example.com');

      expect(status, 'duplicate');
    });

    test('not_a_user is returned so the UI can offer the challenge invite', () async {
      final client = FakeFriendsClient()..requestFriendResult = 'not_a_user';
      final controller = _controller(client);

      final status = await controller.addByEmail('nobody@example.com');

      expect(status, 'not_a_user');
    });

    test('invalid_email is returned without crashing', () async {
      final client = FakeFriendsClient()..requestFriendResult = 'invalid_email';
      final controller = _controller(client);

      final status = await controller.addByEmail('not-an-email');

      expect(status, 'invalid_email');
    });
  });
}
