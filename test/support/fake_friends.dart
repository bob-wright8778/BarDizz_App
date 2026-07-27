import 'package:hockey_shot_tracker/backend/auth_models.dart';
import 'package:hockey_shot_tracker/backend/friends_client.dart';
import 'package:hockey_shot_tracker/backend/friends_models.dart';

/// Scriptable [FriendsClient] fake: no network, ever. Every response/error is
/// set up by the test before use; every request is recorded for assertions.
class FakeFriendsClient implements FriendsClient {
  List<FriendLink> links = [];
  Map<String, AuthProfile> profilesByUserId = {};
  String requestFriendResult = 'requested';
  Object? requestFriendError;
  Object? listLinksError;
  Object? acceptError;
  Object? deleteError;

  String? lastRequestedEmail;
  String? lastRequestAccessToken;
  String? lastAcceptedLinkId;
  String? lastDeletedLinkId;
  int deleteCallCount = 0;
  int acceptCallCount = 0;

  @override
  Future<String> requestFriend({required String accessToken, required String targetEmail}) async {
    lastRequestAccessToken = accessToken;
    lastRequestedEmail = targetEmail;
    final error = requestFriendError;
    if (error != null) throw error;
    return requestFriendResult;
  }

  @override
  Future<List<FriendLink>> listLinks({required String accessToken}) async {
    final error = listLinksError;
    if (error != null) throw error;
    return links;
  }

  @override
  Future<void> acceptLink({required String accessToken, required String linkId}) async {
    lastAcceptedLinkId = linkId;
    acceptCallCount++;
    final error = acceptError;
    if (error != null) throw error;
    links = [
      for (final l in links)
        if (l.id == linkId)
          FriendLink(id: l.id, requesterId: l.requesterId, addresseeId: l.addresseeId, status: FriendLinkStatus.accepted)
        else
          l,
    ];
  }

  @override
  Future<void> deleteLink({required String accessToken, required String linkId}) async {
    lastDeletedLinkId = linkId;
    deleteCallCount++;
    final error = deleteError;
    if (error != null) throw error;
    links = [for (final l in links) if (l.id != linkId) l];
  }

  @override
  Future<AuthProfile> fetchProfile({required String userId}) async {
    return profilesByUserId[userId] ?? const AuthProfile();
  }
}
