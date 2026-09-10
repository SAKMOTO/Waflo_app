import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:waflo_app/theme/app_theme.dart';
import 'package:web/web.dart' as web;

/// User-editable account / information store. Persists to localStorage on web
/// so customizations survive relaunches; degrades to in-memory elsewhere.
class AppSettingsController extends ChangeNotifier {
  AppSettingsController._() {
    _load();
  }

  static final AppSettingsController instance = AppSettingsController._();

  static const _storageKey = 'waflo.settings.v1';

  String _displayName = '';
  String _email = '';
  String _bio = '';
  String _role = 'Creator';

  String get displayName => _displayName;
  String get email => _email;
  String get bio => _bio;
  String get role => _role;

  /// Display name, falling back to a friendly placeholder.
  String get greetingName =>
      _displayName.trim().isEmpty ? 'Creator' : _displayName.trim();

  void updateAccount({
    String name = '',
    String email = '',
    String bio = '',
    String role = '',
  }) {
    _displayName = name;
    _email = email;
    _bio = bio;
    if (role.isNotEmpty) _role = role;
    _save();
    notifyListeners();
  }

  void _load() {
    try {
      final raw = _readStorage();
      if (raw == null || raw.isEmpty) return;
      final map = jsonDecode(raw) as Map<String, dynamic>;
      _displayName = (map['name'] as String?) ?? '';
      _email = (map['email'] as String?) ?? '';
      _bio = (map['bio'] as String?) ?? '';
      _role = (map['role'] as String?) ?? 'Creator';
      final theme = map['theme'] as String?;
      if (theme != null) {
        for (final t in AppThemeId.values) {
          if (t.name == theme) {
            AppThemeController.instance.setTheme(t);
          }
        }
      }
    } catch (e) {
      debugPrint('AppSettings: load failed -> $e');
    }
  }

  void _save() {
    try {
      final map = {
        'name': _displayName,
        'email': _email,
        'bio': _bio,
        'role': _role,
        'theme': AppThemeController.instance.current.name,
      };
      if (!kIsWeb) return;
      web.window.localStorage.setItem(_storageKey, jsonEncode(map));
    } catch (e) {
      debugPrint('AppSettings: save failed -> $e');
    }
  }

  String? _readStorage() {
    if (!kIsWeb) return null;
    return web.window.localStorage.getItem(_storageKey);
  }

  /// Saves the currently active theme (kept in sync with the theme picker).
  void persistTheme(AppThemeId id) {
    AppThemeController.instance.setTheme(id);
    _save();
    notifyListeners();
  }
}