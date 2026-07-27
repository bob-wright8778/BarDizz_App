import 'package:flutter/material.dart';

import '../backend/auth_controller.dart';
import '../theme/design_tokens.dart';

/// Google/GitHub OAuth entry point, embedded wherever a signed-out user
/// needs to authenticate before continuing (Friends tab, Profile tab).
class SignInGate extends StatelessWidget {
  const SignInGate({super.key, required this.controller});

  final AuthController controller;

  @override
  Widget build(BuildContext context) {
    final authenticating = controller.status == AuthStatus.authenticating;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Sign in to continue', style: AppTypography.h2),
          const SizedBox(height: AppSpacing.lg),
          if (controller.errorMessage != null) ...[
            Text(
              controller.errorMessage!,
              key: const Key('signInErrorText'),
              style: AppTypography.errorText,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          ElevatedButton(
            key: const Key('signInGoogleButton'),
            onPressed: authenticating ? null : controller.signInWithGoogle,
            child: const Text('Continue with Google'),
          ),
          const SizedBox(height: AppSpacing.md),
          ElevatedButton(
            key: const Key('signInGithubButton'),
            onPressed: authenticating ? null : controller.signInWithGithub,
            child: const Text('Continue with GitHub'),
          ),
          if (authenticating) ...[
            const SizedBox(height: AppSpacing.lg),
            const CircularProgressIndicator(key: Key('signInProgress')),
          ],
        ],
      ),
    );
  }
}
