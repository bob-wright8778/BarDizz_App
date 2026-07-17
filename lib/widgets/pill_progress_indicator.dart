import 'package:flutter/material.dart';

import '../theme/design_tokens.dart';

/// A [LinearProgressIndicator] clipped to the design system's pill radius.
class PillProgressIndicator extends StatelessWidget {
  const PillProgressIndicator({super.key, this.progressKey, required this.value, this.minHeight});

  /// Inputs: [progressKey] is applied to the inner [LinearProgressIndicator]
  /// (not this wrapper), [value] and [minHeight] pass straight through.
  final Key? progressKey;
  final double? value;
  final double? minHeight;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.all(Radius.circular(AppRadius.pill)),
      child: LinearProgressIndicator(key: progressKey, value: value, minHeight: minHeight),
    );
  }
}
