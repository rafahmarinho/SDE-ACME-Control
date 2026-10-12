import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../models/equipment.dart';
import '../../providers/live_notifiers.dart';
import '../../widgets/common.dart';
import '../../widgets/equipment_control_panel.dart';

enum _StatusFilter { all, running, stopped, faults, maintenance }

class EquipmentScreen extends ConsumerStatefulWidget {
  const EquipmentScreen({super.key});

  @override
  ConsumerState<EquipmentScreen> createState() => _EquipmentScreenState();
}

class _EquipmentScreenState extends ConsumerState<EquipmentScreen> {
  String _query = '';
  EquipmentType? _type;
  _StatusFilter _status = _StatusFilter.all;
  String? _area;

  bool _matches(Equipment e) {
    if (_type != null && e.type != _type) return false;
    if (_area != null && e.area != _area) return false;
    switch (_status) {
      case _StatusFilter.running:
        if (!(e.isActive || e.isOpen || e.actualState == 'opening')) return false;
      case _StatusFilter.stopped:
        if (!(e.actualState == 'stopped' || e.isClosed)) return false;
      case _StatusFilter.faults:
        if (!(e.isTripped || (e.interlock != null && e.interlock!.isNotEmpty) || e.fault != null)) return false;
      case _StatusFilter.maintenance:
        if (!e.underMaintenance) return false;
      case _StatusFilter.all:
        break;
    }
    if (_query.isEmpty) return true;
    final q = _query.toLowerCase();
    return e.tag.toLowerCase().contains(q) || e.name.toLowerCase().contains(q) || (e.area ?? '').toLowerCase().contains(q);
  }

  @override
  Widget build(BuildContext context) {
    final live = ref.watch(equipmentProvider);
    return LiveBuilder<List<Equipment>>(
      live: live,
      onRetry: () => ref.read(equipmentProvider.notifier).refresh(),
      builder: (context, all) {
        final areas = all.map((e) => e.area).whereType<String>().toSet().toList()..sort();
        final list = all.where(_matches).toList();
        return RefreshIndicator(
          onRefresh: () async => ref.read(equipmentProvider.notifier).refresh(),
          child: PageBody(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                StaleNotice(live),
                Row(
                  children: [
                    Expanded(child: SearchField(hint: 'Search tag, name or area', onChanged: (v) => setState(() => _query = v))),
                    const SizedBox(width: 10),
                    DropdownMenu<String?>(
                      initialSelection: _area,
                      hintText: 'Area',
                      width: 150,
                      inputDecorationTheme: const InputDecorationTheme(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 12)),
                      dropdownMenuEntries: [
                        const DropdownMenuEntry<String?>(value: null, label: 'All areas'),
                        for (final a in areas) DropdownMenuEntry<String?>(value: a, label: a),
                      ],
                      onSelected: (v) => setState(() => _area = v),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilterChip(label: const Text('All types'), selected: _type == null, onSelected: (_) => setState(() => _type = null)),
                    for (final t in EquipmentType.values)
                      FilterChip(label: Text('${titleCase(t.name)}s'), selected: _type == t, onSelected: (_) => setState(() => _type = _type == t ? null : t)),
                    const SizedBox(width: 12),
                    for (final s in _StatusFilter.values)
                      ChoiceChip(label: Text(titleCase(s.name)), selected: _status == s, onSelected: (_) => setState(() => _status = s)),
                  ],
                ),
                const SizedBox(height: 14),
                Text('${list.length} of ${all.length} items', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.muted)),
                const SizedBox(height: 8),
                if (list.isEmpty)
                  const EmptyView(title: 'No equipment matches the filters', icon: Icons.filter_alt_off_outlined)
                else
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final columns = (constraints.maxWidth / 300).floor().clamp(1, 4);
                      return GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columns,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          mainAxisExtent: 128,
                        ),
                        itemCount: list.length,
                        itemBuilder: (context, i) => _EquipmentCard(equipment: list[i]),
                      );
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

IconData equipmentIcon(EquipmentType type) {
  switch (type) {
    case EquipmentType.pump:
      return Icons.settings_input_component_outlined;
    case EquipmentType.valve:
      return Icons.adjust;
    case EquipmentType.tank:
      return Icons.water;
    case EquipmentType.sensor:
      return Icons.sensors;
  }
}

class _EquipmentCard extends ConsumerWidget {
  const _EquipmentCard({required this.equipment});

  final Equipment equipment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final e = equipment;
    final color = equipmentStateColor(e);
    final state = ref.watch(processStateProvider).data;
    final theme = Theme.of(context);
    String detail;
    if (e.isTank) {
      detail = 'Level ${fmtNum(e.position)} %';
    } else if (e.isSensor) {
      detail = '${fmtNum(state?.value(e.tag), decimals: 2)} ${e.unit}${state?.isFaulted(e.tag) == true ? ' · FAULT' : ''}';
    } else if (e.isValve) {
      detail = '${fmtNum(e.position, decimals: 0)} % open';
    } else {
      detail = 'Runtime ${fmtHours(e.runtimeHours)} · ${e.startsCount} starts';
    }
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => context.go('/equipment/${e.id}'),
        onLongPress: e.isControllable ? () => showEquipmentControlSheet(context, e) : null,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(color: color.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(10)),
                    child: Icon(equipmentIcon(e.type), color: color, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(e.tag, style: const TextStyle(fontWeight: FontWeight.w800)),
                        Text(e.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(color: AppColors.muted)),
                      ],
                    ),
                  ),
                  if (e.isControllable)
                    StatusChip(label: e.isAuto ? 'AUTO' : 'MAN', color: e.isAuto ? AppColors.muted : AppColors.warning, dense: true, outlined: true),
                ],
              ),
              const Spacer(),
              Row(
                children: [
                  StatusChip(label: e.underMaintenance ? 'Maintenance' : e.actualLabel, color: color, dense: true),
                  const SizedBox(width: 8),
                  Expanded(child: Text(detail, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall)),
                ],
              ),
              if (e.isControllable && !e.inSync && !e.underMaintenance)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('Requested ${e.requestedLabel} → actual ${e.actualLabel}', style: const TextStyle(fontSize: 11, color: AppColors.warning)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
