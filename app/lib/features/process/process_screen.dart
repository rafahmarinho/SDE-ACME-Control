import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../models/equipment.dart';
import '../../models/process_state.dart';
import '../../providers/live_notifiers.dart';
import '../../widgets/common.dart';
import '../../widgets/equipment_control_panel.dart';
import '../../widgets/process_schematic.dart';
import '../shell/app_shell.dart';

class ProcessScreen extends ConsumerStatefulWidget {
  const ProcessScreen({super.key});

  @override
  ConsumerState<ProcessScreen> createState() => _ProcessScreenState();
}

class _ProcessScreenState extends ConsumerState<ProcessScreen> {
  String? _selectedTag;

  @override
  Widget build(BuildContext context) {
    final live = ref.watch(processStateProvider);
    final equipmentLive = ref.watch(equipmentProvider);
    final equipment = equipmentLive.data ?? const <Equipment>[];
    final mobile = isMobileWidth(context);
    final wide = MediaQuery.sizeOf(context).width >= 1100;

    return LiveBuilder<ProcessState>(
      live: live,
      onRetry: () => ref.read(processStateProvider.notifier).refresh(),
      loadingMessage: 'Loading process data…',
      builder: (context, state) {
        if (equipment.isEmpty) {
          return const LoadingView(message: 'Loading equipment…');
        }
        final selected = _selectedTag == null ? null : equipment.where((e) => e.tag == _selectedTag).firstOrNull;

        final schematicCard = Card(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: mobile
                ? InteractiveViewer(
                    minScale: 1,
                    maxScale: 3,
                    child: ProcessSchematic(
                      equipment: equipment,
                      state: state,
                      compact: true,
                      selectedTag: _selectedTag,
                      onTapEquipment: (e) {
                        setState(() => _selectedTag = e.tag);
                        if (e.isControllable) showEquipmentControlSheet(context, e);
                      },
                    ),
                  )
                : ProcessSchematic(
                    equipment: equipment,
                    state: state,
                    compact: false,
                    selectedTag: _selectedTag,
                    onTapEquipment: (e) {
                      setState(() => _selectedTag = e.tag);
                      if (!wide && e.isControllable) showEquipmentControlSheet(context, e);
                    },
                  ),
          ),
        );

        final conditions = _ConditionsBar(state: state, live: live);

        if (wide) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        conditions,
                        const SizedBox(height: 12),
                        schematicCard,
                        const SizedBox(height: 12),
                        _EquipmentStrip(
                          equipment: equipment,
                          selectedTag: _selectedTag,
                          onSelect: (e) => setState(() => _selectedTag = e.tag),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                SizedBox(
                  width: 380,
                  child: Card(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(18),
                      child: selected != null && selected.isControllable
                          ? EquipmentControlPanel(equipmentId: selected.id, showDetailsLink: false)
                          : selected != null
                              ? _TankOrSensorInfo(equipment: selected, state: state)
                              : const _SelectHint(),
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: () async => ref.read(processStateProvider.notifier).refresh(),
          child: PageBody(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                conditions,
                const SizedBox(height: 12),
                schematicCard,
                const SizedBox(height: 12),
                const SectionHeader(title: 'Equipment', subtitle: 'Tap to operate'),
                _EquipmentStrip(
                  equipment: equipment,
                  selectedTag: _selectedTag,
                  onSelect: (e) {
                    setState(() => _selectedTag = e.tag);
                    if (e.isControllable) showEquipmentControlSheet(context, e);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ConditionsBar extends StatelessWidget {
  const _ConditionsBar({required this.state, required this.live});

  final ProcessState state;
  final dynamic live;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StaleNotice(live),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            StatusChip(label: 'Scenario: ${titleCase(state.scenario)}', color: AppColors.primary, icon: Icons.science_outlined),
            StatusChip(
              label: state.running ? 'Running ${state.speed.toStringAsFixed(0)}x' : 'Paused',
              color: state.running ? AppColors.running : AppColors.warning,
              icon: state.running ? Icons.play_arrow : Icons.pause,
            ),
            StatusChip(label: 'Sim ${fmtDateTimeSeconds(state.simTime)}', color: AppColors.muted, icon: Icons.schedule),
            StatusChip(label: 'Demand ${fmtNum(state.conditions.demandM3h)} m³/h', color: AppColors.muted, icon: Icons.location_city),
            StatusChip(
              label: state.conditions.sourceAvailable ? 'Intake available' : 'Intake unavailable',
              color: state.conditions.sourceAvailable ? AppColors.running : AppColors.danger,
              icon: Icons.water,
            ),
            if (state.conditions.sensorFaults.isNotEmpty)
              StatusChip(label: 'Sensor fault: ${state.conditions.sensorFaults.join(', ')}', color: AppColors.warning, icon: Icons.sensors_off),
            if (state.conditions.overflowM3h > 0.5)
              StatusChip(label: 'T1 overflow ${fmtNum(state.conditions.overflowM3h)} m³/h', color: AppColors.critical, icon: Icons.warning_amber),
          ],
        ),
      ],
    );
  }
}

class _EquipmentStrip extends StatelessWidget {
  const _EquipmentStrip({required this.equipment, required this.onSelect, this.selectedTag});

  final List<Equipment> equipment;
  final String? selectedTag;
  final void Function(Equipment) onSelect;

  @override
  Widget build(BuildContext context) {
    final items = equipment.where((e) => e.isControllable).toList();
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final e in items)
          SizedBox(
            width: 150,
            child: Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: e.tag == selectedTag ? AppColors.primary : AppColors.outline.withValues(alpha: 0.6), width: e.tag == selectedTag ? 2 : 1),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => onSelect(e),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: equipmentStateColor(e))),
                          const SizedBox(width: 6),
                          Text(e.tag, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                          const Spacer(),
                          Text(e.isAuto ? 'AUTO' : 'MAN', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: e.isAuto ? AppColors.muted : AppColors.warning)),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text('Req: ${e.requestedLabel}', style: const TextStyle(fontSize: 11, color: AppColors.muted)),
                      Text('Act: ${e.underMaintenance ? 'Maintenance' : e.actualLabel}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: equipmentStateColor(e))),
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

class _SelectHint extends StatelessWidget {
  const _SelectHint();

  @override
  Widget build(BuildContext context) {
    return const EmptyView(
      icon: Icons.touch_app_outlined,
      title: 'Select equipment',
      message: 'Tap a pump, valve or tank in the schematic to see its requested and actual state and operate it.',
    );
  }
}

class _TankOrSensorInfo extends StatelessWidget {
  const _TankOrSensorInfo({required this.equipment, required this.state});

  final Equipment equipment;
  final ProcessState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tank = state.tank(equipment.tag);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${equipment.tag} · ${equipment.name}', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        if (tank != null) ...[
          InfoRow('Level', '${fmtNum(tank.level)} %'),
          InfoRow('Volume', '${fmtNum(tank.volume, decimals: 1)} m³ of ${fmtNum(tank.capacity, decimals: 0)} m³'),
          InfoRow('Inflow', '${fmtNum(tank.inflow)} m³/h'),
          InfoRow('Outflow', '${fmtNum(tank.outflow)} m³/h'),
          InfoRow('Net', '${fmtNum(tank.netFlow)} m³/h', valueColor: tank.netFlow >= 0 ? AppColors.running : AppColors.warning),
          InfoRow('Alarm limits', 'LL ${equipment.params['ll']} · L ${equipment.params['l']} · H ${equipment.params['h']} · HH ${equipment.params['hh']} %'),
        ],
        if (equipment.isSensor) InfoRow('Value', '${fmtNum(state.value(equipment.tag), decimals: 2)} ${equipment.unit}'),
      ],
    );
  }
}
