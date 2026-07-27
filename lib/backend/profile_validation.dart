const int displayNameMaxLength = 20;

/// Outputs: the display name with leading/trailing whitespace removed.
String normalizeDisplayName(String input) => input.trim();

/// Inputs: a raw (untrimmed) candidate display name.
/// Outputs: an error message if it fails the 1-20 trimmed-char rule, else null.
String? validateDisplayName(String input) {
  final trimmed = normalizeDisplayName(input);
  if (trimmed.isEmpty) return 'Enter a display name';
  if (trimmed.length > displayNameMaxLength) {
    return 'Keep it to $displayNameMaxLength characters or fewer';
  }
  return null;
}
