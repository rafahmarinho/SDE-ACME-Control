import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../models/shift_handover.dart';
import '../../providers/auth_providers.dart';
import '../../providers/live_notifiers.dart';
import '../../widgets/common.dart';

Color handoverStatusColor(HandoverStatus s) {
  switch (s) {
    case HandoverStatus.draft:
      return AppColors.muted;
    case HandoverStatus.submitted:
      return AppColors.warning;
    case HandoverStatus.acknowledged:
      return AppColors.running;
  }
}

class HandoverScreen extends ConsumerStatefulWidget {
  const HandoverScreen({super.key});

  @override
  ConsumerState<HandoverScreen> createState() => _HandoverScreenState();
}

class _HandoverScreenState extends ConsumerState<HandoverScreen> {
  HandoverStatus? _status;
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final live = ref.watch(handoversProvider);
    final role = ref.watch(roleProvider);
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: role.canHandover
          ? FloatingActionButton.extended(onPressed: () => context.go('/handover/new'), icon: const Icon(Icons.add), label: const Text('New handover'))
          : null,
      body: LiveBuilder<List<ShiftHandover>>(
        live: live,
        onRetry: () => ref.read(handoversProvider.notifier).refresh(),
        builder: (context, all) {
          final list = all.where((h) {
            if (_status != null && h.status != _status) return false;
            if (_query.isEmpty) return true;
            final q = _query.toLowerCase();
            return h.summary.toLowerCase().contains(q) || (h.fromUserName ?? '').toLowerCase().contains(q) || (h.toUserName ?? '').toLowerCase().contains(q) || h.openIssues.any((i) => i.toLowerCase().contains(q));
          }).toList();
          return RefreshIndicator(
            onRefresh: () async => ref.read(handoversProvider.notifier).refresh(),
            child: PageBody(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  StaleNotice(live),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ChoiceChip(label: const Text('All'), selected: _status == null, onSelected: (_) => setState(() => _status = null)),
                      for (final s in HandoverStatus.values)
                        ChoiceChip(label: Text(titleCase(s.name)), selected: _status == s, onSelected: (_) => setState(() => _status = s)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SearchField(hint: 'Search summary, people or issues', onChanged: (v) => setState(() => _query = v)),
                  const SizedBox(height: 14),
                  if (list.isEmpty)
                    EmptyView(
                      icon: Icons.swap_horiz,
                      title: 'No handovers yet',
                      message: 'Create a handover at the end of your shift so the next operator knows what happened.',
                      action: role.canHandover ? FilledButton.icon(onPressed: () => context.go('/handover/new'), icon: const Icon(Icons.add), label: const Text('New handover')) : null,
                    )
                  else
                    for (final h in list)
                      Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () => context.go('/handover/${h.id}'),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(h.shift == 'night' ? Icons.nightlight_outlined : Icons.wb_sunny_outlined, size: 20, color: AppColors.primary),
                                    const SizedBox(width: 8),
                                    Expanded(child: Text('${titleCase(h.shift)} shift · ${fmtDate(h.shiftDate)}', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700))),
                                    StatusChip(label: titleCase(h.status.name), color: handoverStatusColor(h.status), dense: true),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text('${h.fromUserName ?? 'unknown'} → ${h.toUserName ?? 'next operator'}', style: theme.textTheme.bodySmall?.copyWith(color: AppColors.muted)),
                                const SizedBox(height: 8),
                                Text(h.summary, maxLines: 2, overflow: TextOverflow.ellipsis),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 12,
                                  children: [
                                    Text('${h.openIssues.length} open issue${h.openIssues.length == 1 ? '' : 's'}', style: theme.textTheme.bodySmall?.copyWith(color: h.openIssues.isEmpty ? AppColors.running : AppColors.warning)),
                                    Text('Checklist ${h.checklistDone}/${ShiftHandover.checklistItems.length}', style: theme.textTheme.bodySmall),
                                    Text(fmtRelative(h.submittedAt ?? h.createdAt), style: theme.textTheme.bodySmall?.copyWith(color: AppColors.muted)),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
