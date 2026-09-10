/// Per-account app preferences backed by the `user_preferences` table
/// (with a localStorage mirror so it works offline / pre-migration).
class UserPreferencesModel {
  /// Theme id matching [AppThemeId.name], e.g. "midnight".
  final String theme;

  /// Registered avatar character id — the "Default Agent".
  final String defaultAgent;

  final bool animationsEnabled;
  final bool soundEnabled;
  final bool reduceMotion;

  const UserPreferencesModel({
    this.theme = 'midnight',
    this.defaultAgent = 'strobi',
    this.animationsEnabled = true,
    this.soundEnabled = true,
    this.reduceMotion = false,
  });

  UserPreferencesModel copyWith({
    String? theme,
    String? defaultAgent,
    bool? animationsEnabled,
    bool? soundEnabled,
    bool? reduceMotion,
  }) {
    return UserPreferencesModel(
      theme: theme ?? this.theme,
      defaultAgent: defaultAgent ?? this.defaultAgent,
      animationsEnabled: animationsEnabled ?? this.animationsEnabled,
      soundEnabled: soundEnabled ?? this.soundEnabled,
      reduceMotion: reduceMotion ?? this.reduceMotion,
    );
  }

  Map<String, dynamic> toDbMap() => {
    'id': '',
    'theme': theme,
    'default_agent': defaultAgent,
    'animations_enabled': animationsEnabled,
    'sound_enabled': soundEnabled,
    'reduce_motion': reduceMotion,
  };

  Map<String, dynamic> toLocalMap() => {
    'theme': theme,
    'default_agent': defaultAgent,
    'animations_enabled': animationsEnabled,
    'sound_enabled': soundEnabled,
    'reduce_motion': reduceMotion,
  };

  factory UserPreferencesModel.fromMap(Map<String, dynamic> json) {
    return UserPreferencesModel(
      theme: (json['theme'] as String?) ?? 'midnight',
      defaultAgent: (json['default_agent'] as String?) ?? 'strobi',
      animationsEnabled: (json['animations_enabled'] as bool?) ?? true,
      soundEnabled: (json['sound_enabled'] as bool?) ?? true,
      reduceMotion: (json['reduce_motion'] as bool?) ?? false,
    );
  }
}