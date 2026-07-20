import 'package:flutter_test/flutter_test.dart';
import 'package:hockey_shot_tracker/audio/sound_classifier.dart';

// A single-node tree that always predicts 'a' -- no split, just a leaf at
// node 0 (left[0] == -1 marks it a leaf; feature/threshold are unused).
ClassifierTree _leafTree(List<double> probabilities) => ClassifierTree(
  feature: [-2],
  threshold: [-2.0],
  left: [-1],
  right: [-1],
  classProbabilities: [probabilities],
);

// A two-way split on feature 0 at threshold 5.0: <=5.0 goes to a leaf
// predicting 'a', >5.0 goes to a leaf predicting 'b'.
final _splitTree = ClassifierTree(
  feature: [0, -2, -2],
  threshold: [5.0, -2.0, -2.0],
  left: [1, -1, -1],
  right: [2, -1, -1],
  classProbabilities: [
    <double>[],
    [1.0, 0.0],
    [0.0, 1.0],
  ],
);

void main() {
  const labels = ['a', 'b'];

  group('classifyProbabilities', () {
    test('a single leaf tree returns its own probabilities unchanged', () {
      final probs = classifyProbabilities([0.0], [_leafTree([0.3, 0.7])], labels);
      expect(probs, [0.3, 0.7]);
    });

    test('a split tree routes left when the feature is at or below threshold', () {
      final probs = classifyProbabilities([5.0], [_splitTree], labels);
      expect(probs, [1.0, 0.0]);
    });

    test('a split tree routes right when the feature is above threshold', () {
      final probs = classifyProbabilities([5.1], [_splitTree], labels);
      expect(probs, [0.0, 1.0]);
    });

    test('averages probabilities across multiple trees', () {
      final trees = [_leafTree([1.0, 0.0]), _leafTree([0.0, 1.0])];
      final probs = classifyProbabilities([0.0], trees, labels);
      expect(probs[0], closeTo(0.5, 0.0001));
      expect(probs[1], closeTo(0.5, 0.0001));
    });
  });

  group('classifyLabel', () {
    test('picks the highest-probability label', () {
      final label = classifyLabel([5.1], [_splitTree], labels);
      expect(label, 'b');
    });

    test('first-max-wins on an exact tie, matching numpy argmax', () {
      final label = classifyLabel([0.0], [_leafTree([0.5, 0.5])], labels);
      expect(label, 'a');
    });
  });

  group('classifySound against real held-out manifest clips', () {
    // Feature vectors + expected labels below are
    // extract_dart_features(...)/model.predict(...) output from the
    // ticket-01 checkpoint's trained RandomForestClassifier
    // (tool/ml_investigation/train_dart_classifier.py) on real held-out
    // clips from tool/ml_investigation/manifest.csv, spot-checking that this
    // exported classifierTrees/classifierClassLabels agree with Python
    // exactly, not just on synthetic fixtures. bar-hit's two clips are
    // expected to mismatch their true label -- ticket01-implementation.md
    // documents the Dart-feature classifier's bar-hit regression (0/2 held
    // out) as a real, low-confidence-sample (n=2) finding, not a bug here.
    const cases = [
      (
        'jul_17_at_10_34_am_6__2.326-2.920__0020.wav (true: shot)',
        [0.4146185571, 0.0006159027, 0.2992062188, 0.1821447436, 0.0872025266, 0.0162120512, 0.1290249739, 0.3766179101],
        'shot',
      ),
      (
        'jul_17_at_10_34_am__0.234-0.833__0026.wav (true: shot)',
        [0.0863621893, 0.2225618229, 0.5367705103, 0.0208443442, 0.0114622366, 0.1219988967, 0.1107265527, 0.3580298445],
        'shot',
      ),
      (
        'jul_17_at_10_34_am_6__0.000-2.326__0021.wav (true: background-quiet)',
        [0.0342694575, 0.6018147322, 0.2512299911, 0.1095547341, 0.0008073512, 0.0023237338, 0.1229974316, 0.1406153433],
        'background-quiet',
      ),
      (
        'jul_17_at_10_34_am_6__2.920-3.850__0022.wav (true: background-quiet)',
        [0.6296083178, 0.2192021012, 0.0166946334, 0.1008126727, 0.0026460541, 0.0310362209, 0.0465237114, 0.1922684965],
        'background-quiet',
      ),
      (
        'jul_17_at_10_32_am_1__1.708-2.200__0158.wav (true: bar-hit, predicted shot -- documented regression)',
        [0.2461577232, 0.3350395199, 0.1030579007, 0.1951121182, 0.1088055257, 0.0118272123, 0.1442357708, 0.2665480879],
        'shot',
      ),
      (
        'jul_17_at_10_32_am_1__full__0234.wav (true: bar-hit, predicted stick-handling -- documented regression)',
        [0.7915282955, 0.1077055167, 0.0018922409, 0.0857563966, 0.013067261, 0.0000502893, 0.1038635886, 0.1891372586],
        'stick-handling',
      ),
      (
        'jul_18_at_6_52_pm__12.135-12.693__0180.wav (true: eww)',
        [0.9863155784, 0.0028186856, 0.0092922517, 0.0012262793, 0.0002885573, 0.0000586477, 0.2530234426, 0.0881595161],
        'eww',
      ),
      (
        'jul_18_at_6_47_pm__full__0205.wav (true: stick-handling, predicted background-quiet)',
        [0.1242918135, 0.2568887915, 0.1995827718, 0.0866422317, 0.0531751034, 0.2794192881, 0.0660598624, 0.2319317719],
        'background-quiet',
      ),
      (
        'jul_18_at_6_47_pm__full__0206.wav (true: stick-handling)',
        [0.7708310777, 0.0968369126, 0.1063767631, 0.0073618397, 0.0048909973, 0.0137024095, 0.0544862028, 0.2095297621],
        'stick-handling',
      ),
    ];

    for (final (description, features, expectedLabel) in cases) {
      test('$description matches the Python model', () {
        expect(classifySound(features), expectedLabel);
      });
    }
  });
}
