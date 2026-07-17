import 'package:flutter/material.dart';

import '../theme/design_tokens.dart';

/// A design-system card surface: [AppColors.cardSurface] fill, [AppRadius.lg]
/// corners, [AppElevation.level2] shadow. Shadow lives on an outer, colorless
/// [Container]; the fill lives on an inner [Material] so interactive
/// descendants (e.g. [ListTile]) paint their own background/ink correctly.
class AppCard extends StatelessWidget {
  const AppCard({super.key, required this.child, this.padding, this.width});

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double? width;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: AppElevation.level2,
      ),
      child: Material(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        clipBehavior: Clip.antiAlias,
        child: padding == null ? child : Padding(padding: padding!, child: child),
      ),
    );
  }
}
