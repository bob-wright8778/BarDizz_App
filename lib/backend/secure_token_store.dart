import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const _accessTokenKey = 'auth_access_token';
const _refreshTokenKey = 'auth_refresh_token';

/// Persists the OAuth token pair, abstracted so tests can fake it instead of
/// touching real secure storage.
abstract class SecureTokenStore {
  Future<void> saveTokens({required String accessToken, required String refreshToken});
  Future<String?> readAccessToken();
  Future<String?> readRefreshToken();

  /// Clears both tokens (sign-out).
  Future<void> clear();
}

/// [SecureTokenStore] backed by `flutter_secure_storage` (Keystore/Keychain).
class FlutterSecureTokenStore implements SecureTokenStore {
  const FlutterSecureTokenStore({this.storage = const FlutterSecureStorage()});

  final FlutterSecureStorage storage;

  @override
  Future<void> saveTokens({required String accessToken, required String refreshToken}) async {
    await storage.write(key: _accessTokenKey, value: accessToken);
    await storage.write(key: _refreshTokenKey, value: refreshToken);
  }

  @override
  Future<String?> readAccessToken() => storage.read(key: _accessTokenKey);

  @override
  Future<String?> readRefreshToken() => storage.read(key: _refreshTokenKey);

  @override
  Future<void> clear() async {
    await storage.delete(key: _accessTokenKey);
    await storage.delete(key: _refreshTokenKey);
  }
}
