import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthRetryableFetchException;

import '../../core/security.dart';
import '../../core/theme.dart';
import '../../services/auth_service.dart';

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

/// Neutral notice (e.g. "You were signed out after a period of inactivity.").
class AuthInfoBox extends StatelessWidget {
  const AuthInfoBox(this.message, {super.key});

  final String? message;

  @override
  Widget build(BuildContext context) {
    if (message == null) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: AppColors.primary, size: 18),
          const SizedBox(width: 10),
          Expanded(child: Text(message!, style: const TextStyle(fontSize: 13))),
        ],
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

/// Maps authentication errors to fixed, non-revealing messages. Raw server
/// messages are never shown: every credential problem reads the same, so the
/// page does not disclose whether an account exists or is confirmed.
String friendlyAuthError(Object error) {
  final text = error.toString();
  final lower = text.toLowerCase();
  if (text.contains(AuthService.wrongCurrentPasswordMessage)) return '${AuthService.wrongCurrentPasswordMessage}.';
  if (lower.contains('socketexception') ||
      lower.contains('failed host lookup') ||
      lower.contains('clientexception') ||
      lower.contains('xmlhttprequest') ||
      error is AuthRetryableFetchException) {
    return 'Cannot reach the authentication server. Check your connection.';
  }
  if (lower.contains('rate limit') || lower.contains('too many') || lower.contains('over_request_rate_limit')) {
    return 'Too many attempts. Please wait a moment and try again.';
  }
  if (lower.contains('invalid login credentials') ||
      lower.contains('invalid_credentials') ||
      lower.contains('user not found') ||
      lower.contains('user_not_found') ||
      lower.contains('email not confirmed') ||
      lower.contains('email_not_confirmed') ||
      lower.contains('invalid_grant')) {
    return 'Incorrect e-mail or password.';
  }
  if (lower.contains('password should be') || lower.contains('weak_password')) {
    return 'The password does not meet the policy. $passwordPolicyHint.';
  }
  if (lower.contains('same password') || lower.contains('same_password')) {
    return 'The new password must be different from the old one.';
  }
  if (lower.contains('session') && (lower.contains('expired') || lower.contains('missing'))) {
    return 'Your session expired. Please sign in again.';
  }
  return 'Sign-in failed. Please try again.';
}
