/// A `friend_links` row's two possible persisted states; a declined/removed
/// link is deleted server-side, never represented here.
enum FriendLinkStatus { pending, accepted }

/// One row from `public.friend_links`, as returned by the InsForge REST API.
class FriendLink {
  const FriendLink({
    required this.id,
    required this.requesterId,
    required this.addresseeId,
    required this.status,
  });

  final String id;
  final String requesterId;
  final String addresseeId;
  final FriendLinkStatus status;

  factory FriendLink.fromJson(Map<String, dynamic> json) => FriendLink(
        id: json['id'] as String,
        requesterId: json['requester_id'] as String,
        addresseeId: json['addressee_id'] as String,
        status: json['status'] == 'accepted' ? FriendLinkStatus.accepted : FriendLinkStatus.pending,
      );
}

/// Which side of a [FriendLink] the signed-in user is on, relative to the
/// other party -- drives which section of the Friends tab a row appears in.
enum FriendDirection { incoming, outgoing, friend }

/// A [FriendLink] enriched with the other party's public display name and
/// avatar, ready for a Friends-tab row. Never carries an email.
class FriendListItem {
  const FriendListItem({
    required this.link,
    required this.otherUserId,
    required this.direction,
    this.displayName,
    this.avatarId,
  });

  final FriendLink link;
  final String otherUserId;
  final FriendDirection direction;
  final String? displayName;
  final String? avatarId;
}
