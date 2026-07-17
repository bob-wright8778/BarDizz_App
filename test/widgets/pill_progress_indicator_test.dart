import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hockey_shot_tracker/theme/design_tokens.dart';
import 'package:hockey_shot_tracker/widgets/pill_progress_indicator.dart';

void main() {
  testWidgets('passes value/minHeight/key through to the inner LinearProgressIndicator',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PillProgressIndicator(
            progressKey: const Key('testProgress'),
            value: 0.5,
            minHeight: 20,
          ),
        ),
      ),
    );

    final bar = tester.widget<LinearProgressIndicator>(find.byKey(const Key('testProgress')));
    expect(bar.value, 0.5);
    expect(bar.minHeight, 20);
  });

  testWidgets('clips the indicator to the pill radius', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: PillProgressIndicator(value: 0.5))),
    );

    final clip = tester.widget<ClipRRect>(find.byType(ClipRRect));
    expect(clip.borderRadius, const BorderRadius.all(Radius.circular(AppRadius.pill)));
  });
}
