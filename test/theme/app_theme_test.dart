import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hockey_shot_tracker/theme/app_theme.dart';
import 'package:hockey_shot_tracker/theme/design_tokens.dart';

void main() {
  final theme = AppTheme.dark;

  test('is a dark theme using the design handoff page background', () {
    expect(theme.brightness, Brightness.dark);
    expect(theme.scaffoldBackgroundColor, AppColors.pageBackground);
  });

  test('color scheme maps ice blue to primary and graphite to secondary', () {
    expect(theme.colorScheme.primary, AppColors.iceBluePrimary);
    expect(theme.colorScheme.secondary, AppColors.graphiteSecondary);
    expect(theme.colorScheme.surface, AppColors.cardSurface);
    expect(theme.colorScheme.error, AppColors.error);
  });

  test('display text style uses Barlow Condensed at the handoff scale', () {
    expect(theme.textTheme.displayLarge?.fontFamily, 'Barlow Condensed');
    expect(theme.textTheme.displayLarge?.fontSize, 56);
    expect(theme.textTheme.displayLarge?.fontWeight, FontWeight.w700);
  });

  test('body text style uses Manrope', () {
    expect(theme.textTheme.bodyMedium?.fontFamily, 'Manrope');
    expect(theme.textTheme.bodyMedium?.fontSize, 16);
  });

  test('primary buttons are pill-shaped and filled with the primary accent', () {
    final style = theme.elevatedButtonTheme.style!;
    final background = style.backgroundColor!.resolve(<WidgetState>{});
    final shape = style.shape!.resolve(<WidgetState>{}) as RoundedRectangleBorder;

    expect(background, AppColors.iceBluePrimary);
    expect(shape.borderRadius, BorderRadius.circular(AppRadius.pill));
  });

  test('progress indicators fill with the primary accent on a visibly distinct track', () {
    expect(theme.progressIndicatorTheme.color, AppColors.iceBluePrimary);
    expect(theme.progressIndicatorTheme.linearTrackColor, AppColors.ink700);
    expect(theme.progressIndicatorTheme.linearTrackColor, isNot(theme.scaffoldBackgroundColor));
  });

  test('dialog input fields are distinguishable from the dialog background behind them', () {
    expect(theme.inputDecorationTheme.fillColor, AppColors.pageBackground);
    expect(theme.inputDecorationTheme.fillColor, isNot(theme.dialogTheme.backgroundColor));
  });

  test('app bar is flat and matches the page background', () {
    expect(theme.appBarTheme.backgroundColor, AppColors.pageBackground);
    expect(theme.appBarTheme.elevation, 0);
  });
}
