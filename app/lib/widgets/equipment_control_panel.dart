import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/formatters.dart';
import '../core/security.dart';
import '../core/theme.dart';
import '../models/equipment.dart';
import '../providers/auth_providers.dart';
import '../providers/connectivity_providers.dart';
import '../providers/core_providers.dart';
import '../providers/live_notifiers.dart';
import '../providers/settings_providers.dart';
import '../services/api_client.dart';
import 'common.dart';

/// Opens the control panel for a piece of equipment as a bottom sheet (phones)
/// or a dialog (wide screens).
Future<void> showEquipmentControlSheet(BuildContext context, Equipment equipment) {
  final wide = MediaQuery.sizeOf(context).width >= 760;
  if (wide) {
    return showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: EquipmentControlPanel(equipmentId: equipment.id, showDetailsLink: true),
            ),
          ),
        ),
      ),
    );
  }
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.72,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      builder: (_, controller) => SingleChildScrollView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
        child: EquipmentControlPanel(equipmentId: equipment.id, showDetailsLink: true),
      ),
    ),
  );
}

/// Sends a command through the API with optional confirmation and user feedback.
Future<bool> sendEquipmentCommand(
  BuildContext context,
  WidgetRef ref, {
  required Equipment equipment,
  required String type,
  Object? value,
  bool confirm = true,
}) async {
  final settings = ref.read(settingsProvider);
  if (!ref.read(canControlProvider)) {
    showSnack(context, 'Control actions require a connection. You are offline or the control API is unreachable.', error: true);
    return false;
  }
  final label = type == 'set_mode' ? 'Switch ${equipment.tag} to ${value == 'auto' ? 'automatic' : 'manual'} mode' : '${titleCase(type)} ${equipment.tag} ${equipment.name}';
  if (confirm && settings.confirmCommands && type != 'set_mode') {
    final ok = await confirmDialog(context, title: 'Confirm command', message: '$label?', confirmLabel: titleCase(type));
    if (!ok) return false;
  }
  try {
    await ref.read(apiClientProvider).sendCommand(
          plantId: equipment.plantId,
          equipmentId: equipment.id,
          type: type,
          value: value,
        );
    ref.read(apiReachableProvider.notifier).set(true);
    if (context.mounted) showSnack(context, '$label - accepted', success: true);
    return true;
  } on ApiException catch (e) {
    if (e.isNetwork) ref.read(apiReachableProvider.notifier).set(false);
    if (context.mounted) showSnack(context, e.isRejected ? 'Command rejected: ${e.message}' : e.message, error: true);
    return false;
  } catch (e) {
    if (context.mounted) showSnack(context, describeError(e), error: true);
    return false;
  }
}

Future<bool> setEquipmentMaintenance(
  BuildContext context,
  WidgetRef ref, {
  required Equipment equipment,
  required bool underMaintenance,
}) async {
  if (!ref.read(canControlProvider)) {
    showSnack(context, 'Maintenance lockout requires a connection.', error: true);
    return false;
  }
  final noteController = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(underMaintenance ? 'Place ${equipment.tag} under maintenance' : 'Return ${equipment.tag} to service'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            underMaintenance
                ? 'The equipment will be locked out: it cannot be started or operated until it is returned to service.'
                : 'The lockout will be removed. The equipment returns in the stopped state.',
          ),
          const SizedBox(height: 14),
          TextField(
            controller: noteController,
            decoration: const InputDecoration(labelText: 'Note (optional)', hintText: 'e.g. Seal replacement, WO-01042'),
            maxLines: 2,
            maxLength: kMaxShortText,
            maxLengthEnforcement: MaxLengthEnforcement.enforced,
            buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(underMaintenance ? 'Lock out' : 'Return to service')),
      ],
    ),
  );
  if (ok != true) return false;
  try {
    await ref.read(apiClientProvider).setMaintenance(equipment.id, underMaintenance: underMaintenance, note: sanitizeText(noteController.text));
    if (context.mounted) {
      showSnack(context, underMaintenance ? '${equipment.tag} placed under maintenance' : '${equipment.tag} returned to service', success: true);
    }
    return true;
  } on ApiException catch (e) {
    if (context.mounted) showSnack(context, e.message, error: true);
    return false;
  } catch (e) {
    if (context.mounted) showSnack(context, describeError(e), error: true);
    return false;
  }
}

class EquipmentControlPanel extends ConsumerStatefulWidget {
  const EquipmentControlPanel({super.key, required this.equipmentId, this.showDetailsLink = false});

  final String equipmentId;
  final bool showDetailsLink;

  @override
  ConsumerState<EquipmentControlPanel> createState() => _EquipmentControlPanelState();
}

class _EquipmentControlPanelState extends ConsumerState<EquipmentControlPanel> {
  bool _busy = false;

  Future<void> _run(Future<bool> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final live = ref.watch(equipmentProvider);
    final list = live.data ?? const <Equipment>[];
    Equipment? eq;
    for (final e in list) {
      if (e.id == widget.equipmentId) eq = e;
    }
    if (eq == null) {
      return const Padding(padding: EdgeInsets.all(24), child: Text('Equipment not available.'));
    }
    final equipment = eq;
    final role = ref.watch(roleProvider);
    final canControl = ref.watch(canControlProvider);
    final state = ref.watch(processStateProvider).data;
    final theme = Theme.of(context);
    final color = equipmentStateColor(equipment);

    final flowTag = equipment.isPump ? _sensorFor(list, 'flow', equipment.tag) : null;
    final pressureTag = equipment.isPump ? _sensorFor(list, 'pressure', equipment.tag) : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(12)),
              child: Icon(_iconFor(equipment), color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${equipment.tag} · ${equipment.name}', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  Text(
                    '${titleCase(equipment.type.name)} · ${equipment.area ?? ''}',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            if (widget.showDetailsLink)
              IconButton(
                tooltip: 'Open details',
                onPressed: () {
                  Navigator.of(context).pop();
                  context.go('/equipment/${equipment.id}');
                },
                icon: const Icon(Icons.open_in_new, size: 20),
              ),
          ],
        ),
        const SizedBox(height: 16),
        StaleNotice(live),
        _RequestedActual(equipment: equipment),
        const SizedBox(height: 12),
        if (equipment.underMaintenance)
          _Note(color: AppColors.maintenance, icon: Icons.build_circle_outlined, text: 'Under maintenance - commands are blocked until it is returned to service.'),
        if (equipment.isTripped)
          _Note(color: AppColors.critical, icon: Icons.report_outlined, text: 'Tripped: ${equipment.fault ?? 'protection'}. Reset is required before restarting.'),
        if (!equipment.isTripped && equipment.interlock != null && equipment.interlock!.isNotEmpty)
          _Note(color: AppColors.warning, icon: Icons.lock_outline, text: 'Interlock: ${equipment.interlock}'),
        if (equipment.isControllable) ...[
          Wrap(
            spacing: 18,
            runSpacing: 8,
            children: [
              if (equipment.isPump) _Metric('Speed', '${fmtNum(equipment.position, decimals: 0)} %'),
              if (equipment.isValve) _Metric('Position', '${fmtNum(equipment.position, decimals: 0)} % open'),
              if (flowTag != null) _Metric('Flow ($flowTag)', '${fmtNum(state?.value(flowTag))} m³/h'),
              if (pressureTag != null) _Metric('Pressure ($pressureTag)', '${fmtNum(state?.value(pressureTag), decimals: 2)} bar'),
              if (equipment.isPump) _Metric('Runtime', fmtHours(equipment.runtimeHours)),
              if (equipment.isPump) _Metric('Starts', '${equipment.startsCount}'),
            ],
          ),
          const SizedBox(height: 16),
        ],
        if (equipment.isControllable && role.canOperate) ...[
          Text('Mode', style: theme.textTheme.labelLarge),
          const SizedBox(height: 6),
          SegmentedButton<EquipmentMode>(
            segments: const [
              ButtonSegment(value: EquipmentMode.manual, label: Text('Manual'), icon: Icon(Icons.pan_tool_outlined)),
              ButtonSegment(value: EquipmentMode.auto, label: Text('Automatic'), icon: Icon(Icons.autorenew)),
            ],
            selected: {equipment.mode},
            onSelectionChanged: (_busy || !canControl || equipment.underMaintenance)
                ? null
                : (set) => _run(() => sendEquipmentCommand(context, ref, equipment: equipment, type: 'set_mode', value: set.first.name)),
          ),
          const SizedBox(height: 14),
          Text(equipment.isPump ? 'Pump control' : 'Valve control', style: theme.textTheme.labelLarge),
          const SizedBox(height: 6),
          if (equipment.isAuto)
            Text(
              'Automatic mode: the controller decides. Switch to manual to operate it by hand.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              if (equipment.isPump) ...[
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: AppColors.running, foregroundColor: Colors.black),
                    onPressed: _enabled(equipment, canControl) && equipment.requestedState != 'run' && !equipment.isTripped
                        ? () => _run(() => sendEquipmentCommand(context, ref, equipment: equipment, type: 'start'))
                        : null,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Start'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: AppColors.danger, foregroundColor: Colors.black),
                    onPressed: _enabled(equipment, canControl) && !(equipment.requestedState == 'stop' && equipment.actualState == 'stopped')
                        ? () => _run(() => sendEquipmentCommand(context, ref, equipment: equipment, type: 'stop'))
                        : null,
                    icon: const Icon(Icons.stop),
                    label: const Text('Stop'),
                  ),
                ),
              ],
              if (equipment.isValve) ...[
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: AppColors.running, foregroundColor: Colors.black),
                    onPressed: _enabled(equipment, canControl) && equipment.requestedState != 'open'
                        ? () => _run(() => sendEquipmentCommand(context, ref, equipment: equipment, type: 'open'))
                        : null,
                    icon: const Icon(Icons.radio_button_unchecked),
                    label: const Text('Open'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: AppColors.steel, foregroundColor: Colors.black),
                    onPressed: _enabled(equipment, canControl) && equipment.requestedState != 'close'
                        ? () => _run(() => sendEquipmentCommand(context, ref, equipment: equipment, type: 'close'))
                        : null,
                    icon: const Icon(Icons.close),
                    label: const Text('Close'),
                  ),
                ),
              ],
            ],
          ),
          if (equipment.isTripped) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _busy || !canControl ? null : () => _run(() => sendEquipmentCommand(context, ref, equipment: equipment, type: 'reset', confirm: false)),
              icon: const Icon(Icons.restart_alt),
              label: const Text('Reset trip'),
            ),
          ],
          if (!canControl)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                'Controls are disabled while offline.',
                style: theme.textTheme.bodySmall?.copyWith(color: AppColors.warning),
              ),
            ),
        ],
        if (equipment.isControllable && !role.canOperate)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Your role (${role.label}) can view this equipment but not operate it.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        if (role.canMaintain && equipment.isControllable) ...[
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.build_outlined, size: 18, color: AppColors.maintenance),
              const SizedBox(width: 8),
              Expanded(child: Text('Maintenance lockout', style: theme.textTheme.labelLarge)),
              OutlinedButton(
                onPressed: _busy || !canControl || (equipment.isPump && equipment.isEngaged && !equipment.underMaintenance)
                    ? null
                    : () => _run(() => setEquipmentMaintenance(context, ref, equipment: equipment, underMaintenance: !equipment.underMaintenance)),
                child: Text(equipment.underMaintenance ? 'Return to service' : 'Lock out'),
              ),
            ],
          ),
          if (equipment.isPump && equipment.isEngaged && !equipment.underMaintenance)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('Stop the pump before locking it out.', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ),
        ],
        if (_busy) const Padding(padding: EdgeInsets.only(top: 12), child: LinearProgressIndicator()),
      ],
    );
  }

  bool _enabled(Equipment e, bool canControl) => !_busy && canControl && !e.isAuto && !e.underMaintenance;

  String? _sensorFor(List<Equipment> list, String kind, String pumpTag) {
    for (final e in list) {
      if (e.isSensor && e.params['kind'] == kind && e.params['pump'] == pumpTag) return e.tag;
    }
    return null;
  }

  IconData _iconFor(Equipment e) {
    switch (e.type) {
      case EquipmentType.pump:
        return Icons.settings_input_component_outlined;
      case EquipmentType.valve:
        return Icons.adjust;
      case EquipmentType.tank:
        return Icons.water;
      case EquipmentType.sensor:
        return Icons.sensors;
    }
  }
}

class _RequestedActual extends StatelessWidget {
  const _RequestedActual({required this.equipment});

  final Equipment equipment;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final actualColor = equipmentStateColor(equipment);
    final requestedColor = equipment.requestedState == 'run' || equipment.requestedState == 'open' ? AppColors.running : AppColors.steel;
    if (!equipment.isControllable) {
      return Row(
        children: [
          _StateBox(title: 'State', value: equipment.actualLabel, color: equipment.underMaintenance ? AppColors.maintenance : AppColors.primary),
          const SizedBox(width: 10),
          if (equipment.isTank) _StateBox(title: 'Level', value: '${fmtNum(equipment.position)} %', color: AppColors.water),
        ],
      );
    }
    return Row(
      children: [
        _StateBox(title: 'Requested', value: equipment.requestedLabel, color: requestedColor),
        const SizedBox(width: 10),
        Icon(
          equipment.inSync ? Icons.check_circle_outline : Icons.sync,
          color: equipment.inSync ? AppColors.running : AppColors.warning,
          size: 20,
        ),
        const SizedBox(width: 10),
        _StateBox(title: 'Actual', value: equipment.underMaintenance ? 'Maintenance' : equipment.actualLabel, color: actualColor),
        const SizedBox(width: 10),
        StatusChip(
          label: equipment.isAuto ? 'AUTO' : 'MANUAL',
          color: equipment.isAuto ? theme.colorScheme.primary : AppColors.warning,
          dense: true,
          outlined: true,
        ),
      ],
    );
  }
}

class _StateBox extends StatelessWidget {
  const _StateBox({required this.title, required this.value, required this.color});

  final String title;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title.toUpperCase(), style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant, letterSpacing: 0.6)),
            const SizedBox(height: 2),
            Text(value, style: theme.textTheme.titleMedium?.copyWith(color: color, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric(this.label, this.value);

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
        Text(value, style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.color, required this.icon, required this.text});

  final Color color;
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(10)),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }
}
