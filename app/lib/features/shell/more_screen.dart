import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../providers/auth_providers.dart';
import '../../providers/core_providers.dart';
import '../../widgets/common.dart';
import 'navigation.dart';

/// Mobile "More" tab: every page that is not a bottom tab, plus account actions.
class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(roleProvider);
    final profile = ref.watch(profileProvider).value;
    final tabs = mobileTabsFor(role).map((d) => d.path).toSet();
    final others = destinationsFor(role).where((d) => !tabs.contains(d.path)).toList();

    return PageBody(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            child: ListTile(
              leading: UserAvatar(initials: profile?.initials ?? '?', imageUrl: profile?.avatarUrl, radius: 22),
              title: Text(profile?.displayName ?? ''),
              subtitle: Text(profile?.role.label ?? ''),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.go('/profile'),
            ),
          ),
          const SizedBox(height: 16),
          const SectionHeader(title: 'Pages'),
          Card(
            child: Column(
              children: [
                for (final d in others)
                  ListTile(
                    leading: Icon(d.icon),
                    title: Text(d.label),
                    subtitle: d.subtitle == null ? null : Text(d.subtitle!),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.go(d.path),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const SectionHeader(title: 'Account'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.settings_outlined),
                  title: const Text('Settings'),
                  subtitle: Text(settingsDestination.subtitle!),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.go('/settings'),
                ),
                ListTile(
                  leading: const Icon(Icons.logout, color: AppColors.danger),
                  title: const Text('Sign out'),
                  onTap: () async {
                    final ok = await confirmDialog(context, title: 'Sign out', message: 'Sign out of ACME Control on this device?', confirmLabel: 'Sign out');
                    if (ok) await ref.read(authServiceProvider).signOut();
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
