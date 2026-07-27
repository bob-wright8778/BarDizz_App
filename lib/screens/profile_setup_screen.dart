import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../backend/auth_controller.dart';
import '../backend/avatars.dart';
import '../backend/profile_validation.dart';
import '../theme/design_tokens.dart';

/// First-sign-in and later edit-profile flow: a display name field and a
/// grid to pick one of the 24 bundled avatars.
class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({
    super.key,
    required this.controller,
    this.initialDisplayName = '',
    this.initialAvatarId,
    this.submitLabel = 'Save profile',
    this.onSaved,
  });

  final AuthController controller;
  final String initialDisplayName;
  final String? initialAvatarId;
  final String submitLabel;
  final VoidCallback? onSaved;

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  late final TextEditingController _nameController =
      TextEditingController(text: widget.initialDisplayName);
  String? _selectedAvatarId;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _selectedAvatarId = widget.initialAvatarId;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  bool get _canSave => !_saving;

  Future<void> _save() async {
    final nameError = validateDisplayName(_nameController.text);
    final avatarId = _selectedAvatarId;
    if (nameError != null || avatarId == null) {
      setState(() => _error = nameError ?? 'Choose an avatar');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.controller.saveProfile(
        displayName: normalizeDisplayName(_nameController.text),
        avatarId: avatarId,
      );
      widget.onSaved?.call();
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not save profile. Try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Set up your profile', style: AppTypography.h2),
          const SizedBox(height: AppSpacing.lg),
          TextField(
            key: const Key('displayNameField'),
            controller: _nameController,
            maxLength: displayNameMaxLength,
            decoration: const InputDecoration(labelText: 'Display name'),
          ),
          const SizedBox(height: AppSpacing.lg),
          const Text('Choose an avatar', style: AppTypography.label),
          const SizedBox(height: AppSpacing.sm),
          GridView.count(
            key: const Key('avatarGrid'),
            crossAxisCount: 6,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              for (final id in avatarIds)
                _AvatarTile(
                  avatarId: id,
                  selected: id == _selectedAvatarId,
                  onTap: () => setState(() => _selectedAvatarId = id),
                ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              _error!,
              key: const Key('profileSetupErrorText'),
              style: AppTypography.errorText,
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          ElevatedButton(
            key: const Key('saveProfileButton'),
            onPressed: _canSave ? _save : null,
            child: Text(widget.submitLabel),
          ),
        ],
      ),
    );
  }
}

class _AvatarTile extends StatelessWidget {
  const _AvatarTile({required this.avatarId, required this.selected, required this.onTap});

  final String avatarId;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: Key('avatarTile_$avatarId'),
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.all(AppSpacing.xs),
        decoration: BoxDecoration(
          border: Border.all(
            color: selected ? AppColors.iceBluePrimary : Colors.transparent,
            width: 2,
          ),
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: SvgPicture.asset(avatarAssetPath(avatarId)),
      ),
    );
  }
}
