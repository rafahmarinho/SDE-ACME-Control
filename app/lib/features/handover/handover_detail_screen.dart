import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../models/profile.dart';
import '../../models/shift_handover.dart';
import '../../providers/auth_providers.dart';
import '../../providers/connectivity_providers.dart';
import '../../providers/core_providers.dart';
import '../../providers/live_notifiers.dart';
import '../../widgets/common.dart';
import 'handover_screen.dart';

class HandoverDetailScreen extends ConsumerStatefulWidget {
  const HandoverDetailScreen({super.key, required this.handoverId});

  final String handoverId;

  @override
  ConsumerState<HandoverDetailScreen> createState() => _HandoverDetailScreenState();
}

class _HandoverDetailScreenState extends ConsumerState<HandoverDetailScreen> {
  bool _busy = false;

  Future<void> _submit(ShiftHandover h) async {
    if (!ref.read(connectivityProvider)) {
      showSnack(context, 'Submitting requires a connection.', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(handoverRepositoryProvider).submit(h.id);
      final profile = ref.read(profileProvider).value;
      await ref.read(eventRepositoryProvider).log(plantId: h.plantId, category: 'handover', message: '${titleCase(h.shift)} shift handover submitted', actor: profile?.displayName ?? 'unknown', data: {'handover_id': h.id});
      if (mounted) showSnack(context, 'Handover submitted', success: true);
    } catch (e) {
      if (mounted) showSnack(context, describeError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _acknowledge(ShiftHandover h) async {
    final profile = ref.read(profileProvider).value;
    if (profile == null) return;
    if (!ref.read(connectivityProvider)) {
      showSnack(context, 'Acknowledging requires a connection.', error: true);
      return;
    }
    final ok = await confirmDialog(context, title: 'Acknowledge handover', message: 'Confirm that you have read the ${h.shift} shift handover from ${h.fromUserName ?? 'the outgoing operator'} and take over the plant.', confirmLabel: 'Acknowledge');
    if (!ok) return;
    setState(() => _busy = true);
    try {
      await ref.read(handoverRepositoryProvider).acknowledge(h.id, userId: profile.id, userName: profile.displayName);
      await ref.read(eventRepositoryProvider).log(plantId: h.plantId, category: 'handover', message: '${titleCase(h.shift)} shift handover acknowledged by ${profile.displayName}', actor: profile.displayName, data: {'handover_id': h.id});
      if (mounted) showSnack(context, 'Handover acknowledged', success: true);
    } catch (e) {
      if (mounted) showSnack(context, describeError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editSummary(ShiftHandover h) async {
    final controller = TextEditingController(text: h.summary);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit summary'),
        content: TextField(controller: controller, maxLines: 6, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Save')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(handoverRepositoryProvider).update(h.id, {'summary': controller.text.trim()});
    } catch (e) {
      if (mounted) showSnack(context, describeError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final live = ref.watch(handoversProvider);
    final role = ref.watch(roleProvider);
    final me = ref.watch(currentUserIdProvider);
    final theme = Theme.of(context);

    return LiveBuilder<List<ShiftHandover>>(
      live: live,
      onRetry: () => ref.read(handoversProvider.notifier).refresh(),
      builder: (context, list) {
        final h = list.where((x) => x.id == widget.handoverId).firstOrNull;
        if (h == null) {
          return EmptyView(icon: Icons.search_off, title: 'Handover not found', action: FilledButton(onPressed: () => context.go('/handover'), child: const Text('Back to handovers')));
        }
        final isAuthor = h.fromUser == me;
        final canAck = h.status == HandoverStatus.submitted && !isAuthor && (h.toUser == me || h.toUser == null || role == UserRole.supervisor) && (role == UserRole.supervisor || h.toUser == me);
        return PageBody(
          maxWidth: 820,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  IconButton(onPressed: () => context.go('/handover'), icon: const Icon(Icons.arrow_back)),
                  Icon(h.shift == 'night' ? Icons.nightlight_outlined : Icons.wb_sunny_outlined, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Expanded(child: Text('${titleCase(h.shift)} shift · ${fmtDate(h.shiftDate)}', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800))),
                  StatusChip(label: titleCase(h.status.name), color: handoverStatusColor(h.status)),
                ],
              ),
              const SizedBox(height: 12),
              StaleNotice(live),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      InfoRow('From', h.fromUserName ?? 'unknown'),
                      InfoRow('To', h.toUserName ?? 'Next operator on duty'),
                      InfoRow('Submitted', h.submittedAt == null ? 'Not yet' : fmtDateTime(h.submittedAt)),
                      InfoRow('Acknowledged', h.acknowledgedAt == null ? 'Not yet' : fmtDateTime(h.acknowledgedAt)),
                      const Divider(height: 24),
                      Row(
                        children: [
                          Expanded(child: Text('Summary', style: theme.textTheme.labelLarge)),
                          if (isAuthor && h.status != HandoverStatus.acknowledged)
                            IconButton(tooltip: 'Edit', onPressed: () => _editSummary(h), icon: const Icon(Icons.edit_outlined, size: 18)),
                        ],
                      ),
                      Text(h.summary.isEmpty ? 'No summary.' : h.summary),
                      const SizedBox(height: 16),
                      Text('Open issues', style: theme.textTheme.labelLarge),
                      const SizedBox(height: 4),
                      if (h.openIssues.isEmpty)
                        const Text('No open issues.', style: TextStyle(color: AppColors.running))
                      else
                        for (final i in h.openIssues)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(Icons.warning_amber_rounded, size: 16, color: AppColors.warning),
                                const SizedBox(width: 8),
                                Expanded(child: Text(i)),
                              ],
                            ),
                          ),
                      const SizedBox(height: 16),
                      Text('Checklist', style: theme.textTheme.labelLarge),
                      const SizedBox(height: 4),
                      for (final item in ShiftHandover.checklistItems.entries)
                        Row(
                          children: [
                            Icon(
                              (h.checklist[item.key] ?? false) ? Icons.check_box : Icons.check_box_outline_blank,
                              size: 18,
                              color: (h.checklist[item.key] ?? false) ? AppColors.running : AppColors.muted,
                            ),
                            const SizedBox(width: 8),
                            Text(item.value),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  if (isAuthor && h.status == HandoverStatus.draft)
                    FilledButton.icon(onPressed: _busy ? null : () => _submit(h), icon: const Icon(Icons.send_outlined), label: const Text('Submit handover')),
                  if (canAck)
                    FilledButton.icon(onPressed: _busy ? null : () => _acknowledge(h), icon: const Icon(Icons.check), label: const Text('Acknowledge and take over')),
                  if (h.status == HandoverStatus.submitted && !canAck && !isAuthor)
                    Text('Waiting for ${h.toUserName ?? 'the incoming operator'} or a supervisor to acknowledge.', style: theme.textTheme.bodySmall?.copyWith(color: AppColors.muted)),
                ],
              ),
              if (_busy) const Padding(padding: EdgeInsets.only(top: 12), child: LinearProgressIndicator()),
            ],
          ),
        );
      },
    );
  }
}
