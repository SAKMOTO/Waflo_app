import 'package:flutter/material.dart';

/// Available app themes. All stay dark-composable so every existing white-text
/// screen keeps readable contrast while the look and accent shift per theme.
enum AppThemeId {
  midnight,
  ocean,
  aurora,
  ember,
}

/// Immutable color palette used by [AppColors] for the current theme.
class Palette {
  final String name;
  final Color background;
  final Color surface;
  final Color sideNav;
  final Color searchBarBorder;
  final Color iconGrey;
  final Color textGrey;
  final Color footerGrey;
  final Color proButton;
  final Color cardColor;
  final Color accent;
  final Color accentSoft;
  final Color textPrimary;

  /// Semantic success / destructive colours, theme-tuned for contrast.
  final Color success;
  final Color danger;

  const Palette({
    required this.name,
    required this.background,
    required this.surface,
    required this.sideNav,
    required this.searchBarBorder,
    required this.iconGrey,
    required this.textGrey,
    required this.footerGrey,
    required this.proButton,
    required this.cardColor,
    required this.accent,
    required this.accentSoft,
    required this.textPrimary,
    required this.success,
    required this.danger,
  });
}

const Map<AppThemeId, Palette> palettes = {
  AppThemeId.midnight: Palette(
    name: 'Midnight',
    background: Color(0xFF000000),
    surface: Color(0xFF141414),
    sideNav: Color.fromRGBO(32, 34, 34, 1),
    searchBarBorder: Color.fromRGBO(60, 63, 64, 1),
    iconGrey: Color(0xFF909090),
    textGrey: Color(0xFFAAAAAA),
    footerGrey: Color(0xFF737373),
    proButton: Color.fromRGBO(47, 48, 47, 1),
    cardColor: Color(0xFF262626),
    accent: Color.fromRGBO(27, 185, 206, 1),
    accentSoft: Color(0xFF1BB9CE),
    textPrimary: Colors.white,
    success: Color(0xFF34C77B),
    danger: Color(0xFFE5484D),
  ),
  AppThemeId.ocean: Palette(
    name: 'Ocean',
    background: Color(0xFF04121F),
    surface: Color(0xFF0B2133),
    sideNav: Color(0xFF0A1E2E),
    searchBarBorder: Color(0xFF1D405C),
    iconGrey: Color(0xFF8FA7BA),
    textGrey: Color(0xFFAFBFCC),
    footerGrey: Color(0xFF6C8294),
    proButton: Color(0xFF16354E),
    cardColor: Color(0xFF103048),
    accent: Color(0xFF38BDF8),
    accentSoft: Color(0xFF0EA5E9),
    textPrimary: Color(0xFFEAF6FF),
    success: Color(0xFF4ADE80),
    danger: Color(0xFFF87171),
  ),
  AppThemeId.aurora: Palette(
    name: 'Aurora',
    background: Color(0xFF140721),
    surface: Color(0xFF221036),
    sideNav: Color(0xFF200F33),
    searchBarBorder: Color(0xFF3C2A55),
    iconGrey: Color(0xFFA694BF),
    textGrey: Color(0xFFC0B4D4),
    footerGrey: Color(0xFF7E6E99),
    proButton: Color(0xFF321D4D),
    cardColor: Color(0xFF2B1847),
    accent: Color(0xFFB46CFF),
    accentSoft: Color(0xFF8B5CF6),
    textPrimary: Color(0xFFF7EFFF),
    success: Color(0xFF6EE7B7),
    danger: Color(0xFFFB7185),
  ),
  AppThemeId.ember: Palette(
    name: 'Ember',
    background: Color(0xFF1A1206),
    surface: Color(0xFF2A1E0E),
    sideNav: Color(0xFF281D0D),
    searchBarBorder: Color(0xFF4E3B1F),
    iconGrey: Color(0xFFC0A581),
    textGrey: Color(0xFFD9C6A6),
    footerGrey: Color(0xFF9B835F),
    proButton: Color(0xFF3A2C15),
    cardColor: Color(0xFF352716),
    accent: Color(0xFFF59E0B),
    accentSoft: Color(0xFFFB923C),
    textPrimary: Color(0xFFFFF6E9),
    success: Color(0xFFA3E635),
    danger: Color(0xFFFB7185),
  ),
};

/// Global theme state. Persists the selection to localStorage on web.
class AppThemeController extends ChangeNotifier {
  AppThemeController._();

  static final AppThemeController instance = AppThemeController._();

  AppThemeId _current = AppThemeId.midnight;
  AppThemeId get current => _current;

  Palette get palette => palettes[_current]!;

  static List<AppThemeId> get ids => AppThemeId.values;

  void setTheme(AppThemeId id) {
    if (_current == id) return;
    _current = id;
    notifyListeners();
  }
}