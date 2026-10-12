import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../models/alarm.dart';
import '../../providers/auth_providers.dart';
import '../../providers/connectivity_providers.dart';
import '../../providers/core_providers.dart';
import '../../providers/live_notifiers.dart';
import '../../providers/plant_providers.dart';
import '../../widgets/common.dart';
import 'alarm_tile.dart';

class AlarmsScreen extends ConsumerStatefulWidget {
  const AlarmsScreen({super.key});

  @override
  ConsumerState<AlarmsScreen> createState() => _AlarmsScreenState();
}

class _AlarmsScreenState extends ConsumerState<AlarmsScreen> {
  AlarmState? _state = AlarmState.active;
  final Set<AlarmSeverity> _severities = {};
  String _query = '';
  bool _busy = false;

  bool _matches(Alarm a) {
    if (_state != null && a.state != _state) return false;
    if (_severities.isNotEmpty && !_severities.contains(a.severity)) return false;
    if (_query.isEmpty) return true;
    final q = _query.toLowerCase();
    return a.message.toLowerCase().contains(q) || a.code.toLowerCase().contains(q) || (a.tag ?? '').toLowerCase().contains(q);
  }

  Future<void> _ackAll() async {
    final profile = ref.read(profileProvider).value;
    final plantId = ref.read(effectivePlantIdProvider);
    if (profile == null || plantId == null) return;
    if (!ref.read(connectivityProvider)) {
      showSnack(context, 'Acknowledging alarms requires a connection.', error: true);
      return;
    }
    final ok = await confirmDialog(context, title: 'Acknowledge all', message: 'Acknowledge every active alarm of this plant?', confirmLabel: 'Acknowledge all');
    if (!ok) return;
    setState(() => _busy = true);
    try {
      final n = await ref.read(alarmRepositoryProvider).acknowledgeAll(plantId, userId: profile.id, userName: profile.displayName);
      if (mounted) showSnack(context, '$n alarm${n == 1 ? '' : 's'} acknowledged', success: true);
    } catch (e) {
      if (mounted) showSnack(context, describeError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final live = ref.watch(alarmsProvider);
    final role = ref.watch(roleProvider);
    return LiveBuilder<List<Alarm>>(
      live: live,
      onRetry: () => ref.read(alarmsProvider.notifier).refresh(),
      builder: (context, all) {
        final active = all.where((a) => a.state == AlarmState.active).length;
        final acked = all.where((a) => a.state == AlarmState.acknowledged).length;
        final cleared = all.where((a) => a.state == AlarmState.cleared).length;
        final list = all.where(_matches).toList();
        return RefreshIndicator(
          onRefresh: () async => ref.read(alarmsProvider.notifier).refresh(),
          child: PageBody(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                StaleNotice(live),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _CountChip(label: 'Active', count: active, color: AppColors.danger, selected: _state == AlarmState.active, onTap: () => setState(() => _state = AlarmState.active)),
                    _CountChip(label: 'Acknowledged', count: acked, color: AppColors.warning, selected: _state == AlarmState.acknowledged, onTap: () => setState(() => _state = AlarmState.acknowledged)),
                    _CountChip(label: 'Cleared', count: cleared, color: AppColors.muted, selected: _state == AlarmState.cleared, onTap: () => setState(() => _state = AlarmState.cleared)),
                    _CountChip(label: 'All', count: all.length, color: AppColors.primary, selected: _state == null, onTap: () => setState(() => _state = null)),
                    if (role.canOperate && active > 0)
                      FilledButton.tonalIcon(
                        onPressed: _busy ? null : _ackAll,
                        icon: const Icon(Icons.done_all, size: 18),
                        label: const Text('Acknowledge all'),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: SearchField(hint: 'Search message, code or tag', onChanged: (v) => setState(() => _query = v))),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final s in AlarmSeverity.values)
                      FilterChip(
                        avatar: SeverityDot(s, size: 9),
                        label: Text(severityLabel(s)),
                        selected: _severities.contains(s),
                        onSelected: (v) => setState(() => v ? _severities.add(s) : _severities.remove(s)),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                if (list.isEmpty)
                  EmptyView(
                    icon: _state == AlarmState.active ? Icons.check_circle_outline : Icons.notifications_off_outlined,
                    title: _state == AlarmState.active ? 'No active alarms' : 'No alarms match the filters',
                    message: _state == AlarmState.active ? 'The process is running within limits.' : null,
                  )
                else
                  Card(
                    child: ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: list.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, i) => AlarmTile(alarm: list[i]),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _CountChip extends StatelessWidget {
  const _CountChip({required this.label, required this.count, required this.color, required this.selected, required this.onTap});

  final String label;
  final int count;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      selected: selected,
      onSelected: (_) => onTap(),
      avatar: CircleAvatar(backgroundColor: color.withValues(alpha: 0.25), child: Text('$count', style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w800))),
      label: Text(label),
    );
  }
}
