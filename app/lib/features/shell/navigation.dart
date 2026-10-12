import 'package:flutter/material.dart';

import '../../models/profile.dart';

class NavDestination {
  const NavDestination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.path,
    this.visible,
    this.subtitle,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final String path;
  final String? subtitle;
  final bool Function(UserRole role)? visible;

  bool visibleFor(UserRole role) => visible?.call(role) ?? true;

  bool matches(String path) => path == this.path || path.startsWith('${this.path}/');
}

final allDestinations = <NavDestination>[
  const NavDestination(
    label: 'Overview',
    icon: Icons.dashboard_outlined,
    selectedIcon: Icons.dashboard,
    path: '/overview',
    subtitle: 'Plant KPIs, alarms and pending work',
  ),
  const NavDestination(
    label: 'Process',
    icon: Icons.account_tree_outlined,
    selectedIcon: Icons.account_tree,
    path: '/process',
    subtitle: 'Live schematic and equipment control',
  ),
  const NavDestination(
    label: 'Equipment',
    icon: Icons.precision_manufacturing_outlined,
    selectedIcon: Icons.precision_manufacturing,
    path: '/equipment',
    subtitle: 'Assets, status and details',
  ),
  const NavDestination(
    label: 'Alarms',
    icon: Icons.notifications_active_outlined,
    selectedIcon: Icons.notifications_active,
    path: '/alarms',
    subtitle: 'Active, acknowledged and cleared alarms',
  ),
  const NavDestination(
    label: 'Trends',
    icon: Icons.show_chart,
    selectedIcon: Icons.ssid_chart,
    path: '/trends',
    subtitle: 'Historical process values',
  ),
  NavDestination(
    label: 'Commands',
    icon: Icons.terminal_outlined,
    selectedIcon: Icons.terminal,
    path: '/commands',
    subtitle: 'Command log and quick actions',
    visible: (r) => r.canOperate,
  ),
  NavDestination(
    label: 'Setpoints',
    icon: Icons.tune_outlined,
    selectedIcon: Icons.tune,
    path: '/setpoints',
    subtitle: 'Control limits and change proposals',
    visible: (r) => r.canProposeSetpoints,
  ),
  const NavDestination(
    label: 'Maintenance',
    icon: Icons.build_outlined,
    selectedIcon: Icons.build,
    path: '/maintenance',
    subtitle: 'Work orders and lockouts',
  ),
  NavDestination(
    label: 'Shift handover',
    icon: Icons.swap_horiz_outlined,
    selectedIcon: Icons.swap_horiz,
    path: '/handover',
    subtitle: 'Shift reports and acknowledgements',
    visible: (r) => r.canHandover,
  ),
  NavDestination(
    label: 'Simulation',
    icon: Icons.science_outlined,
    selectedIcon: Icons.science,
    path: '/simulation',
    subtitle: 'Scenarios, time control, events and reset',
    visible: (r) => r.canSimulate,
  ),
  const NavDestination(
    label: 'Plants',
    icon: Icons.factory_outlined,
    selectedIcon: Icons.factory,
    path: '/plants',
    subtitle: 'Switch between plants',
  ),
];

const profileDestination = NavDestination(
  label: 'Profile',
  icon: Icons.person_outline,
  selectedIcon: Icons.person,
  path: '/profile',
  subtitle: 'Your name, picture and default plant',
);

const settingsDestination = NavDestination(
  label: 'Settings',
  icon: Icons.settings_outlined,
  selectedIcon: Icons.settings,
  path: '/settings',
  subtitle: 'Theme, refresh rate and confirmations',
);

const moreDestination = NavDestination(
  label: 'More',
  icon: Icons.menu,
  selectedIcon: Icons.menu_open,
  path: '/more',
);

List<NavDestination> destinationsFor(UserRole role) => allDestinations.where((d) => d.visibleFor(role)).toList();

/// Bottom tabs on phones: plant, alarms, assets and "more".
List<NavDestination> mobileTabsFor(UserRole role) {
  NavDestination byPath(String p) => allDestinations.firstWhere((d) => d.path == p);
  if (role == UserRole.maintenance) {
    return [byPath('/equipment'), byPath('/maintenance'), byPath('/alarms'), moreDestination];
  }
  return [byPath('/process'), byPath('/alarms'), byPath('/equipment'), moreDestination];
}

NavDestination? destinationForPath(String path) {
  for (final d in [...allDestinations, profileDestination, settingsDestination, moreDestination]) {
    if (d.matches(path)) return d;
  }
  return null;
}

String titleForPath(String path) {
  if (path.startsWith('/equipment/')) return 'Equipment detail';
  if (path == '/maintenance/new') return 'New work order';
  if (path.startsWith('/maintenance/')) return 'Work order';
  if (path == '/handover/new') return 'New shift handover';
  if (path.startsWith('/handover/')) return 'Shift handover';
  return destinationForPath(path)?.label ?? 'ACME Control';
}
