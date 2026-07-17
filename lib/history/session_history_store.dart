import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'session_record.dart';

const String _historyKey = 'session_history';

/// Persists completed sessions locally via [SharedPreferences] so history
/// survives app restarts (local storage only — no login, no cloud sync).
class SessionHistoryStore {
  const SessionHistoryStore();

  /// Outputs: all saved sessions, most recent first.
  Future<List<SessionRecord>> loadSessions() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getStringList(_historyKey) ?? [];
    final sessions = stored
        .map((entry) => SessionRecord.fromJson(jsonDecode(entry) as Map<String, dynamic>))
        .toList();
    sessions.sort((a, b) => b.date.compareTo(a.date));
    return sessions;
  }

  /// Inputs: [session] the completed session to add to history.
  Future<void> saveSession(SessionRecord session) async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getStringList(_historyKey) ?? [];
    await prefs.setStringList(_historyKey, [...stored, jsonEncode(session.toJson())]);
  }
}
