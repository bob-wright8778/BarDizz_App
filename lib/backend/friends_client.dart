import 'auth_models.dart';
import 'friends_models.dart';

/// The InsForge friend-graph REST surface this app depends on, abstracted so
/// the UI/state layer never imports `http` directly and tests can fake it.
abstract class FriendsClient {
  /// Inputs: the caller's access token and the target's email.
  /// Outputs: the RPC status code -- one of requested/not_a_user/self/
  /// duplicate/invalid_email.
  Future<String> requestFriend({required String accessToken, required String targetEmail});

  /// Inputs: the caller's access token.
  /// Outputs: every `friend_links` row visible to the caller under RLS.
  Future<List<FriendLink>> listLinks({required String accessToken});

  /// Inputs: the caller's access token and the link id to accept.
  /// Outputs: none; flips the link to accepted server-side (addressee only).
  Future<void> acceptLink({required String accessToken, required String linkId});

  /// Inputs: the caller's access token and the link id to remove.
  /// Outputs: none; deletes the link row -- used for both decline and unfriend.
  Future<void> deleteLink({required String accessToken, required String linkId});

  /// Inputs: the other party's user id.
  /// Outputs: their public profile (name/avatar only, never email).
  Future<AuthProfile> fetchProfile({required String userId});
}

/// Any failure talking to the InsForge friend-graph API.
class FriendsException implements Exception {
  const FriendsException(this.message);

  final String message;

  @override
  String toString() => 'FriendsException: $message';
}
