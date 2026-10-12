import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../models/maintenance_order.dart';
import '../../widgets/common.dart';

Color maintenanceStatusColor(MaintenanceStatus s) {
  switch (s) {
    case MaintenanceStatus.open:
      return AppColors.primary;
    case MaintenanceStatus.inProgress:
      return AppColors.warning;
    case MaintenanceStatus.done:
      return AppColors.running;
    case MaintenanceStatus.cancelled:
      return AppColors.muted;
  }
}

class MaintenanceTile extends StatelessWidget {
  const MaintenanceTile({super.key, required this.order, this.compact = false});

  final MaintenanceOrder order;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final o = order;
    final theme = Theme.of(context);
    final statusColor = maintenanceStatusColor(o.status);
    return ListTile(
      dense: compact,
      onTap: () => context.go('/maintenance/${o.id}'),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(color: priorityColor(o.priority).withValues(alpha: 0.16), borderRadius: BorderRadius.circular(10)),
        child: Icon(Icons.build_outlined, color: priorityColor(o.priority), size: 20),
      ),
      title: Text('${o.code} · ${o.title}', maxLines: compact ? 1 : 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Wrap(
        spacing: 8,
        children: [
          if (o.equipmentTag != null) Text(o.equipmentTag!, style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700)),
          Text('${titleCase(o.priority.name)} priority', style: theme.textTheme.bodySmall?.copyWith(color: priorityColor(o.priority))),
          if (o.assignedToName != null) Text(o.assignedToName!, style: theme.textTheme.bodySmall),
          if (o.scheduledFor != null) Text('due ${fmtRelative(o.scheduledFor)}', style: theme.textTheme.bodySmall),
        ],
      ),
      trailing: StatusChip(label: maintenanceStatusLabel(o.status), color: statusColor, dense: true),
    );
  }
}
