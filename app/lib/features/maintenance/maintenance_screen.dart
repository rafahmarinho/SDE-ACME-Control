import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/formatters.dart';
import '../../models/maintenance_order.dart';
import '../../providers/auth_providers.dart';
import '../../providers/live_notifiers.dart';
import '../../widgets/common.dart';
import 'maintenance_tile.dart';

class MaintenanceScreen extends ConsumerStatefulWidget {
  const MaintenanceScreen({super.key});

  @override
  ConsumerState<MaintenanceScreen> createState() => _MaintenanceScreenState();
}

class _MaintenanceScreenState extends ConsumerState<MaintenanceScreen> {
  MaintenanceStatus? _status;
  bool _openOnly = true;
  MaintenancePriority? _priority;
  String _query = '';

  bool _matches(MaintenanceOrder o) {
    if (_status != null && o.status != _status) return false;
    if (_status == null && _openOnly && o.isClosed) return false;
    if (_priority != null && o.priority != _priority) return false;
    if (_query.isEmpty) return true;
    final q = _query.toLowerCase();
    return o.title.toLowerCase().contains(q) ||
        o.code.toLowerCase().contains(q) ||
        o.description.toLowerCase().contains(q) ||
        (o.equipmentTag ?? '').toLowerCase().contains(q) ||
        (o.assignedToName ?? '').toLowerCase().contains(q);
  }

  @override
  Widget build(BuildContext context) {
    final live = ref.watch(maintenanceOrdersProvider);
    final role = ref.watch(roleProvider);
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: role.canMaintain
          ? FloatingActionButton.extended(
              onPressed: () => context.go('/maintenance/new'),
              icon: const Icon(Icons.add),
              label: const Text('New work order'),
            )
          : null,
      body: LiveBuilder<List<MaintenanceOrder>>(
        live: live,
        onRetry: () => ref.read(maintenanceOrdersProvider.notifier).refresh(),
        builder: (context, all) {
          final list = all.where(_matches).toList();
          final open = all.where((o) => o.status == MaintenanceStatus.open).length;
          final inProgress = all.where((o) => o.status == MaintenanceStatus.inProgress).length;
          return RefreshIndicator(
            onRefresh: () async => ref.read(maintenanceOrdersProvider.notifier).refresh(),
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
                      ChoiceChip(
                        label: Text('Open & in progress ($open + $inProgress)'),
                        selected: _status == null && _openOnly,
                        onSelected: (_) => setState(() {
                          _status = null;
                          _openOnly = true;
                        }),
                      ),
                      for (final s in MaintenanceStatus.values)
                        ChoiceChip(label: Text(maintenanceStatusLabel(s)), selected: _status == s, onSelected: (_) => setState(() => _status = s)),
                      ChoiceChip(
                        label: const Text('All'),
                        selected: _status == null && !_openOnly,
                        onSelected: (_) => setState(() {
                          _status = null;
                          _openOnly = false;
                        }),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SearchField(hint: 'Search title, code, equipment or assignee', onChanged: (v) => setState(() => _query = v)),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final p in MaintenancePriority.values)
                        FilterChip(
                          avatar: CircleAvatar(backgroundColor: priorityColor(p), radius: 5),
                          label: Text(titleCase(p.name)),
                          selected: _priority == p,
                          onSelected: (v) => setState(() => _priority = v ? p : null),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  if (list.isEmpty)
                    EmptyView(
                      icon: Icons.build_outlined,
                      title: 'No work orders match the filters',
                      action: role.canMaintain ? FilledButton.icon(onPressed: () => context.go('/maintenance/new'), icon: const Icon(Icons.add), label: const Text('Create work order')) : null,
                    )
                  else
                    Card(
                      child: ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: list.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, i) => MaintenanceTile(order: list[i]),
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
