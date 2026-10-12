import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../models/alarm.dart';
import '../../models/equipment.dart';
import '../../models/event_entry.dart';
import '../../models/process_state.dart';
import '../../models/shift_handover.dart';
import '../../providers/auth_providers.dart';
import '../../providers/live_notifiers.dart';
import '../../providers/plant_providers.dart';
import '../../widgets/common.dart';
import '../../widgets/equipment_control_panel.dart';
import '../alarms/alarm_tile.dart';
import '../shell/app_shell.dart';

class OverviewScreen extends ConsumerWidget {
  const OverviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plant = ref.watch(selectedPlantProvider);
    final live = ref.watch(processStateProvider);
    final equipment = ref.watch(equipmentProvider).data ?? const <Equipment>[];
    final alarms = ref.watch(activeAlarmsProvider);
    final pendingSetpoints = ref.watch(pendingSetpointCountProvider);
    final openOrders = ref.watch(openMaintenanceCountProvider);
    final handovers = ref.watch(handoversProvider).data ?? const <ShiftHandover>[];
    final awaitingAck = handovers.where((h) => h.status == HandoverStatus.submitted).length;
    final events = (ref.watch(eventsProvider).data ?? const <EventEntry>[]).take(8).toList();
    final role = ref.watch(roleProvider);
    final mobile = isMobileWidth(context);

    if (plant == null) {
      return const LoadingView(message: 'Loading plants…');
    }

    return RefreshIndicator(
      onRefresh: () async => ref.read(processStateProvider.notifier).refresh(),
      child: PageBody(
        child: LiveBuilder<ProcessState>(
          live: live,
          onRetry: () => ref.read(processStateProvider.notifier).refresh(),
          builder: (context, state) {
            final t1 = state.tank('T1');
            final t2 = state.tank('T2');
            final pt3 = state.value('PT3') ?? 0;
            final tu = state.value('TU1') ?? 0;
            final tiles = <Widget>[
              KpiTile(label: 'Raw water tank T1', value: fmtNum(t1?.level), unit: '%', icon: Icons.water, color: AppColors.water, progress: (t1?.level ?? 0) / 100, subtitle: '${fmtNum(t1?.volume, decimals: 0)} of ${fmtNum(t1?.capacity, decimals: 0)} m³ · net ${fmtNum(t1?.netFlow)} m³/h', onTap: () => context.go('/process')),
              KpiTile(label: 'Treated water tank T2', value: fmtNum(t2?.level), unit: '%', icon: Icons.water, color: AppColors.water, progress: (t2?.level ?? 0) / 100, subtitle: '${fmtNum(t2?.volume, decimals: 0)} of ${fmtNum(t2?.capacity, decimals: 0)} m³ · net ${fmtNum(t2?.netFlow)} m³/h', onTap: () => context.go('/process')),
              KpiTile(label: 'Intake flow FT1', value: fmtNum(state.value('FT1')), unit: 'm³/h', icon: Icons.login, subtitle: state.conditions.sourceAvailable ? 'Source available' : 'Intake unavailable', color: state.conditions.sourceAvailable ? null : AppColors.danger),
              KpiTile(label: 'Distribution flow FT3', value: fmtNum(state.value('FT3')), unit: 'm³/h', icon: Icons.logout, subtitle: 'Demand ${fmtNum(state.conditions.demandM3h)} m³/h'),
              KpiTile(label: 'Network pressure PT3', value: fmtNum(pt3, decimals: 2), unit: 'bar', icon: Icons.speed, color: pt3 < 2.5 ? AppColors.danger : AppColors.running),
              KpiTile(label: 'Turbidity TU1', value: fmtNum(tu, decimals: 2), unit: 'NTU', icon: Icons.blur_on, color: tu > 1 ? AppColors.warning : AppColors.running),
              KpiTile(label: 'Chlorine residual CL1', value: fmtNum(state.value('CL1'), decimals: 2), unit: 'mg/L', icon: Icons.science_outlined, color: AppColors.running),
              KpiTile(label: 'Active alarms', value: '${alarms.length}', icon: Icons.notifications_active_outlined, color: alarms.any((a) => a.severity == AlarmSeverity.critical) ? AppColors.critical : alarms.isEmpty ? AppColors.running : AppColors.warning, subtitle: '${alarms.where((a) => a.isActive).length} unacknowledged', onTap: () => context.go('/alarms')),
            ];

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _PlantHeader(state: state, plantName: plant.name, location: plant.location),
                const SizedBox(height: 12),
                StaleNotice(live),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final columns = constraints.maxWidth >= 1100 ? 4 : constraints.maxWidth >= 700 ? 3 : 2;
                    return GridView.count(
                      crossAxisCount: columns,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: mobile ? 1.35 : 1.9,
                      children: tiles,
                    );
                  },
                ),
                const SizedBox(height: 20),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final twoColumns = constraints.maxWidth >= 900;
                    final left = Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SectionHeader(
                          title: 'Equipment status',
                          subtitle: 'Tap a pump or valve to operate it',
                          trailing: TextButton(onPressed: () => context.go('/equipment'), child: const Text('All equipment')),
                        ),
                        _EquipmentGrid(equipment: equipment.where((e) => e.isControllable).toList()),
                        const SizedBox(height: 20),
                        SectionHeader(
                          title: 'Pending work',
                          trailing: role.canSimulate ? TextButton(onPressed: () => context.go('/simulation'), child: const Text('Simulation')) : null,
                        ),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            _PendingTile(icon: Icons.tune, label: 'Setpoint proposals', count: pendingSetpoints, onTap: role.canProposeSetpoints ? () => context.go('/setpoints') : null),
                            _PendingTile(icon: Icons.build_outlined, label: 'Open work orders', count: openOrders, onTap: () => context.go('/maintenance')),
                            _PendingTile(icon: Icons.swap_horiz, label: 'Handovers to acknowledge', count: awaitingAck, onTap: role.canHandover ? () => context.go('/handover') : null),
                          ],
                        ),
                      ],
                    );
                    final right = Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SectionHeader(
                          title: 'Active alarms',
                          trailing: TextButton(onPressed: () => context.go('/alarms'), child: const Text('All alarms')),
                        ),
                        if (alarms.isEmpty)
                          const Card(
                            child: Padding(
                              padding: EdgeInsets.all(18),
                              child: Row(
                                children: [
                                  Icon(Icons.check_circle_outline, color: AppColors.running),
                                  SizedBox(width: 10),
                                  Text('No active alarms'),
                                ],
                              ),
                            ),
                          )
                        else
                          Card(
                            child: Column(
                              children: [
                                for (final a in alarms.take(6)) AlarmTile(alarm: a, compact: true),
                              ],
                            ),
                          ),
                        const SizedBox(height: 20),
                        SectionHeader(
                          title: 'Recent events',
                          trailing: role.canSimulate ? TextButton(onPressed: () => context.go('/simulation'), child: const Text('Inspect')) : null,
                        ),
                        Card(
                          child: events.isEmpty
                              ? const Padding(padding: EdgeInsets.all(18), child: Text('No events yet'))
                              : Column(children: [for (final e in events) EventTile(event: e)]),
                        ),
                      ],
                    );
                    if (!twoColumns) {
                      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [left, const SizedBox(height: 20), right]);
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 5, child: left),
                        const SizedBox(width: 20),
                        Expanded(flex: 4, child: right),
                      ],
                    );
                  },
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _PlantHeader extends StatelessWidget {
  const _PlantHeader({required this.state, required this.plantName, required this.location});

  final ProcessState state;
  final String plantName;
  final String location;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      runSpacing: 8,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(plantName, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
            Text(location, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
        ),
        StatusChip(label: 'Scenario: ${titleCase(state.scenario)}', color: AppColors.primary, icon: Icons.science_outlined),
        StatusChip(
          label: state.running ? 'Simulation ${state.speed.toStringAsFixed(0)}x' : 'Simulation paused',
          color: state.running ? AppColors.running : AppColors.warning,
          icon: state.running ? Icons.play_arrow : Icons.pause,
        ),
        StatusChip(label: 'Sim time ${fmtDateTimeSeconds(state.simTime)}', color: AppColors.muted, icon: Icons.schedule),
      ],
    );
  }
}

class _EquipmentGrid extends ConsumerWidget {
  const _EquipmentGrid({required this.equipment});

  final List<Equipment> equipment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final e in equipment)
          SizedBox(
            width: 170,
            child: Card(
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => showEquipmentControlSheet(context, e),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(width: 10, height: 10, decoration: BoxDecoration(shape: BoxShape.circle, color: equipmentStateColor(e))),
                          const SizedBox(width: 8),
                          Text(e.tag, style: const TextStyle(fontWeight: FontWeight.w800)),
                          const Spacer(),
                          Text(e.isAuto ? 'AUTO' : 'MAN', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: e.isAuto ? AppColors.muted : AppColors.warning)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(e.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                      const SizedBox(height: 6),
                      Text(
                        e.underMaintenance ? 'Maintenance' : e.actualLabel,
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: equipmentStateColor(e)),
                      ),
                      if (!e.inSync && !e.underMaintenance)
                        Text('requested: ${e.requestedLabel}', style: const TextStyle(fontSize: 11, color: AppColors.warning)),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _PendingTile extends StatelessWidget {
  const _PendingTile({required this.icon, required this.label, required this.count, this.onTap});

  final IconData icon;
  final String label;
  final int count;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = count > 0 ? AppColors.warning : AppColors.running;
    return SizedBox(
      width: 220,
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Icon(icon, color: color),
                const SizedBox(width: 12),
                Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
                Text('$count', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: color)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class EventTile extends StatelessWidget {
  const EventTile({super.key, required this.event, this.dense = true});

  final EventEntry event;
  final bool dense;

  IconData get _icon {
    switch (event.category) {
      case 'alarm':
        return Icons.notifications_active_outlined;
      case 'command':
        return Icons.terminal_outlined;
      case 'control':
        return Icons.autorenew;
      case 'integration':
        return Icons.cloud_sync_outlined;
      case 'maintenance':
        return Icons.build_outlined;
      case 'setpoint':
        return Icons.tune;
      case 'handover':
        return Icons.swap_horiz;
      case 'system':
        return Icons.settings_outlined;
      default:
        return Icons.science_outlined;
    }
  }

  Color get _color {
    switch (event.level) {
      case 'error':
        return AppColors.danger;
      case 'warning':
        return AppColors.warning;
      default:
        return AppColors.muted;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: dense,
      leading: Icon(_icon, color: _color, size: 20),
      title: Text(event.message, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text('${fmtDateTimeSeconds(event.ts)} · ${event.actor ?? 'system'} · ${event.category}', style: const TextStyle(fontSize: 11)),
    );
  }
}
