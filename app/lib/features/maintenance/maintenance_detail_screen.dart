import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../models/equipment.dart';
import '../../models/maintenance_order.dart';
import '../../providers/auth_providers.dart';
import '../../providers/connectivity_providers.dart';
import '../../providers/core_providers.dart';
import '../../providers/live_notifiers.dart';
import '../../widgets/common.dart';
import '../../widgets/equipment_control_panel.dart';
import 'maintenance_tile.dart';

class MaintenanceDetailScreen extends ConsumerStatefulWidget {
  const MaintenanceDetailScreen({super.key, required this.orderId});

  final String orderId;

  @override
  ConsumerState<MaintenanceDetailScreen> createState() => _MaintenanceDetailScreenState();
}

class _MaintenanceDetailScreenState extends ConsumerState<MaintenanceDetailScreen> {
  bool _busy = false;

  Future<void> _setStatus(MaintenanceOrder o, MaintenanceStatus status) async {
    if (!ref.read(connectivityProvider)) {
      showSnack(context, 'Updating a work order requires a connection.', error: true);
      return;
    }
    String? notes;
    if (status == MaintenanceStatus.done) {
      final controller = TextEditingController(text: o.workNotes ?? '');
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Complete work order'),
          content: TextField(controller: controller, maxLines: 4, autofocus: true, decoration: const InputDecoration(labelText: 'Work notes', hintText: 'What was done, parts used, test results')),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Complete')),
          ],
        ),
      );
      if (ok != true) return;
      notes = controller.text.trim();
    } else if (status == MaintenanceStatus.cancelled) {
      final ok = await confirmDialog(context, title: 'Cancel work order', message: 'Cancel ${o.code}? This cannot be undone.', confirmLabel: 'Cancel order', destructive: true);
      if (!ok) return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(maintenanceRepositoryProvider).setStatus(o.id, status, workNotes: notes);
      final profile = ref.read(profileProvider).value;
      await ref.read(eventRepositoryProvider).log(
            plantId: o.plantId,
            category: 'maintenance',
            message: 'Work order ${o.code} ${maintenanceStatusLabel(status).toLowerCase()}',
            actor: profile?.displayName ?? 'unknown',
            data: {'order_id': o.id, 'status': maintenanceStatusToDb(status)},
          );
      if (mounted) showSnack(context, 'Work order ${maintenanceStatusLabel(status).toLowerCase()}', success: true);
    } catch (e) {
      if (mounted) showSnack(context, describeError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _assignToMe(MaintenanceOrder o) async {
    final profile = ref.read(profileProvider).value;
    if (profile == null) return;
    setState(() => _busy = true);
    try {
      await ref.read(maintenanceRepositoryProvider).update(o.id, {'assigned_to': profile.id, 'assigned_to_name': profile.displayName});
      if (mounted) showSnack(context, 'Assigned to you', success: true);
    } catch (e) {
      if (mounted) showSnack(context, describeError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final live = ref.watch(maintenanceOrdersProvider);
    final role = ref.watch(roleProvider);
    final equipment = ref.watch(equipmentProvider).data ?? const <Equipment>[];
    final theme = Theme.of(context);

    return LiveBuilder<List<MaintenanceOrder>>(
      live: live,
      onRetry: () => ref.read(maintenanceOrdersProvider.notifier).refresh(),
      builder: (context, list) {
        final o = list.where((x) => x.id == widget.orderId).firstOrNull;
        if (o == null) {
          return EmptyView(icon: Icons.search_off, title: 'Work order not found', action: FilledButton(onPressed: () => context.go('/maintenance'), child: const Text('Back to maintenance')));
        }
        final eq = equipment.where((e) => e.id == o.equipmentId).firstOrNull;
        return PageBody(
          maxWidth: 900,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  IconButton(onPressed: () => context.go('/maintenance'), icon: const Icon(Icons.arrow_back)),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${o.code} · ${o.title}', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                        Text('Created by ${o.createdByName ?? 'unknown'} · ${fmtDateTime(o.createdAt)}', style: theme.textTheme.bodySmall?.copyWith(color: AppColors.muted)),
                      ],
                    ),
                  ),
                  StatusChip(label: maintenanceStatusLabel(o.status), color: maintenanceStatusColor(o.status)),
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
                      Text(o.description.isEmpty ? 'No description.' : o.description),
                      const SizedBox(height: 14),
                      InfoRow('Priority', titleCase(o.priority.name), valueColor: priorityColor(o.priority)),
                      InfoRow('Equipment', eq != null ? '${eq.tag} · ${eq.name}' : (o.equipmentTag ?? 'Not linked')),
                      InfoRow('Assigned to', o.assignedToName ?? 'Unassigned'),
                      InfoRow('Scheduled', o.scheduledFor == null ? 'Not scheduled' : fmtDateTime(o.scheduledFor)),
                      InfoRow('Started', o.startedAt == null ? '--' : fmtDateTime(o.startedAt)),
                      InfoRow('Completed', o.completedAt == null ? '--' : fmtDateTime(o.completedAt)),
                      if (o.workNotes != null && o.workNotes!.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Text('Work notes', style: theme.textTheme.labelLarge),
                        const SizedBox(height: 4),
                        Text(o.workNotes!),
                      ],
                    ],
                  ),
                ),
              ),
              if (o.attachments.isNotEmpty) ...[
                const SizedBox(height: 14),
                const SectionHeader(title: 'Attachments'),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final a in o.attachments)
                      a.isImage
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Image.network(a.url, width: 160, height: 120, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(width: 160, height: 120, color: AppColors.surfaceHigh, child: const Icon(Icons.broken_image_outlined))),
                            )
                          : Chip(avatar: const Icon(Icons.attach_file, size: 16), label: Text(a.name)),
                  ],
                ),
              ],
              if (role.canMaintain && !o.isClosed) ...[
                const SizedBox(height: 14),
                const SectionHeader(title: 'Actions'),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    if (o.status == MaintenanceStatus.open)
                      FilledButton.icon(onPressed: _busy ? null : () => _setStatus(o, MaintenanceStatus.inProgress), icon: const Icon(Icons.play_arrow), label: const Text('Start work')),
                    if (o.status == MaintenanceStatus.inProgress)
                      FilledButton.icon(onPressed: _busy ? null : () => _setStatus(o, MaintenanceStatus.done), icon: const Icon(Icons.check), label: const Text('Complete')),
                    if (o.assignedTo != ref.watch(currentUserIdProvider))
                      OutlinedButton.icon(onPressed: _busy ? null : () => _assignToMe(o), icon: const Icon(Icons.person_add_alt_outlined), label: const Text('Assign to me')),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
                      onPressed: _busy ? null : () => _setStatus(o, MaintenanceStatus.cancelled),
                      icon: const Icon(Icons.cancel_outlined),
                      label: const Text('Cancel order'),
                    ),
                  ],
                ),
              ],
              if (eq != null && eq.isControllable) ...[
                const SizedBox(height: 14),
                SectionHeader(title: 'Equipment lockout', subtitle: '${eq.tag} is ${eq.underMaintenance ? 'under maintenance' : 'in service'}'),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Icon(Icons.build_circle_outlined, color: eq.underMaintenance ? AppColors.maintenance : AppColors.muted),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            eq.underMaintenance
                                ? 'Commands are blocked while the equipment is locked out.'
                                : 'Lock the equipment out before working on it. Pumps must be stopped first.',
                          ),
                        ),
                        if (role.canMaintain)
                          FilledButton.tonal(
                            onPressed: _busy || (eq.isPump && eq.isEngaged && !eq.underMaintenance)
                                ? null
                                : () => setEquipmentMaintenance(context, ref, equipment: eq, underMaintenance: !eq.underMaintenance),
                            child: Text(eq.underMaintenance ? 'Return to service' : 'Lock out'),
                          ),
                        const SizedBox(width: 8),
                        IconButton(tooltip: 'Open equipment', onPressed: () => context.go('/equipment/${eq.id}'), icon: const Icon(Icons.open_in_new)),
                      ],
                    ),
                  ),
                ),
              ],
              if (_busy) const Padding(padding: EdgeInsets.only(top: 12), child: LinearProgressIndicator()),
            ],
          ),
        );
      },
    );
  }
}
