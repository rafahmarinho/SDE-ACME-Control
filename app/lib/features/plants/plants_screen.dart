import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../models/json.dart';
import '../../models/plant.dart';
import '../../providers/core_providers.dart';
import '../../providers/plant_providers.dart';
import '../../widgets/common.dart';

class PlantSummary {
  const PlantSummary({required this.t1Level, required this.t2Level, required this.activeAlarms, required this.scenario, this.simTime});

  final double? t1Level;
  final double? t2Level;
  final int activeAlarms;
  final String scenario;
  final DateTime? simTime;
}

/// One-shot summary of every plant (levels, scenario, open alarm count).
final plantSummariesProvider = FutureProvider<Map<String, PlantSummary>>((ref) async {
  final client = ref.watch(supabaseClientProvider);
  final states = await client.from('process_state').select('plant_id, scenario, sim_time, tanks');
  final alarms = await client.from('alarms').select('plant_id').neq('state', 'cleared');
  final counts = <String, int>{};
  for (final a in alarms) {
    final id = a['plant_id'] as String;
    counts[id] = (counts[id] ?? 0) + 1;
  }
  final result = <String, PlantSummary>{};
  for (final s in states) {
    final tanks = toMap(s['tanks']);
    result[s['plant_id'] as String] = PlantSummary(
      t1Level: toDoubleOrNull(toMap(tanks['T1'])['level']),
      t2Level: toDoubleOrNull(toMap(tanks['T2'])['level']),
      activeAlarms: counts[s['plant_id']] ?? 0,
      scenario: s['scenario'] as String? ?? 'normal',
      simTime: toDate(s['sim_time']),
    );
  }
  return result;
});

class PlantsScreen extends ConsumerWidget {
  const PlantsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plants = ref.watch(plantsProvider);
    final summaries = ref.watch(plantSummariesProvider).value ?? const <String, PlantSummary>{};
    final selected = ref.watch(selectedPlantProvider);

    return plants.when(
      loading: () => const LoadingView(message: 'Loading plants…'),
      error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(plantsProvider)),
      data: (list) => RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(plantsProvider);
          ref.invalidate(plantSummariesProvider);
        },
        child: PageBody(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SectionHeader(title: 'Plants', subtitle: 'Choose the plant to supervise. Web and mobile share the same data.'),
              Wrap(
                spacing: 14,
                runSpacing: 14,
                children: [
                  for (final p in list)
                    SizedBox(
                      width: 360,
                      child: _PlantCard(
                        plant: p,
                        summary: summaries[p.id],
                        selected: selected?.id == p.id,
                        onOpen: () {
                          ref.read(selectedPlantIdProvider.notifier).select(p.id);
                          context.go('/overview');
                        },
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlantCard extends StatelessWidget {
  const _PlantCard({required this.plant, required this.selected, required this.onOpen, this.summary});

  final Plant plant;
  final PlantSummary? summary;
  final bool selected;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColor = plant.status == 'online' ? AppColors.running : plant.status == 'degraded' ? AppColors.warning : AppColors.danger;
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: selected ? AppColors.primary : AppColors.outline.withValues(alpha: 0.6), width: selected ? 2 : 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.factory_outlined, color: AppColors.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(plant.name, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                      Text('${plant.code} · ${plant.location}', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                    ],
                  ),
                ),
                StatusChip(label: titleCase(plant.status), color: statusColor, dense: true),
              ],
            ),
            if (plant.description != null) ...[
              const SizedBox(height: 10),
              Text(plant.description!, style: theme.textTheme.bodySmall),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 14,
              runSpacing: 6,
              children: [
                _Stat('T1 level', summary?.t1Level == null ? '--' : '${fmtNum(summary!.t1Level)} %'),
                _Stat('T2 level', summary?.t2Level == null ? '--' : '${fmtNum(summary!.t2Level)} %'),
                _Stat('Open alarms', '${summary?.activeAlarms ?? '--'}', color: (summary?.activeAlarms ?? 0) > 0 ? AppColors.warning : AppColors.running),
                _Stat('Capacity', '${fmtNum(plant.designCapacityM3h, decimals: 0)} m³/h'),
                _Stat('Scenario', titleCase(summary?.scenario ?? '--')),
                _Stat('Time zone', plant.timezone),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                if (selected) const StatusChip(label: 'Selected', color: AppColors.primary, icon: Icons.check, dense: true),
                const Spacer(),
                FilledButton.icon(onPressed: onOpen, icon: const Icon(Icons.login, size: 18), label: const Text('Open plant')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value, {this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        Text(value, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700, color: color)),
      ],
    );
  }
}
