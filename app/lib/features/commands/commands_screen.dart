import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../models/command.dart';
import '../../models/equipment.dart';
import '../../providers/auth_providers.dart';
import '../../providers/live_notifiers.dart';
import '../../widgets/common.dart';
import '../../widgets/equipment_control_panel.dart';

class CommandsScreen extends ConsumerStatefulWidget {
  const CommandsScreen({super.key});

  @override
  ConsumerState<CommandsScreen> createState() => _CommandsScreenState();
}

class _CommandsScreenState extends ConsumerState<CommandsScreen> {
  CommandStatus? _status;
  String? _tag;
  String _query = '';

  bool _matches(CommandRecord c) {
    if (_status != null && c.status != _status) return false;
    if (_tag != null && c.equipmentTag != _tag) return false;
    if (_query.isEmpty) return true;
    final q = _query.toLowerCase();
    return (c.equipmentTag ?? '').toLowerCase().contains(q) ||
        (c.userName ?? '').toLowerCase().contains(q) ||
        c.label.toLowerCase().contains(q) ||
        (c.reason ?? '').toLowerCase().contains(q);
  }

  @override
  Widget build(BuildContext context) {
    final live = ref.watch(commandsProvider);
    final equipment = (ref.watch(equipmentProvider).data ?? const <Equipment>[]).where((e) => e.isControllable).toList();
    final role = ref.watch(roleProvider);
    final theme = Theme.of(context);

    return LiveBuilder<List<CommandRecord>>(
      live: live,
      onRetry: () => ref.read(commandsProvider.notifier).refresh(),
      builder: (context, all) {
        final list = all.where(_matches).toList();
        return RefreshIndicator(
          onRefresh: () async => ref.read(commandsProvider.notifier).refresh(),
          child: PageBody(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                StaleNotice(live),
                if (role.canOperate) ...[
                  const SectionHeader(title: 'Quick actions', subtitle: 'Open the control panel of a pump or valve'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final e in equipment)
                        ActionChip(
                          avatar: Container(width: 10, height: 10, decoration: BoxDecoration(shape: BoxShape.circle, color: equipmentStateColor(e))),
                          label: Text('${e.tag} · ${e.underMaintenance ? 'Maintenance' : e.actualLabel}'),
                          onPressed: () => showEquipmentControlSheet(context, e),
                        ),
                    ],
                  ),
                  const SizedBox(height: 18),
                ],
                SectionHeader(title: 'Command log', subtitle: '${list.length} of ${all.length} commands'),
                Row(
                  children: [
                    Expanded(child: SearchField(hint: 'Search equipment, user or reason', onChanged: (v) => setState(() => _query = v))),
                    const SizedBox(width: 10),
                    DropdownMenu<String?>(
                      initialSelection: _tag,
                      hintText: 'Equipment',
                      width: 140,
                      inputDecorationTheme: const InputDecorationTheme(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 12)),
                      dropdownMenuEntries: [
                        const DropdownMenuEntry<String?>(value: null, label: 'All'),
                        for (final e in equipment) DropdownMenuEntry<String?>(value: e.tag, label: e.tag),
                      ],
                      onSelected: (v) => setState(() => _tag = v),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(label: const Text('All'), selected: _status == null, onSelected: (_) => setState(() => _status = null)),
                    for (final s in [CommandStatus.executed, CommandStatus.rejected, CommandStatus.accepted, CommandStatus.failed])
                      ChoiceChip(label: Text(titleCase(s.name)), selected: _status == s, onSelected: (_) => setState(() => _status = s)),
                  ],
                ),
                const SizedBox(height: 14),
                if (list.isEmpty)
                  const EmptyView(icon: Icons.terminal_outlined, title: 'No commands match the filters')
                else
                  Card(
                    child: ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: list.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final c = list[i];
                        final color = commandStatusColor(c.status.name);
                        return ListTile(
                          leading: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(10)),
                            child: Icon(_iconFor(c.type), color: color, size: 20),
                          ),
                          title: Text('${c.equipmentTag ?? '?'} · ${c.label}', style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${c.userName ?? 'unknown'} · ${fmtDateTimeSeconds(c.createdAt)}', style: theme.textTheme.bodySmall),
                              if (c.reason != null && c.reason!.isNotEmpty)
                                Text(c.reason!, style: theme.textTheme.bodySmall?.copyWith(color: AppColors.danger)),
                            ],
                          ),
                          trailing: StatusChip(label: titleCase(c.status.name), color: color, dense: true),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  IconData _iconFor(String type) {
    switch (type) {
      case 'start':
        return Icons.play_arrow;
      case 'stop':
        return Icons.stop;
      case 'open':
        return Icons.radio_button_unchecked;
      case 'close':
        return Icons.close;
      case 'reset':
        return Icons.restart_alt;
      case 'set_mode':
        return Icons.autorenew;
      default:
        return Icons.terminal_outlined;
    }
  }
}
