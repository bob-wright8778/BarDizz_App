/// Data-collection-mode event classes -- a deliberate subset of the
/// classifier's real labels (excludes stick-handling and background-quiet,
/// see the spec's Decisions section).
enum CollectionLabel { shot, barHit, eww }

extension CollectionLabelNames on CollectionLabel {
  /// Button/UI text.
  String get displayName => switch (this) {
        CollectionLabel.shot => 'Shot',
        CollectionLabel.barHit => 'Bar-Hit',
        CollectionLabel.eww => 'Eww',
      };

  /// Folder/filename token -- also the label build_manifest.py assigns clips
  /// sourced from that folder.
  String get folderName => switch (this) {
        CollectionLabel.shot => 'shot',
        CollectionLabel.barHit => 'bar-hit',
        CollectionLabel.eww => 'eww',
      };
}
