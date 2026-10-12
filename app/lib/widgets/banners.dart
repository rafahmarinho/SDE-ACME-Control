import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/theme.dart';
import '../providers/connectivity_providers.dart';
import '../providers/live_notifiers.dart';
import '../providers/settings_providers.dart';

class _Banner extends StatelessWidget {
  const _Banner({required this.color, required this.icon, required this.text, this.action, this.actionLabel});

  final Color color;
  final IconData icon;
  final String text;
  final VoidCallback? action;
  final String? actionLabel;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.16),
      child: InkWell(
        onTap: action,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 10),
              Expanded(child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 13))),
              if (action != null && actionLabel != null)
                Text(actionLabel!, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Offline / paused / API unreachable / critical alarm banners shown at the top of the shell.
class StatusBanners extends ConsumerWidget {
  const StatusBanners({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final online = ref.watch(connectivityProvider);
    final apiReachable = ref.watch(apiReachableProvider);
    final critical = ref.watch(criticalAlarmProvider);
    final showAlarm = ref.watch(settingsProvider).alarmBanner;

    return Column(
      children: [
        if (!online)
          const _Banner(
            color: AppColors.danger,
            icon: Icons.cloud_off_outlined,
            text: 'Offline - showing the latest saved data. Control actions are disabled until the connection returns.',
          ),
        if (online && !apiReachable)
          const _Banner(
            color: AppColors.warning,
            icon: Icons.api_outlined,
            text: 'Control API unreachable - the process is not advancing and commands cannot be sent.',
          ),
        if (showAlarm && critical != null)
          _Banner(
            color: AppColors.critical,
            icon: Icons.warning_amber_rounded,
            text: 'CRITICAL: ${critical.message}',
            action: () => context.go('/alarms'),
            actionLabel: 'View alarms',
          ),
      ],
    );
  }
}
