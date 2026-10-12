import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/env.dart';
import '../../core/security.dart';
import '../../core/theme.dart';
import '../../providers/core_providers.dart';
import 'auth_scaffold.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key, this.reason});

  /// Why the user landed here automatically: `idle` or `expired` (from `?reason=`).
  final String? reason;

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  String? _error;

  static const _demoAccounts = [
    ('Operator', 'operator@acme.demo'),
    ('Engineer', 'engineer@acme.demo'),
    ('Supervisor', 'supervisor@acme.demo'),
    ('Maintenance', 'maintenance@acme.demo'),
  ];

  static String? reasonMessage(String? reason) {
    switch (reason) {
      case 'idle':
        return 'You were signed out after a period of inactivity.';
      case 'expired':
        return 'Your session expired. Please sign in again.';
      default:
        return null;
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authServiceProvider).signIn(email: _email.text, password: _password.text);
      // GoRouter redirect moves to the requested page once the session exists.
    } catch (e) {
      if (mounted) setState(() => _error = friendlyAuthError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: 'Sign in',
      subtitle: 'Use your plant account to access the control room.',
      child: Form(
        key: _formKey,
        child: AutofillGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_error == null) AuthInfoBox(reasonMessage(widget.reason)),
              AuthErrorBox(_error),
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.username, AutofillHints.email],
                textInputAction: TextInputAction.next,
                maxLength: kMaxShortText,
                maxLengthEnforcement: MaxLengthEnforcement.enforced,
                buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
                decoration: const InputDecoration(labelText: 'E-mail', prefixIcon: Icon(Icons.mail_outline)),
                validator: (v) => (v == null || !v.contains('@')) ? 'Enter a valid e-mail address' : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _password,
                obscureText: _obscure,
                autofillHints: const [AutofillHints.password],
                textInputAction: TextInputAction.done,
                maxLength: kMaxPasswordLength,
                maxLengthEnforcement: MaxLengthEnforcement.enforced,
                buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
                onFieldSubmitted: (_) => _signIn(),
                decoration: InputDecoration(
                  labelText: 'Password',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    onPressed: () => setState(() => _obscure = !_obscure),
                    icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                  ),
                ),
                validator: (v) => (v == null || v.isEmpty) ? 'Enter your password' : null,
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _busy ? null : () => context.go('/forgot-password'),
                  child: const Text('Forgot password?'),
                ),
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: _busy ? null : _signIn,
                child: _busy
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Sign in'),
              ),
              // Demo shortcuts are compiled in only with --dart-define DEMO_MODE=true.
              if (Env.demoMode) ...[
                const SizedBox(height: 24),
                const Divider(),
                const SizedBox(height: 12),
                Text('Demo accounts', style: Theme.of(context).textTheme.labelLarge?.copyWith(color: AppColors.muted)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final (label, email) in _demoAccounts)
                      ActionChip(
                        label: Text(label),
                        avatar: const Icon(Icons.person_outline, size: 16),
                        onPressed: _busy
                            ? null
                            : () {
                                _email.text = email;
                                _password.text = Env.demoPassword;
                                setState(() => _error = null);
                              },
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  Env.demoPassword.isEmpty
                      ? 'Demo accounts use the password distributed with the demo environment.'
                      : 'Demo accounts share the password configured for this demo build.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.muted),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
