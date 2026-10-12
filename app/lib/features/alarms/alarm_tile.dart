import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../models/alarm.dart';
import '../../providers/auth_providers.dart';
import '../../providers/connectivity_providers.dart';
import '../../providers/core_providers.dart';
import '../../widgets/common.dart';

Future<void> acknowledgeAlarm(BuildContext context, WidgetRef ref, Alarm alarm) async {
  final profile = ref.read(profileProvider).value;
  if (profile == null) return;
  if (!ref.read(connectivityProvider)) {
    showSnack(context, 'Acknowledging alarms requires a connection.', error: true);
    return;
  }
  try {
    await ref.read(alarmRepositoryProvider).acknowledge(alarm.id, userId: profile.id, userName: profile.displayName);
    if (context.mounted) showSnack(context, 'Alarm ${alarm.code} acknowledged', success: true);
  } catch (e) {
    if (context.mounted) showSnack(context, describeError(e), error: true);
  }
}

class AlarmTile extends ConsumerWidget {
  const AlarmTile({super.key, required this.alarm, this.compact = false});

  final Alarm alarm;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(roleProvider);
    final color = severityColor(alarm.severity);
    final theme = Theme.of(context);
    final stateColor = switch (alarm.state) {
      AlarmState.active => AppColors.danger,
      AlarmState.acknowledged => AppColors.warning,
      AlarmState.cleared => AppColors.muted,
    };
    return ListTile(
      dense: compact,
      leading: SeverityDot(alarm.severity, size: compact ? 10 : 12),
      title: Text(
        alarm.message,
        maxLines: compact ? 1 : 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontWeight: alarm.isActive ? FontWeight.w600 : FontWeight.w400, color: alarm.state == AlarmState.cleared ? theme.colorScheme.onSurfaceVariant : null),
      ),
      subtitle: Wrap(
        spacing: 8,
        runSpacing: 2,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text('${alarm.code} · ${severityLabel(alarm.severity)}', style: TextStyle(fontSize: 11, color: color)),
          Text(fmtDateTimeSeconds(alarm.raisedAt), style: const TextStyle(fontSize: 11)),
          if (!compact && alarm.ackedAt != null) Text('ack ${alarm.ackedByName ?? ''} ${fmtTimeShort(alarm.ackedAt)}', style: const TextStyle(fontSize: 11)),
          if (!compact && alarm.clearedAt != null) Text('cleared ${fmtTimeShort(alarm.clearedAt)}', style: const TextStyle(fontSize: 11)),
        ],
      ),
      trailing: alarm.isActive && role.canOperate
          ? (compact
              ? IconButton(tooltip: 'Acknowledge', icon: const Icon(Icons.check, size: 20), onPressed: () => acknowledgeAlarm(context, ref, alarm))
              : FilledButton.tonal(onPressed: () => acknowledgeAlarm(context, ref, alarm), child: const Text('Ack')))
          : StatusChip(label: titleCase(alarm.state.name), color: stateColor, dense: true, outlined: true),
    );
  }
}
