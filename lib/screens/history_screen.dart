import 'package:flutter/material.dart';

import '../history/session_history_store.dart';
import '../history/session_record.dart';

/// Lists past completed sessions, most recent first (Acceptance criterion:
/// a history screen lists past sessions, persisted across app restarts).
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key, this.store = const SessionHistoryStore()});

  final SessionHistoryStore store;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<SessionRecord>? _sessions;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final sessions = await widget.store.loadSessions();
      if (mounted) setState(() => _sessions = sessions);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  String _describe(SessionRecord session) {
    final progress = session.goal == 0
        ? 0
        : (session.shotCount / session.goal * 100).clamp(0, 100).round();
    final date = session.date.toLocal().toString().split('.').first;
    return '$date • ${session.duration.inMinutes} min • $progress% of ${session.goal}';
  }

  Widget _buildBody() {
    if (_error != null) {
      return Center(child: Text(_error!, key: const Key('historyErrorText')));
    }
    final sessions = _sessions;
    if (sessions == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (sessions.isEmpty) {
      return const Center(child: Text('No sessions yet', key: Key('historyEmptyText')));
    }
    return ListView.builder(
      key: const Key('historyList'),
      itemCount: sessions.length,
      itemBuilder: (context, index) {
        final session = sessions[index];
        return ListTile(
          title: Text('${session.shotCount} shots'),
          subtitle: Text(_describe(session)),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('History')),
      body: _buildBody(),
    );
  }
}
