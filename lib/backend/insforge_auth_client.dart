import 'dart:convert';

import 'package:http/http.dart' as http;

import 'auth_client.dart';
import 'auth_models.dart';
import 'insforge_config.dart';

/// [AuthClient] backed by InsForge's REST auth/profile API over `http`.
class InsforgeAuthClient implements AuthClient {
  InsforgeAuthClient({http.Client? httpClient, this.baseUrl = insforgeBaseUrl})
      : _client = httpClient ?? http.Client();

  final http.Client _client;
  final String baseUrl;

  @override
  Future<String> requestAuthUrl({
    required String provider,
    required String redirectUri,
    required String codeChallenge,
  }) async {
    final uri = Uri.parse('$baseUrl/api/auth/oauth/$provider').replace(queryParameters: {
      'redirect_uri': redirectUri,
      'code_challenge': codeChallenge,
    });
    final body = _decode(await _client.get(uri), 'requesting the OAuth URL');
    final authUrl = body['authUrl'] as String?;
    if (authUrl == null) throw const AuthException('Missing authUrl in OAuth response');
    return authUrl;
  }

  @override
  Future<AuthSession> exchangeCode({required String code, required String codeVerifier}) async {
    final uri = Uri.parse('$baseUrl/api/auth/oauth/exchange?client_type=mobile');
    final response = await _client.post(
      uri,
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'code': code, 'code_verifier': codeVerifier}),
    );
    return AuthSession.fromJson(_decode(response, 'exchanging the OAuth code'));
  }

  @override
  Future<AuthSession> refresh({required String refreshToken}) async {
    final uri = Uri.parse('$baseUrl/api/auth/refresh?client_type=mobile');
    final response = await _client.post(
      uri,
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'refreshToken': refreshToken}),
    );
    return AuthSession.fromJson(_decode(response, 'refreshing the session'));
  }

  @override
  Future<AuthProfile> fetchProfile({required String userId}) async {
    final uri = Uri.parse('$baseUrl/api/auth/profiles/$userId');
    final body = _decode(await _client.get(uri), 'fetching the profile');
    return AuthProfile.fromJson(body['profile'] as Map<String, dynamic>?);
  }

  @override
  Future<AuthProfile> updateProfile({
    required String accessToken,
    required String displayName,
    required String avatarId,
  }) async {
    final uri = Uri.parse('$baseUrl/api/auth/profiles/current');
    final response = await _client.patch(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $accessToken',
      },
      body: jsonEncode({
        'profile': {'name': displayName, 'avatar_id': avatarId},
      }),
    );
    final body = _decode(response, 'updating the profile');
    final profileJson = (body['profile'] ?? body) as Map<String, dynamic>;
    return AuthProfile.fromJson(profileJson);
  }

  @override
  Future<void> signOut({required String accessToken}) async {
    final uri = Uri.parse('$baseUrl/api/auth/logout');
    await _client.post(uri, headers: {'Authorization': 'Bearer $accessToken'});
  }

  Map<String, dynamic> _decode(http.Response response, String action) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AuthException('Failed $action (HTTP ${response.statusCode})');
    }
    if (response.body.isEmpty) return const {};
    return jsonDecode(response.body) as Map<String, dynamic>;
  }
}
