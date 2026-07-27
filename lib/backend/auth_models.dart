/// A signed-in InsForge user. Email is read here (it's part of every
/// auth/session response) but must never be surfaced in Friends/Profile UI.
class AuthUser {
  const AuthUser({required this.id, required this.email});

  final String id;
  final String email;

  factory AuthUser.fromJson(Map<String, dynamic> json) => AuthUser(
        id: json['id'] as String,
        email: json['email'] as String? ?? '',
      );
}

/// The token pair returned by an OAuth exchange or a refresh call, alongside
/// the user they belong to.
class AuthSession {
  const AuthSession({required this.user, required this.accessToken, required this.refreshToken});

  final AuthUser user;
  final String accessToken;
  final String refreshToken;

  factory AuthSession.fromJson(Map<String, dynamic> json) => AuthSession(
        user: AuthUser.fromJson(json['user'] as Map<String, dynamic>),
        accessToken: json['accessToken'] as String,
        refreshToken: json['refreshToken'] as String,
      );
}

/// The InsForge built-in profile's custom fields this app uses: a display
/// name and a bundled avatar ID. Never carries the user's email.
class AuthProfile {
  const AuthProfile({this.name, this.avatarId});

  final String? name;
  final String? avatarId;

  /// Outputs: true once both a display name and an avatar have been set.
  bool get isComplete => (name?.isNotEmpty ?? false) && (avatarId?.isNotEmpty ?? false);

  factory AuthProfile.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const AuthProfile();
    return AuthProfile(
      name: json['name'] as String?,
      avatarId: json['avatar_id'] as String?,
    );
  }
}

/// Any failure talking to the InsForge auth/profile API or completing the
/// OAuth round-trip.
class AuthException implements Exception {
  const AuthException(this.message);

  final String message;

  @override
  String toString() => 'AuthException: $message';
}
