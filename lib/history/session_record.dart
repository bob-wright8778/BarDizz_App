/// A single completed shooting session, persisted to local history.
class SessionRecord {
  const SessionRecord({
    required this.date,
    required this.duration,
    required this.shotCount,
    required this.goal,
  });

  final DateTime date;
  final Duration duration;
  final int shotCount;
  final int goal;

  /// Outputs: a JSON-encodable map representation.
  Map<String, dynamic> toJson() => {
        'date': date.toIso8601String(),
        'durationSeconds': duration.inSeconds,
        'shotCount': shotCount,
        'goal': goal,
      };

  /// Inputs: [json] a map previously produced by [toJson].
  factory SessionRecord.fromJson(Map<String, dynamic> json) => SessionRecord(
        date: DateTime.parse(json['date'] as String),
        duration: Duration(seconds: json['durationSeconds'] as int),
        shotCount: json['shotCount'] as int,
        goal: json['goal'] as int,
      );
}
