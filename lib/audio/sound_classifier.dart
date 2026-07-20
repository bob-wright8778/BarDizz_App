import 'classifier_model.dart';

/// One decision tree from the exported RandomForest ensemble, as parallel
/// per-node arrays -- index `i` across every list describes node `i`.
/// [left]/[right] are child node indices; a leaf has `left[i] == -1` (no
/// children) and a [classProbabilities] entry (that leaf's normalized
/// per-class vector, indexed against [classifierClassLabels]). An internal
/// node's [classProbabilities] entry is the empty list -- it's never read,
/// since traversal only stops at leaves.
class ClassifierTree {
  const ClassifierTree({
    required this.feature,
    required this.threshold,
    required this.left,
    required this.right,
    required this.classProbabilities,
  });

  final List<int> feature;
  final List<double> threshold;
  final List<int> left;
  final List<int> right;
  final List<List<double>> classProbabilities;
}

/// Walks one [tree] from its root to a leaf for [features] -- sklearn's own
/// split rule (`feature value <= threshold` goes left, else right).
List<double> _leafProbabilities(ClassifierTree tree, List<double> features) {
  var node = 0;
  while (tree.left[node] != -1) {
    node = features[tree.feature[node]] <= tree.threshold[node]
        ? tree.left[node]
        : tree.right[node];
  }
  return tree.classProbabilities[node];
}

/// Soft-vote class probabilities across [trees] -- the mean of every tree's
/// leaf probability vector, matching
/// `RandomForestClassifier.predict_proba`'s own averaging so the Dart and
/// Python models agree exactly (mod floating-point summation order).
///
/// Inputs: [features] a feature vector matching [classifierFeatureNames]'s
/// order; [trees] the ensemble; [classLabels] the label each probability
/// column corresponds to (must be the same order the trees were built with).
/// Outputs: a [classLabels]-length probability vector.
List<double> classifyProbabilities(
  List<double> features,
  List<ClassifierTree> trees,
  List<String> classLabels,
) {
  final totals = List<double>.filled(classLabels.length, 0.0);
  for (final tree in trees) {
    final leafProbs = _leafProbabilities(tree, features);
    for (var c = 0; c < totals.length; c++) {
      totals[c] += leafProbs[c];
    }
  }
  for (var c = 0; c < totals.length; c++) {
    totals[c] /= trees.length;
  }
  return totals;
}

/// Classifies [features] via [classifyProbabilities], picking the
/// highest-probability label -- first-max-wins on a tie, matching numpy's
/// `argmax` (the same tie-break `RandomForestClassifier.predict()` relies
/// on internally).
String classifyLabel(
  List<double> features,
  List<ClassifierTree> trees,
  List<String> classLabels,
) {
  final probabilities = classifyProbabilities(features, trees, classLabels);
  var bestIndex = 0;
  for (var i = 1; i < probabilities.length; i++) {
    if (probabilities[i] > probabilities[bestIndex]) bestIndex = i;
  }
  return classLabels[bestIndex];
}

/// Classifies one [classifierFeatureNames]-ordered feature vector into a
/// sound-event label via the exported [classifierTrees] ensemble.
///
/// Inputs: [features] an 8-value feature vector
/// (`classifier_features.dart`'s `extractClassifierFeatures` order).
/// Outputs: one of [classifierClassLabels].
String classifySound(List<double> features) =>
    classifyLabel(features, classifierTrees, classifierClassLabels);
