import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/router.dart';
import 'core/theme.dart';
import 'providers/auth_providers.dart';
import 'providers/connectivity_providers.dart';
import 'providers/session_guard.dart';
import 'providers/settings_providers.dart';
import 'providers/sim_ticker.dart';

class AcmeControlApp extends ConsumerStatefulWidget {
  const AcmeControlApp({super.key});

  @override
  ConsumerState<AcmeControlApp> createState() => _AcmeControlAppState();
}

class _AcmeControlAppState extends ConsumerState<AcmeControlApp> with WidgetsBindingObserver {
  StreamSubscription<Uri>? _linkSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (!kIsWeb) {
      // Password-recovery links open the app through acmecontrol://auth/reset-password.
      // supabase_flutter exchanges the code for a session; we only route to the form.
      _linkSub = AppLinks().uriLinkStream.listen(_handleLink, onError: (_) {});
    }
  }

  void _handleLink(Uri uri) {
    // Only the exact password-recovery callback is honoured; any other link is ignored.
    if (uri.scheme != 'acmecontrol' || uri.host != 'auth' || uri.path != '/reset-password') return;
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) ref.read(routerProvider).go('/reset-password');
    });
  }

  @override
  void dispose() {
    _linkSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Pause background updates when the app leaves the foreground; resume on return.
    final foreground = state == AppLifecycleState.resumed || state == AppLifecycleState.inactive;
    ref.read(appForegroundProvider.notifier).set(foreground);
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    final settings = ref.watch(settingsProvider);

    // Keep the simulation ticker, the session guard (idle / absolute timeout)
    // and the sign-in bookkeeping alive for the whole app lifetime.
    ref.watch(simTickerProvider);
    ref.watch(sessionGuardProvider);
    ref.watch(signInSessionProvider.select((s) => s.userId));
    final guard = ref.read(sessionGuardProvider.notifier);

    ref.listen(authStateProvider, (previous, next) {
      final event = next.value?.event;
      if (event == AuthChangeEvent.passwordRecovery) {
        router.go('/reset-password');
      }
    });

    return MaterialApp.router(
      title: 'ACME Control',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(Brightness.light),
      darkTheme: buildAppTheme(Brightness.dark),
      themeMode: settings.themeMode,
      routerConfig: router,
      // Every tap, click or scroll counts as activity for the idle timeout.
      builder: (context, child) => Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => guard.touch(),
        onPointerSignal: (_) => guard.touch(),
        child: child ?? const SizedBox.shrink(),
      ),
    );
  }
}

/// Shown when the build was made without Supabase credentials.
class ConfigErrorApp extends StatelessWidget {
  const ConfigErrorApp({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ACME Control',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(Brightness.dark),
      home: Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.settings_suggest_outlined, size: 48, color: AppColors.warning),
                  const SizedBox(height: 16),
                  Text('Configuration required', style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  Text(message),
                  const SizedBox(height: 16),
                  const SelectableText(
                    'Copy env.example.json to env.json, fill in SUPABASE_URL, SUPABASE_ANON_KEY and API_BASE_URL, '
                    'then run:\n\nflutter run -d chrome --dart-define-from-file=env.json',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
