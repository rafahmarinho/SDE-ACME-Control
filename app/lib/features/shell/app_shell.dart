import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../models/plant.dart';
import '../../providers/auth_providers.dart';
import '../../providers/connectivity_providers.dart';
import '../../providers/core_providers.dart';
import '../../providers/live_notifiers.dart';
import '../../providers/plant_providers.dart';
import '../../providers/settings_providers.dart';
import '../../widgets/banners.dart';
import '../../widgets/common.dart';
import 'navigation.dart';

/// Breakpoints shared by the shell and the pages.
bool isMobileWidth(BuildContext context) => MediaQuery.sizeOf(context).width < 760;
bool isWideWidth(BuildContext context) => MediaQuery.sizeOf(context).width >= 1180;

class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(roleProvider);
    final path = GoRouterState.of(context).uri.path;
    final mobile = isMobileWidth(context);
    final wide = isWideWidth(context);
    final destinations = destinationsFor(role);
    final unacked = ref.watch(unacknowledgedAlarmCountProvider);

    final railIndex = destinations.indexWhere((d) => d.matches(path));
    final tabs = mobileTabsFor(role);
    var tabIndex = tabs.indexWhere((d) => d.matches(path));
    if (tabIndex < 0 && mobile) tabIndex = tabs.length - 1;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            if (!mobile) ...[
              const Icon(Icons.water_drop, color: AppColors.water, size: 22),
              const SizedBox(width: 8),
              const Text('ACME Control'),
              const SizedBox(width: 16),
              Container(width: 1, height: 22, color: AppColors.outline),
              const SizedBox(width: 16),
            ],
            Flexible(child: Text(titleForPath(path), overflow: TextOverflow.ellipsis)),
          ],
        ),
        actions: [
          const _PlantSwitcher(),
          const SizedBox(width: 4),
          if (!mobile) const _SimClock(),
          const _ConnectionChip(),
          IconButton(
            tooltip: 'Alarms',
            onPressed: () => context.go('/alarms'),
            icon: Badge(
              isLabelVisible: unacked > 0,
              label: Text('$unacked'),
              backgroundColor: AppColors.critical,
              child: const Icon(Icons.notifications_outlined),
            ),
          ),
          const _UserMenu(),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          const StatusBanners(),
          Expanded(
            child: Row(
              children: [
                if (!mobile)
                  LayoutBuilder(
                    builder: (context, constraints) => SingleChildScrollView(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minHeight: constraints.maxHeight),
                        child: IntrinsicHeight(
                          child: NavigationRail(
                            extended: wide,
                            minExtendedWidth: 200,
                            labelType: wide ? NavigationRailLabelType.none : NavigationRailLabelType.all,
                            selectedIndex: railIndex >= 0 ? railIndex : null,
                            onDestinationSelected: (i) => context.go(destinations[i].path),
                            destinations: [
                              for (final d in destinations)
                                NavigationRailDestination(
                                  icon: d.path == '/alarms'
                                      ? Badge(
                                          isLabelVisible: unacked > 0,
                                          label: Text('$unacked'),
                                          backgroundColor: AppColors.critical,
                                          child: Icon(d.icon),
                                        )
                                      : Icon(d.icon),
                                  selectedIcon: Icon(d.selectedIcon),
                                  label: Text(d.label),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                if (!mobile) const VerticalDivider(width: 1),
                Expanded(child: child),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: mobile
          ? NavigationBar(
              selectedIndex: tabIndex,
              onDestinationSelected: (i) => context.go(tabs[i].path),
              destinations: [
                for (final d in tabs)
                  NavigationDestination(
                    icon: d.path == '/alarms'
                        ? Badge(
                            isLabelVisible: unacked > 0,
                            label: Text('$unacked'),
                            backgroundColor: AppColors.critical,
                            child: Icon(d.icon),
                          )
                        : Icon(d.icon),
                    selectedIcon: Icon(d.selectedIcon),
                    label: d.path == '/process'
                        ? 'Plant'
                        : d.path == '/equipment'
                            ? 'Assets'
                            : d.label,
                  ),
              ],
            )
          : null,
    );
  }
}

class _PlantSwitcher extends ConsumerWidget {
  const _PlantSwitcher();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plants = ref.watch(plantsProvider).value ?? const <Plant>[];
    final selected = ref.watch(selectedPlantProvider);
    final mobile = isMobileWidth(context);
    if (selected == null) return const SizedBox.shrink();
    return PopupMenuButton<String>(
      tooltip: 'Switch plant',
      onSelected: (id) => ref.read(selectedPlantIdProvider.notifier).select(id),
      itemBuilder: (_) => [
        for (final p in plants)
          PopupMenuItem(
            value: p.id,
            child: Row(
              children: [
                Icon(
                  p.id == selected.id ? Icons.radio_button_checked : Icons.radio_button_off,
                  size: 18,
                  color: p.id == selected.id ? AppColors.primary : null,
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text('${p.code} · ${p.location}', style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                  ],
                ),
              ],
            ),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.outline),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.factory_outlined, size: 16),
            const SizedBox(width: 6),
            Text(mobile ? selected.code : selected.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            const Icon(Icons.arrow_drop_down, size: 18),
          ],
        ),
      ),
    );
  }
}

class _SimClock extends ConsumerWidget {
  const _SimClock();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(settingsProvider).showSimClock) return const SizedBox.shrink();
    final state = ref.watch(processStateProvider).data;
    if (state == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Tooltip(
        message: 'Simulation time · scenario ${state.scenario} · ${state.speed.toStringAsFixed(0)}x',
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(state.running ? Icons.schedule : Icons.pause_circle_outline, size: 16, color: AppColors.muted),
            const SizedBox(width: 6),
            Text(
              fmtTime(state.simTime),
              style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()], fontSize: 13, color: AppColors.muted),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConnectionChip extends ConsumerWidget {
  const _ConnectionChip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final online = ref.watch(connectivityProvider);
    final api = ref.watch(apiReachableProvider);
    final paused = ref.watch(processStateProvider).paused;
    final mobile = isMobileWidth(context);

    final Color color;
    final String label;
    final IconData icon;
    if (!online) {
      color = AppColors.danger;
      label = 'Offline';
      icon = Icons.cloud_off_outlined;
    } else if (paused) {
      color = AppColors.warning;
      label = 'Paused';
      icon = Icons.pause_circle_outline;
    } else if (!api) {
      color = AppColors.warning;
      label = 'API down';
      icon = Icons.api_outlined;
    } else {
      color = AppColors.running;
      label = 'Live';
      icon = Icons.sensors;
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: mobile ? Icon(icon, color: color, size: 20) : StatusChip(label: label, color: color, icon: icon, dense: true),
    );
  }
}

class _UserMenu extends ConsumerWidget {
  const _UserMenu();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider).value;
    final name = ref.watch(displayNameProvider);
    return PopupMenuButton<String>(
      tooltip: 'Account',
      onSelected: (value) async {
        switch (value) {
          case 'profile':
            context.go('/profile');
          case 'settings':
            context.go('/settings');
          case 'signout':
            final ok = await confirmDialog(context, title: 'Sign out', message: 'Sign out of ACME Control on this device?', confirmLabel: 'Sign out');
            if (ok) await ref.read(authServiceProvider).signOut();
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          enabled: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.text)),
              Text(profile?.role.label ?? '', style: const TextStyle(fontSize: 12, color: AppColors.muted)),
            ],
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'profile', child: ListTile(leading: Icon(Icons.person_outline), title: Text('Profile'), dense: true)),
        const PopupMenuItem(value: 'settings', child: ListTile(leading: Icon(Icons.settings_outlined), title: Text('Settings'), dense: true)),
        const PopupMenuItem(value: 'signout', child: ListTile(leading: Icon(Icons.logout), title: Text('Sign out'), dense: true)),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: UserAvatar(initials: profile?.initials ?? '?', imageUrl: profile?.avatarUrl),
      ),
    );
  }
}
