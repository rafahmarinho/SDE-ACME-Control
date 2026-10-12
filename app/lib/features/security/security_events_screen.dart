import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../models/security_event.dart';
import '../../providers/auth_providers.dart';
import '../../providers/core_providers.dart';
import '../../widgets/common.dart';

/// Latest 200 rows of the `security_events` audit log (RLS: supervisors only).
final securityEventsProvider = FutureProvider.autoDispose<List<SecurityEvent>>((ref) {
  ref.watch(sessionProvider);
  return ref.watch(securityRepositoryProvider).fetchLatest(limit: 200);
});

Color outcomeColor(String outcome) {
  switch (outcome) {
    case 'success':
      return AppColors.running;
    case 'denied':
      return AppColors.danger;
    case 'rejected':
      return AppColors.warning;
    case 'error':
      return AppColors.critical;
    default:
      return AppColors.steel;
  }
}

class SecurityEventsScreen extends ConsumerStatefulWidget {
  const SecurityEventsScreen({super.key});

  @override
  ConsumerState<SecurityEventsScreen> createState() => _SecurityEventsScreenState();
}

class _SecurityEventsScreenState extends ConsumerState<SecurityEventsScreen> {
  String _query = '';
  final Set<String> _outcomes = {};

  bool _matches(SecurityEvent e) {
    if (_outcomes.isNotEmpty && !_outcomes.contains(e.outcome)) return false;
    if (_query.isEmpty) return true;
    final q = _query.toLowerCase();
    return e.action.toLowerCase().contains(q) ||
        e.actorLabel.toLowerCase().contains(q) ||
        (e.actorRole ?? '').toLowerCase().contains(q) ||
        (e.path ?? '').toLowerCase().contains(q);
  }

  @override
  Widget build(BuildContext context) {
    final role = ref.watch(roleProvider);
    if (!role.canViewSecurityLog) {
      return const EmptyView(icon: Icons.lock_outline, title: 'Supervisors only', message: 'The security audit log is restricted to supervisors.');
    }
    final events = ref.watch(securityEventsProvider);

    return events.when(
      loading: () => const LoadingView(message: 'Loading security events…'),
      error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(securityEventsProvider), title: 'Could not load the security log'),
      data: (all) {
        final list = all.where(_matches).toList();
        final counts = <String, int>{for (final o in SecurityEvent.outcomes) o: all.where((e) => e.outcome == o).length};
        return RefreshIndicator(
          onRefresh: () => ref.refresh(securityEventsProvider.future),
          child: PageBody(
            maxWidth: 1000,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SectionHeader(
                  title: 'Security audit log',
                  subtitle: 'Latest ${all.length} authentication and authorisation events, newest first',
                  trailing: IconButton(tooltip: 'Refresh', onPressed: () => ref.invalidate(securityEventsProvider), icon: const Icon(Icons.refresh)),
                ),
                SearchField(hint: 'Search action, actor or path', onChanged: (v) => setState(() => _query = v.trim())),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final o in SecurityEvent.outcomes)
                      FilterChip(
                        avatar: CircleAvatar(backgroundColor: outcomeColor(o), radius: 5),
                        label: Text('${titleCase(o)} (${counts[o]})'),
                        selected: _outcomes.contains(o),
                        onSelected: (v) => setState(() => v ? _outcomes.add(o) : _outcomes.remove(o)),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                if (all.isEmpty)
                  const EmptyView(icon: Icons.security_outlined, title: 'No security events yet', message: 'Sign-ins, denied requests and policy rejections will appear here.')
                else if (list.isEmpty)
                  const EmptyView(icon: Icons.filter_alt_off_outlined, title: 'No events match the filters')
                else
                  Card(
                    child: ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: list.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, i) => _SecurityEventTile(event: list[i]),
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

class _SecurityEventTile extends StatelessWidget {
  const _SecurityEventTile({required this.event});

  final SecurityEvent event;

  static const _json = JsonEncoder.withIndent('  ');

  @override
  Widget build(BuildContext context) {
    final e = event;
    final theme = Theme.of(context);
    final color = outcomeColor(e.outcome);
    final subtitleParts = [
      e.actorLabel,
      if (e.actorRole != null) e.actorRole!,
      if (e.path != null) e.path!,
      if (e.status != null) 'HTTP ${e.status}',
    ];
    return ExpansionTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(color: color.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(10)),
        child: Icon(
          e.outcome == 'success' ? Icons.verified_user_outlined : Icons.gpp_maybe_outlined,
          color: color,
          size: 20,
        ),
      ),
      title: Text(e.action, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(subtitleParts.join(' · '), maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(color: AppColors.muted)),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          StatusChip(label: titleCase(e.outcome), color: color, dense: true),
          const SizedBox(height: 4),
          Text(fmtDateTimeSeconds(e.ts), style: theme.textTheme.bodySmall?.copyWith(color: AppColors.muted)),
        ],
      ),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InfoRow('Time', fmtDateTimeSeconds(e.ts)),
        InfoRow('Actor', e.actorLabel),
        if (e.actorId != null) InfoRow('Actor id', e.actorId!),
        InfoRow('Role', e.actorRole ?? '--'),
        InfoRow('Path', e.path ?? '--'),
        InfoRow('Status', e.status?.toString() ?? '--'),
        InfoRow('IP address', e.ip ?? '--'),
        InfoRow('User agent', e.userAgent ?? '--'),
        InfoRow('Request id', e.requestId ?? '--'),
        if (e.details.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('Details', style: theme.textTheme.labelLarge),
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: AppColors.surfaceHigh, borderRadius: BorderRadius.circular(10)),
            child: SelectableText(_json.convert(e.details), style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
          ),
        ],
      ],
    );
  }
}
