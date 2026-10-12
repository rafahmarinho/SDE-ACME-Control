import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../models/setpoint.dart';
import '../../providers/auth_providers.dart';
import '../../providers/connectivity_providers.dart';
import '../../providers/core_providers.dart';
import '../../providers/live_notifiers.dart';
import '../../services/api_client.dart';
import '../../widgets/common.dart';

class SetpointsScreen extends ConsumerStatefulWidget {
  const SetpointsScreen({super.key});

  @override
  ConsumerState<SetpointsScreen> createState() => _SetpointsScreenState();
}

class _SetpointsScreenState extends ConsumerState<SetpointsScreen> {
  bool _showHistory = false;

  Future<void> _propose(Setpoint sp) async {
    if (!ref.read(canControlProvider)) {
      showSnack(context, 'Proposing a change requires a connection.', error: true);
      return;
    }
    final result = await showDialog<(double, String)>(context: context, builder: (_) => _ProposeDialog(setpoint: sp));
    if (result == null) return;
    try {
      await ref.read(apiClientProvider).proposeSetpoint(
            plantId: sp.plantId,
            setpointId: sp.id,
            proposedValue: result.$1,
            justification: result.$2,
          );
      if (mounted) showSnack(context, 'Change proposed for ${sp.label}. A supervisor will review it.', success: true);
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } catch (e) {
      if (mounted) showSnack(context, describeError(e), error: true);
    }
  }

  Future<void> _review(SetpointRequest r, bool approve) async {
    if (!ref.read(canControlProvider)) {
      showSnack(context, 'Reviewing requires a connection.', error: true);
      return;
    }
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(approve ? 'Approve change' : 'Reject change'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${r.setpointLabel}: ${fmtNum(r.currentValue, decimals: 2)} → ${fmtNum(r.proposedValue, decimals: 2)}'),
            const SizedBox(height: 6),
            Text('Proposed by ${r.requestedByName ?? 'unknown'}: ${r.justification}', style: const TextStyle(color: AppColors.muted, fontSize: 13)),
            const SizedBox(height: 14),
            TextField(controller: note, maxLines: 2, decoration: const InputDecoration(labelText: 'Review note (optional)')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(
            style: approve ? null : FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(approve ? 'Approve and apply' : 'Reject'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(apiClientProvider).reviewSetpoint(r.id, approve: approve, note: note.text.trim());
      if (mounted) showSnack(context, approve ? 'Setpoint ${r.setpointKey} updated' : 'Proposal rejected', success: true);
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } catch (e) {
      if (mounted) showSnack(context, describeError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final live = ref.watch(setpointsProvider);
    final requests = ref.watch(setpointRequestsProvider).data ?? const <SetpointRequest>[];
    final role = ref.watch(roleProvider);
    final theme = Theme.of(context);
    final pending = requests.where((r) => r.isPending).toList();
    final history = requests.where((r) => !r.isPending).toList();

    return LiveBuilder<List<Setpoint>>(
      live: live,
      onRetry: () => ref.read(setpointsProvider.notifier).refresh(),
      builder: (context, setpoints) {
        final groups = <String, List<Setpoint>>{};
        for (final sp in setpoints) {
          groups.putIfAbsent(sp.groupName, () => []).add(sp);
        }
        return RefreshIndicator(
          onRefresh: () async => ref.read(setpointsProvider.notifier).refresh(),
          child: PageBody(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                StaleNotice(live),
                if (pending.isNotEmpty) ...[
                  SectionHeader(
                    title: 'Awaiting review',
                    subtitle: role.canReviewSetpoints ? 'Approve to apply the new value immediately' : 'Pending supervisor review',
                  ),
                  for (final r in pending)
                    Card(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: AppColors.warning)),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(child: Text(r.setpointLabel, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700))),
                                const StatusChip(label: 'Pending', color: AppColors.warning, dense: true),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text('${fmtNum(r.currentValue, decimals: 2)} → ${fmtNum(r.proposedValue, decimals: 2)}', style: theme.textTheme.headlineSmall?.copyWith(color: AppColors.primary, fontWeight: FontWeight.w800)),
                            const SizedBox(height: 6),
                            Text(r.justification),
                            const SizedBox(height: 6),
                            Text('Proposed by ${r.requestedByName ?? 'unknown'} · ${fmtRelative(r.createdAt)}', style: theme.textTheme.bodySmall?.copyWith(color: AppColors.muted)),
                            if (role.canReviewSetpoints) ...[
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  FilledButton.icon(onPressed: () => _review(r, true), icon: const Icon(Icons.check, size: 18), label: const Text('Approve')),
                                  const SizedBox(width: 10),
                                  OutlinedButton.icon(onPressed: () => _review(r, false), icon: const Icon(Icons.close, size: 18), label: const Text('Reject')),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 18),
                ],
                for (final entry in groups.entries) ...[
                  SectionHeader(title: entry.key),
                  Card(
                    child: Column(
                      children: [
                        for (final sp in entry.value)
                          ListTile(
                            title: Text(sp.label, style: const TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (sp.description != null) Text(sp.description!, style: theme.textTheme.bodySmall),
                                Text('Range ${fmtNum(sp.minValue, decimals: 1)} – ${fmtNum(sp.maxValue, decimals: 1)} ${sp.unit} · updated ${fmtRelative(sp.updatedAt)}', style: theme.textTheme.bodySmall?.copyWith(color: AppColors.muted)),
                              ],
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('${fmtNum(sp.value, decimals: sp.unit == '%' ? 0 : 2)} ${sp.unit}', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: AppColors.primary)),
                                if (role.canProposeSetpoints) ...[
                                  const SizedBox(width: 8),
                                  IconButton(
                                    tooltip: 'Propose change',
                                    onPressed: pending.any((r) => r.setpointId == sp.id) ? null : () => _propose(sp),
                                    icon: const Icon(Icons.edit_outlined, size: 20),
                                  ),
                                ],
                              ],
                            ),
                            isThreeLine: sp.description != null,
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
                SectionHeader(
                  title: 'Review history',
                  trailing: TextButton(onPressed: () => setState(() => _showHistory = !_showHistory), child: Text(_showHistory ? 'Hide' : 'Show (${history.length})')),
                ),
                if (_showHistory)
                  Card(
                    child: history.isEmpty
                        ? const Padding(padding: EdgeInsets.all(18), child: Text('No reviewed proposals yet.'))
                        : Column(
                            children: [
                              for (final r in history)
                                ListTile(
                                  leading: Icon(
                                    r.status == SetpointRequestStatus.approved ? Icons.check_circle_outline : Icons.cancel_outlined,
                                    color: r.status == SetpointRequestStatus.approved ? AppColors.running : AppColors.danger,
                                  ),
                                  title: Text('${r.setpointLabel}: ${fmtNum(r.currentValue, decimals: 2)} → ${fmtNum(r.proposedValue, decimals: 2)}'),
                                  subtitle: Text('${titleCase(r.status.name)} by ${r.reviewedByName ?? '?'} ${fmtRelative(r.reviewedAt)}${r.reviewNote != null && r.reviewNote!.isNotEmpty ? ' · ${r.reviewNote}' : ''}\nProposed by ${r.requestedByName ?? '?'}: ${r.justification}'),
                                  isThreeLine: true,
                                ),
                            ],
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

class _ProposeDialog extends StatefulWidget {
  const _ProposeDialog({required this.setpoint});

  final Setpoint setpoint;

  @override
  State<_ProposeDialog> createState() => _ProposeDialogState();
}

class _ProposeDialogState extends State<_ProposeDialog> {
  late double _value = widget.setpoint.value;
  late final TextEditingController _valueText = TextEditingController(text: fmtNum(widget.setpoint.value, decimals: _decimals));
  final _justification = TextEditingController();
  String? _error;

  int get _decimals => widget.setpoint.unit == '%' ? 0 : 2;

  @override
  void dispose() {
    _valueText.dispose();
    _justification.dispose();
    super.dispose();
  }

  void _submit() {
    final sp = widget.setpoint;
    final v = double.tryParse(_valueText.text.replaceAll(',', '.'));
    if (v == null) {
      setState(() => _error = 'Enter a number');
      return;
    }
    if (v < sp.minValue || v > sp.maxValue) {
      setState(() => _error = 'Value must be between ${fmtNum(sp.minValue, decimals: 1)} and ${fmtNum(sp.maxValue, decimals: 1)} ${sp.unit}');
      return;
    }
    if (v == sp.value) {
      setState(() => _error = 'Proposed value equals the current value');
      return;
    }
    if (_justification.text.trim().length < 5) {
      setState(() => _error = 'Please explain why the change is needed');
      return;
    }
    Navigator.of(context).pop((v, _justification.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    final sp = widget.setpoint;
    return AlertDialog(
      title: Text('Propose change: ${sp.label}'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Current value: ${fmtNum(sp.value, decimals: _decimals)} ${sp.unit}', style: const TextStyle(color: AppColors.muted)),
            const SizedBox(height: 12),
            Slider(
              value: _value.clamp(sp.minValue, sp.maxValue),
              min: sp.minValue,
              max: sp.maxValue,
              divisions: ((sp.maxValue - sp.minValue) / (sp.unit == '%' ? 1 : 0.1)).round().clamp(1, 1000),
              label: '${fmtNum(_value, decimals: _decimals)} ${sp.unit}',
              onChanged: (v) => setState(() {
                _value = v;
                _valueText.text = fmtNum(v, decimals: _decimals);
                _error = null;
              }),
            ),
            TextField(
              controller: _valueText,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: 'Proposed value', suffixText: sp.unit, errorText: _error),
              onChanged: (t) {
                final v = double.tryParse(t.replaceAll(',', '.'));
                if (v != null) setState(() => _value = v);
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _justification,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Justification', hintText: 'Why is this change needed?'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: const Text('Submit for review')),
      ],
    );
  }
}
