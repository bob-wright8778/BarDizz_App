import 'package:flutter_test/flutter_test.dart';
import 'package:hockey_shot_tracker/backend/insforge_friends_client.dart';

void main() {
  group('parseFriendRequestStatus', () {
    test('parses a bare JSON string', () {
      expect(parseFriendRequestStatus('"requested"'), 'requested');
    });

    test('parses a single-row array wrapping the scalar under the function name', () {
      expect(parseFriendRequestStatus('[{"request_friend":"not_a_user"}]'), 'not_a_user');
    });

    test('parses a bare object wrapping the scalar under the function name', () {
      expect(parseFriendRequestStatus('{"request_friend":"self"}'), 'self');
    });

    test('parses a single-key object under any key name', () {
      expect(parseFriendRequestStatus('{"result":"duplicate"}'), 'duplicate');
    });

    test('parses a single-row array of a single-key object', () {
      expect(parseFriendRequestStatus('[{"value":"invalid_email"}]'), 'invalid_email');
    });

    test('throws a FriendsException on an unrecognizable shape', () {
      expect(() => parseFriendRequestStatus('{"foo": 1, "bar": 2}'), throwsA(isA<Exception>()));
    });
  });
}
