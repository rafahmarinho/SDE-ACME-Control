import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/alarms/alarms_screen.dart';
import '../features/auth/forgot_password_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/reset_password_screen.dart';
import '../features/commands/commands_screen.dart';
import '../features/equipment/equipment_detail_screen.dart';
import '../features/equipment/equipment_screen.dart';
import '../features/handover/handover_detail_screen.dart';
import '../features/handover/handover_form_screen.dart';
import '../features/handover/handover_screen.dart';
import '../features/maintenance/maintenance_detail_screen.dart';
import '../features/maintenance/maintenance_form_screen.dart';
import '../features/maintenance/maintenance_screen.dart';
import '../features/overview/overview_screen.dart';
import '../features/plants/plants_screen.dart';
import '../features/process/process_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/setpoints/setpoints_screen.dart';
import '../features/shell/app_shell.dart';
import '../features/shell/more_screen.dart';
import '../features/shell/navigation.dart';
import '../features/simulation/simulation_screen.dart';
import '../features/trends/trends_screen.dart';
import '../providers/auth_providers.dart';
import '../providers/core_providers.dart';

/// Turns a stream into a Listenable so GoRouter re-evaluates redirects on auth changes.
class _StreamListenable extends ChangeNotifier {
  _StreamListenable(Stream<dynamic> stream) {
    _sub = stream.listen((_) => notifyListeners());
  }

  late final StreamSubscription<dynamic> _sub;

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

const authRoutes = {'/login', '/forgot-password', '/reset-password'};

final routerProvider = Provider<GoRouter>((ref) {
  final auth = ref.watch(authServiceProvider);
  final listenable = _StreamListenable(auth.onAuthStateChange);
  ref.onDispose(listenable.dispose);

  return GoRouter(
    initialLocation: '/overview',
    refreshListenable: listenable,
    debugLogDiagnostics: kDebugMode,
    redirect: (context, state) {
      final signedIn = auth.isSignedIn;
      final location = state.matchedLocation;
      final isAuthRoute = authRoutes.contains(location);

      if (!signedIn && !isAuthRoute) {
        final from = state.uri.toString();
        return from == '/' || from == '/overview' ? '/login' : '/login?from=${Uri.encodeComponent(from)}';
      }
      if (signedIn && (location == '/login' || location == '/forgot-password')) {
        final from = state.uri.queryParameters['from'];
        return (from != null && from.startsWith('/') && !authRoutes.contains(from)) ? from : '/overview';
      }
      if (signedIn) {
        final profile = ref.read(profileProvider).value;
        final destination = destinationForPath(location);
        if (profile != null && destination != null && !destination.visibleFor(profile.role)) {
          return '/overview';
        }
      }
      return null;
    },
    routes: [
      GoRoute(path: '/', redirect: (_, __) => '/overview'),
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/forgot-password', builder: (_, __) => const ForgotPasswordScreen()),
      GoRoute(path: '/reset-password', builder: (_, __) => const ResetPasswordScreen()),
      ShellRoute(
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          GoRoute(path: '/overview', builder: (_, __) => const OverviewScreen()),
          GoRoute(path: '/process', builder: (_, __) => const ProcessScreen()),
          GoRoute(
            path: '/equipment',
            builder: (_, __) => const EquipmentScreen(),
            routes: [
              GoRoute(
                path: ':id',
                builder: (_, state) => EquipmentDetailScreen(equipmentId: state.pathParameters['id']!),
              ),
            ],
          ),
          GoRoute(path: '/alarms', builder: (_, __) => const AlarmsScreen()),
          GoRoute(path: '/trends', builder: (_, __) => const TrendsScreen()),
          GoRoute(path: '/commands', builder: (_, __) => const CommandsScreen()),
          GoRoute(path: '/setpoints', builder: (_, __) => const SetpointsScreen()),
          GoRoute(
            path: '/maintenance',
            builder: (_, __) => const MaintenanceScreen(),
            routes: [
              GoRoute(
                path: 'new',
                builder: (_, state) => MaintenanceFormScreen(equipmentId: state.uri.queryParameters['equipment']),
              ),
              GoRoute(
                path: ':id',
                builder: (_, state) => MaintenanceDetailScreen(orderId: state.pathParameters['id']!),
              ),
            ],
          ),
          GoRoute(
            path: '/handover',
            builder: (_, __) => const HandoverScreen(),
            routes: [
              GoRoute(path: 'new', builder: (_, __) => const HandoverFormScreen()),
              GoRoute(
                path: ':id',
                builder: (_, state) => HandoverDetailScreen(handoverId: state.pathParameters['id']!),
              ),
            ],
          ),
          GoRoute(path: '/simulation', builder: (_, __) => const SimulationScreen()),
          GoRoute(path: '/plants', builder: (_, __) => const PlantsScreen()),
          GoRoute(path: '/profile', builder: (_, __) => const ProfileScreen()),
          GoRoute(path: '/settings', builder: (_, __) => const SettingsScreen()),
          GoRoute(path: '/more', builder: (_, __) => const MoreScreen()),
        ],
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.explore_off_outlined, size: 48),
            const SizedBox(height: 12),
            Text('Page not found: ${state.uri}'),
            const SizedBox(height: 12),
            FilledButton(onPressed: () => context.go('/overview'), child: const Text('Go to overview')),
          ],
        ),
      ),
    ),
  );
});
