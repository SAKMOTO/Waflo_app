/// DB-backed public profile for a Waflo account.
///
/// This is the shape of the `profiles` table. Any Google-sourced identity
/// (email, Google name, Google avatar, provider) lives on the auth session
/// managed by [UserProfileController], which merges the two sources — a
/// custom profile field wins over the Google default, never the other way.
class UserProfileModel {
  final String id;
  final String displayName;
  final String? username;
  final String bio;

  /// Custom uploaded avatar. Either an https object URL from Supabase
  /// Storage or a `data:` URL (used by the offline fallback). Null means
  /// "use the Google avatar", never a broken URL.
  final String? avatarUrl;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  const UserProfileModel({
    required this.id,
    this.displayName = '',
    this.username,
    this.bio = '',
    this.avatarUrl,
    this.createdAt,
    this.updatedAt,
  });

  bool get hasCustomAvatar => avatarUrl != null && avatarUrl!.trim().isNotEmpty;

  /// Strips a leading "@" (the UI keeps the raw handle without it).
  String? get cleanUsername {
    final u = username?.trim();
    if (u == null || u.isEmpty) return null;
    return u.startsWith('@') ? u.substring(1) : u;
  }

  Map<String, dynamic> toDbMap() => {
    'id': id,
    'display_name': displayName,
    'username': cleanUsername,
    'bio': bio,
    'avatar_url': avatarUrl,
    'created_at': createdAt?.toUtc().toIso8601String(),
    'updated_at': updatedAt?.toUtc().toIso8601String(),
  };

  Map<String, dynamic> toLocalMap() => toDbMap();

  factory UserProfileModel.fromJson(Map<String, dynamic> json) {
    return UserProfileModel(
      id: (json['id'] ?? '') as String,
      displayName: (json['display_name'] as String?) ?? '',
      username: json['username'] as String?,
      bio: (json['bio'] as String?) ?? '',
      avatarUrl: json['avatar_url'] as String?,
      createdAt: _parseDate(json['created_at']),
      updatedAt: _parseDate(json['updated_at']),
    );
  }

  UserProfileModel copyWith({
    String? displayName,
    String? username,
    String? bio,
    String? avatarUrl,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return UserProfileModel(
      id: id,
      displayName: displayName ?? this.displayName,
      username: username ?? this.username,
      bio: bio ?? this.bio,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  static DateTime? _parseDate(Object? value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    return DateTime.tryParse(value.toString());
  }
}