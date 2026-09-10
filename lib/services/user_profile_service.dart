import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/user_preferences_model.dart';
import '../models/user_profile_model.dart';
import 'supabase_service.dart';

/// All Supabase reads/writes for the signed-in user's profile, preferences
/// and avatar uploads. Every method is defensive in the same spirit as
/// [ChatHistoryService]: it returns null/false/empty on any failure so the
/// Settings / Profile UI degrades to the local mirror instead of crashing.
///
/// The `profiles` / `user_preferences` tables and the `avatars` bucket come
/// from `supabase/migrations/0002_profiles_preferences.sql`. Until that file
/// has been applied to the project, these methods simply report failure and
/// [UserProfileController] keeps everything in localStorage — so the app is
/// fully functional either way.
class UserProfileService {
  static SupabaseClient get _client => Supabase.instance.client;

  /// Profile writes only make sense behind a real (Google) account; the
  /// anonymous chat-history bootstrap must never touch these tables.
  static bool get _db => SupabaseService.ready && SupabaseService.isSignedInWithGoogle;

  // ---------------------------------------------------------------- profile

  static Future<UserProfileModel?> fetchProfile(String userId) async {
    if (!_db) return null;
    try {
      final rows = await _client
          .from('profiles')
          .select()
          .eq('id', userId)
          .limit(1);
      if (rows.isEmpty) return null;
      return UserProfileModel.fromJson(Map<String, dynamic>.from(rows.first));
    } catch (e) {
      debugLog('fetchProfile failed: $e');
      return null;
    }
  }

  static Future<UserProfileModel?> upsertProfile(UserProfileModel profile) async {
    if (!_db) return null;
    try {
      final rows = await _client
          .from('profiles')
          .upsert(profile.toDbMap())
          .select();
      if (rows.isEmpty) return null;
      return UserProfileModel.fromJson(Map<String, dynamic>.from(rows.first));
    } catch (e) {
      debugLog('upsertProfile failed: $e');
      return null;
    }
  }

  /// Case-insensitive username availability check. Returns null when the
  /// database is unreachable (the UI then skips the uniqueness gate).
  static Future<bool?> usernameExists(String username, {required String excludeUserId}) async {
    if (!_db) return null;
    try {
      final rows = await _client
          .from('profiles')
          .select('id')
          .ilike('username', username)
          .neq('id', excludeUserId)
          .limit(1);
      return rows.isNotEmpty;
    } catch (e) {
      debugLog('usernameExists failed: $e');
      return null;
    }
  }

  // ------------------------------------------------------------- preferences

  static Future<UserPreferencesModel?> fetchPreferences(String userId) async {
    if (!_db) return null;
    try {
      final rows = await _client
          .from('user_preferences')
          .select()
          .eq('id', userId)
          .limit(1);
      if (rows.isEmpty) return null;
      return UserPreferencesModel.fromMap(Map<String, dynamic>.from(rows.first));
    } catch (e) {
      debugLog('fetchPreferences failed: $e');
      return null;
    }
  }

  static Future<UserPreferencesModel?> upsertPreferences(
    String userId,
    UserPreferencesModel prefs,
  ) async {
    if (!_db) return null;
    try {
      final map = prefs.toDbMap()..['id'] = userId;
      final rows = await _client.from('user_preferences').upsert(map).select();
      if (rows.isEmpty) return null;
      return UserPreferencesModel.fromMap(Map<String, dynamic>.from(rows.first));
    } catch (e) {
      debugLog('upsertPreferences failed: $e');
      return null;
    }
  }

  // ----------------------------------------------------------------- avatars

  /// Uploads an avatar into the public `avatars` bucket at
  /// `{userId}/profile.{ext}` and returns its public URL (or null on failure).
  /// The caller decides how to fall back (the controller stores a `data:` URL
  /// locally when storage is unavailable).
  static Future<String?> uploadAvatar({
    required String userId,
    required Uint8List bytes,
    required String mimeType,
  }) async {
    if (!_db) return null;
    try {
      final ext = _extensionForMime(mimeType);
      final path = '$userId/profile.$ext';
      await _client.storage.from('avatars').upload(
            path,
            bytes,
            fileOptions: FileOptions(contentType: mimeType, upsert: true),
          );
      return _client.storage.from('avatars').getPublicUrl(path);
    } catch (e) {
      debugLog('uploadAvatar failed: $e');
      return null;
    }
  }

  /// Removes the avatar object for a user (best effort).
  static Future<bool> deleteAvatar(String userId) async {
    if (!_db) return false;
    try {
      final paths = ['$userId/profile.png', '$userId/profile.jpg', '$userId/profile.jpeg', '$userId/profile.webp'];
      await _client.storage.from('avatars').remove(paths);
      return true;
    } catch (e) {
      debugLog('deleteAvatar failed: $e');
      return false;
    }
  }

  // -------------------------------------------------------------- Google info

  /// Google profile image / Gravatar from the auth metadata (may be missing).
  static String? googleAvatarFromMetadata(Map<String, dynamic>? metadata) {
    if (metadata == null) return null;
    final url = (metadata['avatar_url'] ?? metadata['picture']) as String?;
    return (url == null || url.trim().isEmpty) ? null : url.trim();
  }

  static String _extensionForMime(String mime) {
    switch (mime) {
      case 'image/jpeg':
        return 'jpg';
      case 'image/png':
        return 'png';
      case 'image/webp':
        return 'webp';
      case 'image/gif':
        return 'gif';
      default:
        return 'png';
    }
  }

  static void debugLog(String message) {
    // ignore: avoid_print
    print('[UserProfile] $message');
  }
}