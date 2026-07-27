import 'dart:convert';

import 'package:http/http.dart' as http;

import 'auth_models.dart';
import 'friends_client.dart';
import 'friends_models.dart';
import 'insforge_config.dart';
import 'insforge_rest.dart';

/// [FriendsClient] backed by InsForge's REST database/auth API over `http`.
class InsforgeFriendsClient implements FriendsClient {
  InsforgeFriendsClient({http.Client? httpClient, this.baseUrl = insforgeBaseUrl})
      : _client = httpClient ?? http.Client();

  final http.Client _client;
  final String baseUrl;

  @override
  Future<String> requestFriend({required String accessToken, required String targetEmail}) async {
    final uri = Uri.parse('$baseUrl/api/database/rpc/request_friend');
    final response = await _client.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $accessToken',
      },
      body: jsonEncode({'target_email': targetEmail}),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw FriendsException('Failed requesting friend (HTTP ${response.statusCode})');
    }
    return parseFriendRequestStatus(response.body);
  }

  @override
  Future<List<FriendLink>> listLinks({required String accessToken}) async {
    final uri = Uri.parse('$baseUrl/api/database/records/friend_links?order=created_at.desc');
    final response = await _client.get(uri, headers: {'Authorization': 'Bearer $accessToken'});
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw FriendsException('Failed listing friend links (HTTP ${response.statusCode})');
    }
    return [for (final row in parseRecordList(response.body)) FriendLink.fromJson(row)];
  }

  @override
  Future<void> acceptLink({required String accessToken, required String linkId}) async {
    final uri = Uri.parse('$baseUrl/api/database/records/friend_links?id=eq.$linkId');
    final response = await _client.patch(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $accessToken',
      },
      body: jsonEncode({'status': 'accepted'}),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw FriendsException('Failed accepting friend request (HTTP ${response.statusCode})');
    }
  }

  @override
  Future<void> deleteLink({required String accessToken, required String linkId}) async {
    final uri = Uri.parse('$baseUrl/api/database/records/friend_links?id=eq.$linkId');
    final response = await _client.delete(uri, headers: {'Authorization': 'Bearer $accessToken'});
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw FriendsException('Failed removing friend link (HTTP ${response.statusCode})');
    }
  }

  @override
  Future<AuthProfile> fetchProfile({required String userId}) async {
    final uri = Uri.parse('$baseUrl/api/auth/profiles/$userId');
    final response = await _client.get(uri);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw FriendsException('Failed fetching profile (HTTP ${response.statusCode})');
    }
    final body = response.body.isEmpty ? const {} : jsonDecode(response.body) as Map<String, dynamic>;
    return AuthProfile.fromJson(body['profile'] as Map<String, dynamic>?);
  }

}

/// Inputs: the raw response body from the `request_friend` RPC.
/// Outputs: the scalar status text, unwrapping whatever envelope PostgREST
/// used -- a bare JSON string, a single-key object, or a one-row array.
String parseFriendRequestStatus(String body) {
  final decoded = jsonDecode(body);
  final status = _asScalarString(decoded);
  if (status == null) {
    throw FriendsException('Unexpected request_friend response: $body');
  }
  return status;
}

String? _asScalarString(dynamic value) {
  if (value is String) return value;
  if (value is List && value.isNotEmpty) return _asScalarString(value.first);
  if (value is Map) {
    if (value.length == 1) return _asScalarString(value.values.first);
    for (final key in ['request_friend', 'result', 'value', 'status']) {
      if (value.containsKey(key)) return _asScalarString(value[key]);
    }
  }
  return null;
}
