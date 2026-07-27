/// One row from `public.snapshots`: a user's published best-session summary
/// (display name, avatar, bar-down rate/count). Never carries an email.
class Snapshot {
  const Snapshot({
    required this.userId,
    this.displayName,
    this.avatarId,
    required this.barDownRate,
    required this.barDownCount,
  });

  final String userId;
  final String? displayName;
  final String? avatarId;
  final double barDownRate;
  final int barDownCount;

  factory Snapshot.fromJson(Map<String, dynamic> json) => Snapshot(
        userId: json['user_id'] as String,
        displayName: json['display_name'] as String?,
        avatarId: json['avatar_id'] as String?,
        barDownRate: (json['bar_down_rate'] as num?)?.toDouble() ?? 0,
        barDownCount: (json['bar_down_count'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'user_id': userId,
        'display_name': displayName,
        'avatar_id': avatarId,
        'bar_down_rate': barDownRate,
        'bar_down_count': barDownCount,
      };
}
