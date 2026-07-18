import 'package:flutter/material.dart';

import 'design_tokens.dart';

/// Builds the app's Material theme from the design tokens (dark-only —
/// the design handoff has no light variant).
class AppTheme {
  const AppTheme._();

  static final dark = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: AppColors.pageBackground,
    colorScheme: const ColorScheme(
      brightness: Brightness.dark,
      primary: AppColors.iceBluePrimary,
      onPrimary: AppColors.ink900,
      secondary: AppColors.graphiteSecondary,
      onSecondary: AppColors.ink900,
      error: AppColors.error,
      onError: AppColors.ink50,
      surface: AppColors.cardSurface,
      onSurface: AppColors.ink50,
    ),
    textTheme: const TextTheme(
      displayLarge: AppTypography.display,
      headlineLarge: AppTypography.h1,
      headlineSmall: AppTypography.h2,
      bodyLarge: AppTypography.bodyL,
      bodyMedium: AppTypography.body,
      labelLarge: AppTypography.label,
      labelSmall: AppTypography.overline,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.pageBackground,
      foregroundColor: AppColors.ink50,
      elevation: 0,
      titleTextStyle: AppTypography.h2,
    ),
    iconTheme: const IconThemeData(color: AppColors.ink200),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.iceBluePrimary,
        foregroundColor: AppColors.ink900,
        textStyle: AppTypography.label.copyWith(fontWeight: FontWeight.w700, color: AppColors.ink900),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: AppSpacing.md),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.pill)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.ink200,
        textStyle: AppTypography.label.copyWith(fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.pill)),
      ),
    ),
    // A track the same color as the page background would be invisible --
    // one step lighter so the unfilled portion stays visible.
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.iceBluePrimary,
      linearTrackColor: AppColors.ink700,
    ),
    listTileTheme: const ListTileThemeData(
      textColor: AppColors.ink50,
      iconColor: AppColors.ink200,
    ),
    // Darker than the dialog background it usually sits in, so a field
    // stays visually distinct with no border needed.
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.pageBackground,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        borderSide: BorderSide.none,
      ),
      labelStyle: AppTypography.body.copyWith(color: AppColors.ink300),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.cardSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.xl)),
    ),
  );
}
