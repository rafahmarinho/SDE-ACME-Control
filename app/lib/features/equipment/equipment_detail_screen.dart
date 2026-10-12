import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../models/alarm.dart';
import '../../models/command.dart';
import '../../models/equipment.dart';
import '../../models/maintenance_order.dart';
import '../../providers/auth_providers.dart';
import '../../providers/live_notifiers.dart';
import '../../widgets/common.dart';
import '../../widgets/equipment_control_panel.dart';
import '../alarms/alarm_tile.dart';
import '../maintenance/maintenance_tile.dart';
import 'equipment_screen.dart';

class EquipmentDetailScreen extends ConsumerWidget {
  const EquipmentDetailScreen({super.key, required this.equipmentId});

  final String equipmentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final live = ref.watch(equipmentProvider);
    final role = ref.watch(roleProvider);
    final state = ref.watch(processStateProvider).data;
    final alarms = (ref.watch(alarmsProvider).data ?? const <Alarm>[]);
    final orders = (ref.watch(maintenanceOrdersProvider).data ?? const <MaintenanceOrder>[]);
    final commands = (ref.watch(commandsProvider).data ?? const <CommandRecord>[]);

    return LiveBuilder<List<Equipment>>(
      live: live,
      onRetry: () => ref.read(equipmentProvider.notifier).refresh(),
      builder: (context, list) {
        final e = list.where((x) => x.id == equipmentId).firstOrNull;
        if (e == null) {
          return EmptyView(
            icon: Icons.search_off,
            title: 'Equipment not found',
            action: FilledButton(onPressed: () => context.go('/equipment'), child: const Text('Back to equipment')),
          );
        }
        final related = alarms.where((a) => a.equipmentId == e.id || a.tag == e.tag).take(10).toList();
        final work = orders.where((o) => o.equipmentId == e.id).toList();
        final cmds = commands.where((c) => c.equipmentId == e.id).take(10).toList();
        final color = equipmentStateColor(e);
        final theme = Theme.of(context);
        final wide = MediaQuery.sizeOf(context).width >= 1000;

        final header = Row(
          children: [
            IconButton(onPressed: () => context.go('/equipment'), icon: const Icon(Icons.arrow_back)),
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(12)),
              child: Icon(equipmentIcon(e.type), color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${e.tag} · ${e.name}', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                  Text('${titleCase(e.type.name)} · ${e.area ?? 'No area'} · updated ${fmtRelative(e.updatedAt)}', style: theme.textTheme.bodySmall?.copyWith(color: AppColors.muted)),
                ],
              ),
            ),
            if (role.canMaintain)
              FilledButton.tonalIcon(
                onPressed: () => context.go('/maintenance/new?equipment=${e.id}'),
                icon: const Icon(Icons.add_task, size: 18),
                label: const Text('Work order'),
              ),
          ],
        );

        final controlCard = Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: e.isControllable
                ? EquipmentControlPanel(equipmentId: e.id)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(e.isTank ? 'Tank status' : 'Measurement', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 10),
                      if (e.isTank) ...[
                        InfoRow('Level', '${fmtNum(state?.tank(e.tag)?.level ?? e.position)} %'),
                        InfoRow('Volume', '${fmtNum(state?.tank(e.tag)?.volume, decimals: 1)} / ${fmtNum(e.capacityM3, decimals: 0)} m³'),
                        InfoRow('Inflow', '${fmtNum(state?.tank(e.tag)?.inflow)} m³/h'),
                        InfoRow('Outflow', '${fmtNum(state?.tank(e.tag)?.outflow)} m³/h'),
                      ],
                      if (e.isSensor) ...[
                        InfoRow('Value', '${fmtNum(state?.value(e.tag), decimals: 2)} ${e.unit}'),
                        InfoRow('Quality', state?.isFaulted(e.tag) == true ? 'BAD - signal fault' : 'Good', valueColor: state?.isFaulted(e.tag) == true ? AppColors.danger : AppColors.running),
                        InfoRow('Range', '${e.params['min']} – ${e.params['max']} ${e.unit}'),
                      ],
                      if (e.underMaintenance) const Padding(padding: EdgeInsets.only(top: 8), child: StatusChip(label: 'Under maintenance', color: AppColors.maintenance)),
                      if (role.canMaintain) ...[
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: () => setEquipmentMaintenance(context, ref, equipment: e, underMaintenance: !e.underMaintenance),
                          icon: const Icon(Icons.build_outlined, size: 18),
                          label: Text(e.underMaintenance ? 'Return to service' : 'Lock out for maintenance'),
                        ),
                      ],
                    ],
                  ),
          ),
        );

        final paramsCard = Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Parameters', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                for (final entry in e.params.entries) InfoRow(titleCase(entry.key.replaceAll('_m3h', ' (m³/h)').replaceAll('_bar', ' (bar)').replaceAll('_m3', ' (m³)').replaceAll('_s', ' (s)').replaceAll('_kw', ' (kW)').replaceAll('_m', ' (m)')), '${entry.value}'),
                if (e.isPump) ...[
                  InfoRow('Runtime', fmtHours(e.runtimeHours)),
                  InfoRow('Start count', '${e.startsCount}'),
                ],
              ],
            ),
          ),
        );

        final alarmsCard = Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(padding: const EdgeInsets.fromLTRB(18, 16, 18, 4), child: Text('Alarms', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
              if (related.isEmpty) const Padding(padding: EdgeInsets.fromLTRB(18, 8, 18, 18), child: Text('No alarms for this equipment.')),
              for (final a in related) AlarmTile(alarm: a, compact: true),
            ],
          ),
        );

        final workCard = Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(padding: const EdgeInsets.fromLTRB(18, 16, 18, 4), child: Text('Work orders', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
              if (work.isEmpty) const Padding(padding: EdgeInsets.fromLTRB(18, 8, 18, 18), child: Text('No work orders for this equipment.')),
              for (final o in work) MaintenanceTile(order: o, compact: true),
            ],
          ),
        );

        final commandsCard = Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(padding: const EdgeInsets.fromLTRB(18, 16, 18, 4), child: Text('Recent commands', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
              if (cmds.isEmpty) const Padding(padding: EdgeInsets.fromLTRB(18, 8, 18, 18), child: Text('No commands yet.')),
              for (final c in cmds)
                ListTile(
                  dense: true,
                  leading: Icon(Icons.terminal_outlined, color: commandStatusColor(c.status.name), size: 20),
                  title: Text('${c.label} · ${c.userName ?? 'unknown'}'),
                  subtitle: Text('${fmtDateTimeSeconds(c.createdAt)}${c.reason != null ? ' · ${c.reason}' : ''}', maxLines: 2, overflow: TextOverflow.ellipsis),
                  trailing: StatusChip(label: titleCase(c.status.name), color: commandStatusColor(c.status.name), dense: true),
                ),
            ],
          ),
        );

        return PageBody(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              header,
              const SizedBox(height: 12),
              StaleNotice(live),
              if (wide)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 5, child: Column(children: [controlCard, const SizedBox(height: 14), paramsCard])),
                    const SizedBox(width: 14),
                    Expanded(flex: 4, child: Column(children: [alarmsCard, const SizedBox(height: 14), workCard, const SizedBox(height: 14), commandsCard])),
                  ],
                )
              else ...[
                controlCard,
                const SizedBox(height: 14),
                paramsCard,
                const SizedBox(height: 14),
                alarmsCard,
                const SizedBox(height: 14),
                workCard,
                const SizedBox(height: 14),
                commandsCard,
              ],
            ],
          ),
        );
      },
    );
  }
}
