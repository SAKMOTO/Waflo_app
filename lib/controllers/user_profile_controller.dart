import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:waflo_app/controllers/avatar_controller.dart';
import 'package:waflo_app/models/user_preferences_model.dart';
import 'package:waflo_app/models/user_profile_model.dart';
import 'package:waflo_app/services/supabase_service.dart';
import 'package:waflo_app/services/user_profile_service.dart';
import 'package:waflo_app/theme/app_theme.dart';
import 'package:waflo_app/controllers/settings_controller.dart' as legacy;
import 'package:web/web.dart' as web;

/// Lifecycle of the signed-in account UI.
enum ProfileStatus { signedOut, loading, ready, error }

/// App-wide state for the signed-in Google account: merged profile (custom
/// profile wins over Google metadata), preferences, avatar uploads and sign
/// out.
///
/// Data model (see `supabase/migrations/0002_profiles_preferences.sql`):
///   * `profiles`          -> custom display name / username / bio / avatar
///   * `user_preferences`  -> theme + app behaviour
///   * `avatars` bucket    -> uploaded profile pictures
///
/// Because the tables are added by a one-time migration, every store also has
/// a localStorage mirror keyed by the user id. The database is the source of
/// truth once reachable; the mirror keeps Settings fully functional before
/// the migration (and offline). Nothing here ever hardcodes a name, email or
/// avatar — every value comes from Supabase.
class UserProfileController extends ChangeNotifier {
  UserProfileController._() {
    _seedFromLegacySettings();
  }

  static final UserProfileController instance = UserProfileController._();

  StreamSubscription<AuthState>? _authSub;
  static bool _started = false;

  // local-mirror keys (one per signed-in user)
  static const _profileKeyPrefix = 'waflo.profile.v1.';
  static const _prefsKeyPrefix = 'waflo.prefs.v1.';

  ProfileStatus _status = ProfileStatus.signedOut;
  UserProfileModel? _profile;
  UserPreferencesModel? _preferences;

  ProfileStatus get status => _status;
  bool get loading => _status == ProfileStatus.loading;
  bool get signedInGoogle => SupabaseService.isSignedInWithGoogle;
  bool get signedOut => !SupabaseService.isSignedInWithGoogle;

  UserProfileModel? get profile => _profile;
  UserPreferencesModel? get preferences => _preferences;

  User? get user => SupabaseService.currentUser;
  String? get userId => user?.id;

  // --------------------------------------------------- effective user values

  String? get email => user?.email;

  /// Display name: custom profile value wins, then Google full name, then the
  /// local part of the account email. Never blank; never hardcoded.
  String get displayName {
    final custom = _profile?.displayName.trim();
    if (custom != null && custom.isNotEmpty) return custom;
    final google = _googleFullName;
    if (google != null && google.trim().isNotEmpty) return google.trim();
    final mail = email;
    if (mail != null && mail.isNotEmpty) return mail.split('@').first;
    return 'Account';
  }

  String get greetingName => displayName;

  /// "@handle" — the custom username, else the local part of the email.
  String get handle {
    final u = _profile?.cleanUsername;
    if (u != null && u.isNotEmpty) return '@$u';
    final mail = email;
    if (mail != null && mail.isNotEmpty) return '@${mail.split('@').first}';
    return '';
  }

  String get bio => _profile?.bio ?? '';

  String? get username => _profile?.cleanUsername;

  /// Custom upload first, Google profile picture as the default.
  String? get avatarUrl {
    final custom = _profile?.avatarUrl;
    if (custom != null && custom.trim().isNotEmpty) return custom.trim();
    return _googleAvatarUrl;
  }

  bool get hasCustomAvatar =>
      (_profile?.avatarUrl != null && _profile!.avatarUrl!.trim().isNotEmpty);

  String? get googleAvatarUrl => _googleAvatarUrl;

  /// Where the account came from (Supabase provider, e.g. Google).
  String get providerLabel {
    final p = user?.appMetadata['provider'];
    if (p is String && p.isNotEmpty) {
      return p[0].toUpperCase() + p.substring(1);
    }
    return 'Google';
  }

  String? get accountCreatedAt => user?.createdAt;

  String get sessionStatus =>
      signedInGoogle ? 'Active' : 'Signed out';

  // ------------------------------------------------------------------- start

  /// Wire the controller to Supabase auth. Call once at startup.
  void start() {
    if (_started) return;
    _started = true;
    _authSub = SupabaseService.authStream.listen(_onAuthState);
    // A freshly restored (PKCE) session won't re-emit SIGNED_IN — check now.
    if (SupabaseService.isSignedInWithGoogle) {
      unawaited(refresh());
    }
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  void _onAuthState(AuthState state) {
    switch (state.event) {
      case AuthChangeEvent.signedIn:
      case AuthChangeEvent.tokenRefreshed:
        if (SupabaseService.isSignedInWithGoogle) unawaited(refresh());
      case AuthChangeEvent.initialSession:
        if (SupabaseService.isSignedInWithGoogle) unawaited(refresh());
      case AuthChangeEvent.signedOut:
        _status = ProfileStatus.signedOut;
        _profile = null;
        _preferences = null;
        notifyListeners();
      default:
        break;
    }
  }

  /// Fetch profile + preferences from Supabase, falling back to the local
  /// mirror (and finally to Google metadata) when the database is not yet
  /// migrated or unreachable.
  Future<void> refresh() async {
    final u = user;
    if (u == null || !SupabaseService.isSignedInWithGoogle) {
      _status = ProfileStatus.signedOut;
      _profile = null;
      _preferences = null;
      notifyListeners();
      return;
    }
    _status = ProfileStatus.loading;
    notifyListeners();

    final dbProfile = await UserProfileService.fetchProfile(u.id);
    final local = _readLocalProfile(u.id);
    _profile = dbProfile ?? local ?? _freshFromUser();

    final dbPrefs = await UserProfileService.fetchPreferences(u.id);
    final localPrefs = _readLocalPrefs(u.id);
    _preferences = dbPrefs ?? localPrefs ?? UserPreferencesModel();

    _applyPreferences(_preferences!);
    _status = ProfileStatus.ready;
    notifyListeners();
  }

  // ------------------------------------------------------------- profile ops

  /// Persist display name / username / bio. Returns null on success, or an
  /// error message. Never throws; never loses existing profile data.
  Future<String?> updateProfile({
    required String displayName,
    String? username,
    required String bio,
  }) async {
    final current = _profile;
    final uid = userId;
    if (uid == null || current == null) return 'You need to be signed in.';

    final updated = UserProfileModel(
      id: uid,
      displayName: displayName.trim(),
      username: _normalizeUsername(username),
      bio: bio.trim(),
      avatarUrl: current.avatarUrl,
      createdAt: current.createdAt,
      updatedAt: DateTime.now().toUtc(),
    );

    final saved = await UserProfileService.upsertProfile(updated);
    if (saved != null) {
      _profile = saved;
    } else {
      _profile = updated;
      _saveLocalProfile(uid, updated);
    }
    notifyListeners();
    return null;
  }

  /// Upload a custom profile picture to Supabase Storage (falling back to a
  /// local data URL when storage is unreachable). Returns null or an error.
  Future<String?> uploadAvatarBytes(Uint8List bytes, {String? mimeType}) async {
    final uid = userId;
    if (uid == null) return 'You need to be signed in.';
    final mime = mimeType ?? 'image/png';
    if (!mime.startsWith('image/')) return 'Choose an image file.';
    if (bytes.length > 12 * 1024 * 1024) {
      return 'Image is too large (max 12 MB).';
    }

    final url = await UserProfileService.uploadAvatar(
      userId: uid,
      bytes: bytes,
      mimeType: mime,
    );

    String? avatarUrl;
    if (url != null) {
      avatarUrl = url;
    } else {
      // DB storage unavailable (pre-migration / offline) — keep the image
      // locally so the avatar still works and survives a restart.
      avatarUrl = 'data:$mime;base64,${base64Encode(bytes)}';
    }

    final current = _profile ?? _freshFromUser();
    final updated = UserProfileModel(
      id: uid,
      displayName: current.displayName,
      username: current.username,
      bio: current.bio,
      avatarUrl: avatarUrl,
      createdAt: current.createdAt,
      updatedAt: DateTime.now().toUtc(),
    );
    _profile = updated;
    _saveLocalProfile(uid, updated);
    notifyListeners();
    return null;
  }

  /// Clear the custom avatar so the Google profile picture shows again (and
  /// tidy the uploaded object from storage).
  Future<void> removeAvatar() async {
    final uid = userId;
    if (uid == null) return;
    await UserProfileService.deleteAvatar(uid);
    await _replaceAvatarWith(uid, null);
  }

  /// Revert to the Google profile picture (same as removing the custom one —
  /// the Google picture is the built-in fallback).
  Future<void> revertToGoogleAvatar() => removeAvatar();

  Future<void> _replaceAvatarWith(String uid, String? avatarUrl) async {
    final current = _profile ?? _freshFromUser();
    final updated = UserProfileModel(
      id: uid,
      displayName: current.displayName,
      username: current.username,
      bio: current.bio,
      avatarUrl: avatarUrl,
      createdAt: current.createdAt,
      updatedAt: DateTime.now().toUtc(),
    );
    final saved = await UserProfileService.upsertProfile(updated);
    _profile = saved ?? updated;
    _saveLocalProfile(uid, updated);
    notifyListeners();
  }

  // ----------------------------------------------------------- preferences

  Future<void> updatePreferences(UserPreferencesModel prefs) async {
    _preferences = prefs;
    _applyPreferences(prefs);
    final uid = userId;
    if (uid != null) {
      await UserProfileService.upsertPreferences(uid, prefs);
      _saveLocalPrefs(uid, prefs);
    }
    notifyListeners();
  }

  /// Change the theme: applied instantly app-wide and persisted locally AND
  /// synced to the account preferences when signed in.
  Future<void> setTheme(AppThemeId id) async {
    legacy.AppSettingsController.instance.persistTheme(id);
    final current = _preferences ?? UserPreferencesModel();
    final next = current.copyWith(theme: id.name);
    _preferences = next;
    final uid = userId;
    if (uid != null) {
      await UserProfileService.upsertPreferences(uid, next);
      _saveLocalPrefs(uid, next);
    }
    notifyListeners();
  }

  Future<void> setDefaultAgent(String id) async {
    final current = _preferences ?? UserPreferencesModel();
    await updatePreferences(current.copyWith(defaultAgent: id));
  }

  void _applyPreferences(UserPreferencesModel prefs) {
    final theme = AppThemeId.values.where((t) => t.name == prefs.theme);
    if (theme.isNotEmpty) {
      legacy.AppSettingsController.instance.persistTheme(theme.first);
    }
    if (prefs.defaultAgent.isNotEmpty) {
      AvatarController.instance.selectCharacter(prefs.defaultAgent);
    }
  }

  // ----------------------------------------------------------------- logout

  /// Real Supabase sign-out: clears the server session AND the local profile
  /// caches so the next launch starts clean. Navigation is handled by the UI
  /// (see [AccountFlow]).
  Future<void> signOut() async {
    final uid = userId;
    if (uid != null) {
      _clearLocalProfile(uid);
      _clearLocalPrefs(uid);
    }
    _status = ProfileStatus.signedOut;
    _profile = null;
    _preferences = null;
    notifyListeners();
    try {
      await SupabaseService.signOut();
    } catch (e) {
      debugPrint('UserProfile: signOut error -> $e');
    }
    notifyListeners();
  }

  // ---------------------------------------------------------------- helpers

  String? get _googleFullName =>
      _metaString(['name', 'full_name', 'fullName']);
  String? get _googleAvatarUrl =>
      UserProfileService.googleAvatarFromMetadata(user?.userMetadata);

  String? _metaString(List<String> keys) {
    final meta = user?.userMetadata ?? const <String, dynamic>{};
    for (final key in keys) {
      final v = meta[key];
      if (v is String && v.trim().isNotEmpty) return v.trim();
    }
    return null;
  }

  /// A profile derived purely from the Google session (used before the user
  /// customizes anything). Seeded from the legacy local settings so nothing
  /// the user already saved is lost.
  UserProfileModel _freshFromUser() {
    final legacyBio = _legacyBio;
    final legacyName = _legacyName;
    final googleName = _metaString(['name', 'full_name', 'fullName']);
    final name = (legacyName != null && legacyName.isNotEmpty)
        ? legacyName
        : (googleName ?? '');
    final mail = email;
    final handle = (mail != null && mail.isNotEmpty) ? mail.split('@').first : null;
    return UserProfileModel(
      id: userId ?? '',
      displayName: name,
      username: handle,
      bio: legacyBio ?? '',
      avatarUrl: null,
    );
  }

  String? _normalizeUsername(String? raw) {
    final u = raw?.trim();
    if (u == null || u.isEmpty) return null;
    return u.startsWith('@') ? u.substring(1) : u;
  }

  // ------------------------------------------------------- local reflection

  void _saveLocalProfile(String uid, UserProfileModel p) {
    if (!kIsWeb) return;
    try {
      web.window.localStorage.setItem(
        '$_profileKeyPrefix$uid',
        jsonEncode(p.toLocalMap()),
      );
    } catch (e) {
      debugPrint('UserProfile: save local profile failed -> $e');
    }
  }

  UserProfileModel? _readLocalProfile(String uid) {
    if (!kIsWeb) return null;
    try {
      final raw = web.window.localStorage.getItem('$_profileKeyPrefix$uid');
      if (raw == null || raw.isEmpty) return null;
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final profile = UserProfileModel.fromJson(map);
      if (profile.displayName.isEmpty &&
          profile.username == null &&
          profile.avatarUrl == null) {
        return null;
      }
      return profile;
    } catch (_) {
      return null;
    }
  }

  void _saveLocalPrefs(String uid, UserPreferencesModel p) {
    if (!kIsWeb) return;
    try {
      web.window.localStorage.setItem('$_prefsKeyPrefix$uid', jsonEncode(p.toLocalMap()));
    } catch (e) {
      debugPrint('UserProfile: save local prefs failed -> $e');
    }
  }

  UserPreferencesModel? _readLocalPrefs(String uid) {
    if (!kIsWeb) return null;
    try {
      final raw = web.window.localStorage.getItem('$_prefsKeyPrefix$uid');
      if (raw == null || raw.isEmpty) return null;
      return UserPreferencesModel.fromMap(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  void _clearLocalProfile(String uid) {
    if (!kIsWeb) return;
    web.window.localStorage.removeItem('$_profileKeyPrefix$uid');
  }

  void _clearLocalPrefs(String uid) {
    if (!kIsWeb) return;
    web.window.localStorage.removeItem('$_prefsKeyPrefix$uid');
  }

  /// Carry over the pre-2026 local settings (name/email/bio) so nothing the
  /// user typed in the old Settings page is thrown away.
  void _seedFromLegacySettings() {
    if (!kIsWeb) return;
    try {
      final raw = web.window.localStorage.getItem('waflo.settings.v1');
      if (raw == null || raw.isEmpty) return;
      _legacyMap = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      _legacyMap = const {};
    }
  }

  Map<String, dynamic> _legacyMap = const {};

  String? get _legacyName {
    final v = _legacyMap['name'];
    return v is String && v.trim().isNotEmpty ? v.trim() : null;
  }

  String? get _legacyBio {
    final v = _legacyMap['bio'];
    return v is String && v.trim().isNotEmpty ? v.trim() : null;
  }
}