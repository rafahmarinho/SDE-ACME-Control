import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// Shared layout for sign-in, password recovery and reset pages.
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({super.key, required this.title, required this.subtitle, required this.child});

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0A1020), Color(0xFF0E1B33), Color(0xFF0A1020)],
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Card(
                color: AppColors.surface,
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: AppColors.water.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.water_drop, color: AppColors.water),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('ACME Control', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                                Text(
                                  'Water treatment supervisory system',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(color: AppColors.muted),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 28),
                      Text(title, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 6),
                      Text(subtitle, style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.muted)),
                      const SizedBox(height: 24),
                      child,
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AuthErrorBox extends StatelessWidget {
  const AuthErrorBox(this.message, {super.key});

  final String? message;

  @override
  Widget build(BuildContext context) {
    if (message == null) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AppColors.danger, size: 18),
          const SizedBox(width: 10),
          Expanded(child: Text(message!, style: const TextStyle(color: AppColors.danger, fontSize: 13))),
        ],
      ),
    );
  }
}

String friendlyAuthError(Object error) {
  final text = error.toString();
  if (text.contains('Invalid login credentials')) return 'Incorrect e-mail or password.';
  if (text.contains('Email not confirmed')) return 'This e-mail address has not been confirmed yet.';
  if (text.contains('rate limit') || text.contains('Too many')) return 'Too many attempts. Please wait a moment and try again.';
  if (text.contains('SocketException') || text.contains('Failed host lookup') || text.contains('ClientException')) {
    return 'Cannot reach the authentication server. Check your connection.';
  }
  if (text.contains('Password should be')) return 'Password must be at least 6 characters.';
  if (text.contains('same password')) return 'The new password must be different from the old one.';
  return text.replaceFirst(RegExp(r'^AuthException: '), '').replaceFirst(RegExp(r'^AuthApiException: '), '').replaceFirst(RegExp(r', statusCode: .*$'), '');
}
