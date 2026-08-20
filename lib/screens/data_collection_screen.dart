import 'package:flutter/material.dart';

import '../audio/collection_label.dart';
import '../audio/data_collection_controller.dart';
import '../theme/design_tokens.dart';
import '../widgets/app_card.dart';

/// Live event-tagging screen for building classifier training data: tap a
/// label while recording and a ready-to-train clip is saved immediately
/// (see [DataCollectionController] for the rolling-buffer/auto-trim
/// mechanics) -- no separate post-hoc labeling pass needed.
class DataCollectionScreen extends StatefulWidget {
  const DataCollectionScreen({super.key, required this.controller});

  final DataCollectionController controller;

  @override
  State<DataCollectionScreen> createState() => _DataCollectionScreenState();
}

class _DataCollectionScreenState extends State<DataCollectionScreen> {
  String? _error;

  Future<void> _toggleCapture() async {
    setState(() => _error = null);
    try {
      if (widget.controller.isCapturing) {
        await widget.controller.stop();
      } else {
        await widget.controller.start();
      }
      setState(() {});
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  @override
  void dispose() {
    if (widget.controller.isCapturing) {
      widget.controller.stop();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final capturing = widget.controller.isCapturing;

    return Scaffold(
      appBar: AppBar(title: const Text('Data Collection')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ElevatedButton(
              key: const Key('captureToggleButton'),
              onPressed: _toggleCapture,
              child: Text(capturing ? 'Stop' : 'Start'),
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.md),
              Text(_error!, key: const Key('errorText'), style: AppTypography.errorText),
            ],
            const SizedBox(height: AppSpacing.xl),
            StreamBuilder<CollectionTally>(
              stream: widget.controller.tally,
              initialData: widget.controller.currentTally,
              builder: (context, snapshot) {
                final tally = snapshot.data ?? CollectionTally.empty;
                return AppCard(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final label in CollectionLabel.values) ...[
                        _LabelRow(
                          label: label,
                          count: tally.countFor(label),
                          enabled: capturing,
                          onTap: () => widget.controller.tag(label),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                      ],
                      const SizedBox(height: AppSpacing.md),
                      OutlinedButton(
                        key: const Key('undoLastButton'),
                        onPressed: tally.canUndo ? widget.controller.undoLast : null,
                        child: const Text('Undo last'),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _LabelRow extends StatelessWidget {
  const _LabelRow({
    required this.label,
    required this.count,
    required this.enabled,
    required this.onTap,
  });

  final CollectionLabel label;
  final int count;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton(
            key: Key('${label.folderName}TagButton'),
            onPressed: enabled ? onTap : null,
            child: Text(label.displayName),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Text('$count', key: Key('${label.folderName}CountText'), style: AppTypography.h2),
      ],
    );
  }
}
