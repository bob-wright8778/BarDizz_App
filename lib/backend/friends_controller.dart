import 'package:flutter/foundation.dart';

import 'friends_client.dart';
import 'friends_models.dart';

/// Owns the signed-in user's friend graph: loads/splits incoming, outgoing,
/// and accepted links, and drives add/accept/decline/remove. The Session
/// shot-tracking path never touches this.
class FriendsController extends ChangeNotifier {
  FriendsController({required this.client, required this.myUserId, required this.accessToken});

  final FriendsClient client;
  final String myUserId;
  final String accessToken;

  bool loading = false;
  String? errorMessage;
  List<FriendListItem> incoming = [];
  List<FriendListItem> outgoing = [];
  List<FriendListItem> friends = [];

  /// Fetches every link visible under RLS, resolves each other party's
  /// public profile, and splits the results into the three lists.
  Future<void> load() async {
    loading = true;
    errorMessage = null;
    notifyListeners();
    try {
      final links = await client.listLinks(accessToken: accessToken);
      final items = <FriendListItem>[];
      for (final link in links) {
        final otherId = link.requesterId == myUserId ? link.addresseeId : link.requesterId;
        final direction = _directionFor(link, otherId);
        final profile = await client.fetchProfile(userId: otherId);
        items.add(FriendListItem(
          link: link,
          otherUserId: otherId,
          direction: direction,
          displayName: profile.name,
          avatarId: profile.avatarId,
        ));
      }
      incoming = [for (final i in items) if (i.direction == FriendDirection.incoming) i];
      outgoing = [for (final i in items) if (i.direction == FriendDirection.outgoing) i];
      friends = [for (final i in items) if (i.direction == FriendDirection.friend) i];
    } catch (_) {
      errorMessage = 'Could not load friends. Try again.';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  FriendDirection _directionFor(FriendLink link, String otherId) {
    if (link.status == FriendLinkStatus.accepted) return FriendDirection.friend;
    return link.requesterId == myUserId ? FriendDirection.outgoing : FriendDirection.incoming;
  }

  /// Inputs: a candidate email (validation/trimming is the caller's job).
  /// Outputs: the RPC status code; the UI maps it to a message or the
  /// challenge-invite offer. Reloads the lists on a successful request.
  Future<String> addByEmail(String email) async {
    final status = await client.requestFriend(accessToken: accessToken, targetEmail: email);
    if (status == 'requested') await load();
    return status;
  }

  /// Inputs: an incoming pending link id. Accepts it and reloads the lists.
  Future<void> accept(String linkId) async {
    try {
      await client.acceptLink(accessToken: accessToken, linkId: linkId);
      await load();
    } catch (_) {
      errorMessage = 'Could not accept the request. Try again.';
      notifyListeners();
    }
  }

  /// Inputs: a pending link id. Declines it (deletes the row) and reloads.
  Future<void> decline(String linkId) async {
    try {
      await client.deleteLink(accessToken: accessToken, linkId: linkId);
      await load();
    } catch (_) {
      errorMessage = 'Could not remove the link. Try again.';
      notifyListeners();
    }
  }

  /// Inputs: an accepted link id. Removes it (unfriend) -- same delete op as
  /// [decline], different UI entry point.
  Future<void> remove(String linkId) => decline(linkId);
}
