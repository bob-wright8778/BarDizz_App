import 'package:flutter_test/flutter_test.dart';
import 'package:hockey_shot_tracker/history/session_record.dart';

void main() {
  test('toJson/fromJson round-trips all fields', () {
    final record = SessionRecord(
      date: DateTime.utc(2026, 7, 16, 18, 30),
      duration: const Duration(minutes: 12, seconds: 34),
      shotCount: 87,
      goal: 10000,
    );

    final restored = SessionRecord.fromJson(record.toJson());

    expect(restored.date, record.date);
    expect(restored.duration, record.duration);
    expect(restored.shotCount, 87);
    expect(restored.goal, 10000);
  });
}
