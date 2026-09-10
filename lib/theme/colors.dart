import 'package:flutter/material.dart';
import 'package:waflo_app/theme/app_theme.dart';

/// App-wide color palette. These are dynamic getters backed by the currently
/// selected theme (see [AppThemeController]) so every existing call site
/// re-themes automatically when the user switches themes in Settings.
class AppColors {
  static Color get background => AppThemeController.instance.palette.background;
  static Color get surface => AppThemeController.instance.palette.surface;
  static Color get sideNav => AppThemeController.instance.palette.sideNav;
  static Color get searchBarBorder =>
      AppThemeController.instance.palette.searchBarBorder;
  static Color get iconGrey => AppThemeController.instance.palette.iconGrey;
  static Color get textGrey => AppThemeController.instance.palette.textGrey;
  static Color get footerGrey => AppThemeController.instance.palette.footerGrey;
  static Color get proButton => AppThemeController.instance.palette.proButton;
  static Color get cardColor => AppThemeController.instance.palette.cardColor;
  static Color get submitButton =>
      AppThemeController.instance.palette.accent;

  /// Primary accent color for selection highlights / CTAs.
  static Color get accent => AppThemeController.instance.palette.accent;

  /// Softer accent for translucent overlays.
  static Color get accentSoft => AppThemeController.instance.palette.accentSoft;

  /// Primary text color (white in every theme).
  static Color get textPrimary => AppThemeController.instance.palette.textPrimary;

  /// Theme-tuned success green (status dots, "completed", provider badges).
  static Color get success => AppThemeController.instance.palette.success;

  /// Theme-tuned destructive red (errors, sign out, stop actions).
  static Color get danger => AppThemeController.instance.palette.danger;

  /// Accent gradient used for glows, buttons and hero strokes.
  static List<Color> get accentGradient => [
    AppThemeController.instance.palette.accent,
    AppThemeController.instance.palette.accentSoft,
  ];

  static Color get whiteColor =>
      AppThemeController.instance.palette.textPrimary;

  // Kept for compatibility with the original const API where callers used
  // these in `const` contexts; most call sites still treat them as const
  // colors, so we keep a static const copy of the default (Midnight) values.
  static const searchBar = Color.fromRGBO(32, 34, 34, 1);
}