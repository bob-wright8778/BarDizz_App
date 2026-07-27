import 'dart:convert';

import 'package:http/http.dart' as http;

import 'insforge_config.dart';
import 'insforge_rest.dart';
import 'snapshot_models.dart';
import 'snapshots_client.dart';

/// [SnapshotsClient] backed by InsForge's REST database API over `http`.
/// Upsert is PATCH-then-POST since the exact upsert envelope InsForge expects
/// is unconfirmed against the live project -- see ticket04-implementation.md.
class InsforgeSnapshotsClient implements SnapshotsClient {
  InsforgeSnapshotsClient({http.Client? httpClient, this.baseUrl = insforgeBaseUrl})
      : _client = httpClient ?? http.Client();

  final http.Client _client;
  final String baseUrl;

  @override
  Future<List<Snapshot>> fetchLeaderboard({required String accessToken}) async {
    final uri = Uri.parse('$baseUrl/api/database/records/snapshots');
    final response = await _client.get(uri, headers: {'Authorization': 'Bearer $accessToken'});
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw SnapshotsException('Failed fetching leaderboard (HTTP ${response.statusCode})');
    }
    return [for (final row in parseRecordList(response.body)) Snapshot.fromJson(row)];
  }

  @override
  Future<void> upsertSnapshot({
    required String accessToken,
    required String userId,
    String? displayName,
    String? avatarId,
    required double barDownRate,
    required int barDownCount,
  }) async {
    final headers = {'Content-Type': 'application/json', 'Authorization': 'Bearer $accessToken'};
    final fields = {
      'display_name': displayName,
      'avatar_id': avatarId,
      'bar_down_rate': barDownRate,
      'bar_down_count': barDownCount,
    };

    final patchUri = Uri.parse('$baseUrl/api/database/records/snapshots?user_id=eq.$userId');
    final patchResponse = await _client.patch(patchUri, headers: headers, body: jsonEncode(fields));
    final patchOk = patchResponse.statusCode >= 200 && patchResponse.statusCode < 300;
    if (patchOk && _affectedARow(patchResponse.body)) return;

    final postUri = Uri.parse('$baseUrl/api/database/records/snapshots');
    final postResponse = await _client.post(
      postUri,
      headers: headers,
      body: jsonEncode({...fields, 'user_id': userId}),
    );
    if (postResponse.statusCode < 200 || postResponse.statusCode >= 300) {
      throw SnapshotsException('Failed publishing snapshot (HTTP ${postResponse.statusCode})');
    }
  }

  /// Inputs: a PATCH response body.
  /// Outputs: whether it indicates a row was actually matched/updated -- an
  /// empty array/no records means no row existed yet and POST must run.
  bool _affectedARow(String body) {
    if (body.isEmpty) return false;
    final decoded = jsonDecode(body);
    if (decoded is List) return decoded.isNotEmpty;
    if (decoded is Map<String, dynamic>) {
      final records = decoded['records'];
      if (records is List) return records.isNotEmpty;
      return decoded.isNotEmpty;
    }
    return false;
  }
}
