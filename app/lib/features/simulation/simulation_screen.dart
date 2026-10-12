import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../models/event_entry.dart';
import '../../models/process_state.dart';
import '../../models/scenario.dart';
import '../../providers/auth_providers.dart';
import '../../providers/connectivity_providers.dart';
import '../../providers/core_providers.dart';
import '../../providers/live_notifiers.dart';
import '../../providers/plant_providers.dart';
import '../../services/api_client.dart';
import '../../widgets/common.dart';
import '../overview/overview_screen.dart';
import '../plants/plants_screen.dart';

final scenariosProvider = FutureProvider<List<Scenario>>((ref) {
  ref.watch(sessionProvider);
  return ref.watch(apiClientProvider).scenarios();
});

class SimulationScreen extends ConsumerStatefulWidget {
  const SimulationScreen({super.key});

  @override
  ConsumerState<SimulationScreen> createState() => _SimulationScreenState();
}

class _SimulationScreenState extends ConsumerState<SimulationScreen> {
  bool _busy = false;
  String? _busyLabel;
  String _category = 'all';
  String _query = '';

  Future<void> _run(String label, Future<void> Function() action) async {
    if (_busy) return;
    if (!ref.read(canControlProvider)) {
      showSnack(context, 'Simulation controls require a connection.', error: true);
      return;
    }
    setState(() {
      _busy = true;
      _busyLabel = label;
    });
    try {
      await action();
      ref.read(apiReachableProvider.notifier).set(true);
    } on ApiException catch (e) {
      if (e.isNetwork) ref.read(apiReachableProvider.notifier).set(false);
      if (mounted) showSnack(context, e.message, error: true);
    } catch (e) {
      if (mounted) showSnack(context, describeError(e), error: true);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _busyLabel = null;
        });
      }
    }
  }

  Future<void> _advance(String plantId, int seconds, String label) => _run('Advancing $label…', () async {
        final r = await ref.read(apiClientProvider).advance(plantId, seconds);
        if (!mounted) return;
        final raised = r.raised.map((a) => a['code']).join(', ');
        showSnack(
          context,
          'Advanced $label: ${r.raised.length} alarm${r.raised.length == 1 ? '' : 's'} raised${raised.isNotEmpty ? ' ($raised)' : ''}, ${r.cleared.length} cleared, ${r.events} events.',
          success: true,
        );
      });

  Future<void> _loadScenario(String plantId, Scenario s) async {
    final ok = await confirmDialog(context, title: 'Load scenario', message: '${s.name}\n\n${s.description}\n\nOpen process alarms are cleared and re-evaluated.', confirmLabel: 'Load');
    if (!ok) return;
    await _run('Loading ${s.name}…', () async {
      await ref.read(apiClientProvider).loadScenario(plantId, s.code);
      if (mounted) showSnack(context, 'Scenario "${s.name}" loaded. ${s.expected}', success: true);
    });
  }

  Future<void> _reset() async {
    final ok = await confirmDialog(
      context,
      title: 'Reset demo data',
      message: 'This rebuilds equipment, setpoints, alarms, work orders, handovers, commands, events and 24 h of trend history for BOTH plants. User accounts are kept. Continue?',
      confirmLabel: 'Reset everything',
      destructive: true,
    );
    if (!ok) return;
    await _run('Resetting demo data…', () async {
      await ref.read(apiClientProvider).resetDemoData();
      ref.invalidate(plantSummariesProvider);
      if (mounted) showSnack(context, 'Demo data reset to defaults', success: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final plantId = ref.watch(effectivePlantIdProvider);
    final live = ref.watch(processStateProvider);
    final scenarios = ref.watch(scenariosProvider);
    final events = ref.watch(eventsProvider).data ?? const <EventEntry>[];
    final theme = Theme.of(context);
    final categories = ['all', ...{for (final e in events) e.category}];
    final filtered = events.where((e) {
      if (_category != 'all' && e.category != _category) return false;
      if (_query.isEmpty) return true;
      final q = _query.toLowerCase();
      return e.message.toLowerCase().contains(q) || (e.actor ?? '').toLowerCase().contains(q);
    }).toList();

    if (plantId == null) return const LoadingView();

    return LiveBuilder<ProcessState>(
      live: live,
      onRetry: () => ref.read(processStateProvider.notifier).refresh(),
      builder: (context, state) => PageBody(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            StaleNotice(live),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text('Simulation control', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
                        StatusChip(
                          label: state.running ? 'Running ${state.speed.toStringAsFixed(0)}x' : 'Paused',
                          color: state.running ? AppColors.running : AppColors.warning,
                          icon: state.running ? Icons.play_arrow : Icons.pause,
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 18,
                      runSpacing: 8,
                      children: [
                        _Stat('Scenario', titleCase(state.scenario)),
                        _Stat('Simulation time', fmtDateTimeSeconds(state.simTime)),
                        _Stat('Last tick', fmtRelative(state.lastTickAt)),
                        _Stat('Demand', '${fmtNum(state.conditions.demandM3h)} m³/h (×${state.conditions.demandFactor.toStringAsFixed(1)})'),
                        _Stat('Intake', state.conditions.sourceAvailable ? 'available' : 'unavailable'),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        FilledButton.tonalIcon(
                          onPressed: _busy ? null : () => _run(state.running ? 'Pausing…' : 'Resuming…', () => ref.read(apiClientProvider).control(plantId, running: !state.running)),
                          icon: Icon(state.running ? Icons.pause : Icons.play_arrow),
                          label: Text(state.running ? 'Pause' : 'Resume'),
                        ),
                        SegmentedButton<double>(
                          segments: const [
                            ButtonSegment(value: 1, label: Text('1x')),
                            ButtonSegment(value: 5, label: Text('5x')),
                            ButtonSegment(value: 20, label: Text('20x')),
                          ],
                          selected: {[1.0, 5.0, 20.0].contains(state.speed) ? state.speed : 1.0},
                          onSelectionChanged: _busy ? null : (s) => _run('Changing speed…', () => ref.read(apiClientProvider).control(plantId, running: true, speed: s.first)),
                        ),
                        const SizedBox(width: 8),
                        Text('Advance:', style: theme.textTheme.labelLarge),
                        OutlinedButton(onPressed: _busy ? null : () => _advance(plantId, 60, '1 min'), child: const Text('+1 min')),
                        OutlinedButton(onPressed: _busy ? null : () => _advance(plantId, 600, '10 min'), child: const Text('+10 min')),
                        OutlinedButton(onPressed: _busy ? null : () => _advance(plantId, 3600, '1 h'), child: const Text('+1 h')),
                      ],
                    ),
                    if (_busy) ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                          const SizedBox(width: 10),
                          Text(_busyLabel ?? 'Working…'),
                        ],
                      ),
                    ],
                    const SizedBox(height: 10),
                    Text(
                      'While a client is connected the process advances in real time (one tick every few seconds). Advancing jumps the simulated clock and writes trend samples once per simulated minute.',
                      style: theme.textTheme.bodySmall?.copyWith(color: AppColors.muted),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            const SectionHeader(title: 'Scenarios', subtitle: 'Load a situation and watch how the process and alarms respond'),
            scenarios.when(
              loading: () => const LoadingView(message: 'Loading scenarios…'),
              error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(scenariosProvider), title: 'Could not load scenarios from the control API'),
              data: (list) => Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final s in list)
                    SizedBox(
                      width: 360,
                      child: Card(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: BorderSide(color: s.code == state.scenario ? AppColors.primary : AppColors.outline.withValues(alpha: 0.6), width: s.code == state.scenario ? 2 : 1),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(child: Text(s.name, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700))),
                                  if (s.code == state.scenario) const StatusChip(label: 'Active', color: AppColors.primary, dense: true),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(s.description, style: theme.textTheme.bodySmall),
                              const SizedBox(height: 6),
                              Text('Expect: ${s.expected}', style: theme.textTheme.bodySmall?.copyWith(color: AppColors.muted)),
                              const SizedBox(height: 10),
                              Align(
                                alignment: Alignment.centerRight,
                                child: FilledButton.tonal(onPressed: _busy ? null : () => _loadScenario(plantId, s), child: Text(s.code == state.scenario ? 'Reload' : 'Load')),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            const SectionHeader(title: 'Demo data', subtitle: 'Rebuild both plants from the seed definition'),
            Card(
              child: ListTile(
                leading: const Icon(Icons.restart_alt, color: AppColors.danger),
                title: const Text('Reset demo data'),
                subtitle: const Text('Equipment, setpoints, alarms, work orders, handovers, commands, events and trend history. Accounts are kept.'),
                trailing: FilledButton(style: FilledButton.styleFrom(backgroundColor: AppColors.danger), onPressed: _busy ? null : _reset, child: const Text('Reset')),
              ),
            ),
            const SizedBox(height: 18),
            SectionHeader(title: 'Event inspector', subtitle: 'Latest ${events.length} events of this plant, live'),
            Row(
              children: [
                Expanded(child: SearchField(hint: 'Search events', onChanged: (v) => setState(() => _query = v))),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final c in categories)
                  ChoiceChip(label: Text(titleCase(c)), selected: _category == c, onSelected: (_) => setState(() => _category = c)),
              ],
            ),
            const SizedBox(height: 10),
            Card(
              child: filtered.isEmpty
                  ? const Padding(padding: EdgeInsets.all(18), child: Text('No events match.'))
                  : ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final e = filtered[i];
                        return ExpansionTile(
                          title: EventTile(event: e),
                          tilePadding: EdgeInsets.zero,
                          childrenPadding: const EdgeInsets.fromLTRB(56, 0, 16, 12),
                          children: [
                            Align(
                              alignment: Alignment.centerLeft,
                              child: SelectableText(
                                e.data.isEmpty ? 'No additional data' : e.data.entries.map((d) => '${d.key}: ${d.value}').join('\n'),
                                style: const TextStyle(fontSize: 12, fontFamily: 'monospace', color: AppColors.muted),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        Text(value, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
      ],
    );
  }
}
