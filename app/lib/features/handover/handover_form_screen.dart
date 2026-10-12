import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/formatters.dart';
import '../../core/security.dart';
import '../../core/theme.dart';
import '../../models/alarm.dart';
import '../../models/profile.dart';
import '../../models/shift_handover.dart';
import '../../providers/auth_providers.dart';
import '../../providers/connectivity_providers.dart';
import '../../providers/core_providers.dart';
import '../../providers/live_notifiers.dart';
import '../../providers/plant_providers.dart';
import '../../widgets/common.dart';

class HandoverFormScreen extends ConsumerStatefulWidget {
  const HandoverFormScreen({super.key});

  @override
  ConsumerState<HandoverFormScreen> createState() => _HandoverFormScreenState();
}

class _HandoverFormScreenState extends ConsumerState<HandoverFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _summary = TextEditingController();
  final _issue = TextEditingController();
  String _shift = DateTime.now().hour >= 6 && DateTime.now().hour < 18 ? 'day' : 'night';
  DateTime _date = DateTime.now();
  String? _toUserId;
  final List<String> _issues = [];
  final Map<String, bool> _checklist = {for (final k in ShiftHandover.checklistItems.keys) k: false};
  bool _busy = false;

  @override
  void dispose() {
    _summary.dispose();
    _issue.dispose();
    super.dispose();
  }

  static const _maxIssueLength = 500;

  void _addIssue() {
    final text = sanitizeText(_issue.text);
    if (text.isEmpty) return;
    if (text.length > _maxIssueLength) {
      showSnack(context, 'An issue can have at most $_maxIssueLength characters.', error: true);
      return;
    }
    setState(() {
      if (!_issues.contains(text)) _issues.add(text);
      _issue.clear();
    });
  }

  Future<void> _save({required bool submit}) async {
    if (!_formKey.currentState!.validate()) return;
    final plantId = ref.read(effectivePlantIdProvider);
    final profile = ref.read(profileProvider).value;
    if (plantId == null || profile == null) return;
    if (!ref.read(connectivityProvider)) {
      showSnack(context, 'Saving a handover requires a connection.', error: true);
      return;
    }
    final toUser = (ref.read(usersProvider).value ?? const <Profile>[]).where((u) => u.id == _toUserId).firstOrNull;
    setState(() => _busy = true);
    try {
      final h = await ref.read(handoverRepositoryProvider).create(
            plantId: plantId,
            shift: _shift,
            shiftDate: _date,
            fromUser: profile.id,
            fromUserName: profile.displayName,
            toUser: toUser?.id,
            toUserName: toUser?.displayName,
            summary: sanitizeText(_summary.text),
            openIssues: _issues.map(sanitizeText).where((i) => i.isNotEmpty).toList(),
            checklist: _checklist,
            submit: submit,
          );
      if (submit) {
        await ref.read(eventRepositoryProvider).log(plantId: plantId, category: 'handover', message: '${titleCase(_shift)} shift handover submitted', actor: profile.displayName, data: {'handover_id': h.id});
      }
      if (mounted) {
        showSnack(context, submit ? 'Handover submitted' : 'Draft saved', success: true);
        context.go('/handover/${h.id}');
      }
    } catch (e) {
      if (mounted) showSnack(context, describeError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final users = (ref.watch(usersProvider).value ?? const <Profile>[]).where((u) => u.id != ref.watch(currentUserIdProvider)).toList();
    final activeAlarms = ref.watch(activeAlarmsProvider);
    final theme = Theme.of(context);

    return PageBody(
      maxWidth: 760,
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                IconButton(onPressed: () => context.go('/handover'), icon: const Icon(Icons.arrow_back)),
                Text('New shift handover', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'day', label: Text('Day'), icon: Icon(Icons.wb_sunny_outlined)),
                      ButtonSegment(value: 'night', label: Text('Night'), icon: Icon(Icons.nightlight_outlined)),
                    ],
                    selected: {_shift},
                    onSelectionChanged: (s) => setState(() => _shift = s.first),
                  ),
                ),
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  onPressed: () async {
                    final d = await showDatePicker(context: context, initialDate: _date, firstDate: DateTime.now().subtract(const Duration(days: 30)), lastDate: DateTime.now().add(const Duration(days: 1)));
                    if (d != null) setState(() => _date = d);
                  },
                  icon: const Icon(Icons.event, size: 18),
                  label: Text(fmtDate(_date)),
                ),
              ],
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String?>(
              initialValue: _toUserId,
              decoration: const InputDecoration(labelText: 'Hand over to'),
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('Next operator on duty')),
                for (final u in users) DropdownMenuItem<String?>(value: u.id, child: Text('${u.displayName} · ${u.role.label}')),
              ],
              onChanged: (v) => setState(() => _toUserId = v),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _summary,
              maxLines: 5,
              textCapitalization: TextCapitalization.sentences,
              maxLength: kMaxLongText,
              maxLengthEnforcement: MaxLengthEnforcement.enforced,
              decoration: const InputDecoration(labelText: 'Shift summary', hintText: 'What happened, what was done, what to watch'),
              validator: (v) => validateRequiredText(v, label: 'a short summary', max: kMaxLongText, min: 10),
            ),
            if (activeAlarms.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Active alarms right now: ${activeAlarms.map((a) => a.code).join(', ')}', style: theme.textTheme.bodySmall?.copyWith(color: AppColors.warning)),
              TextButton.icon(
                onPressed: () => setState(() {
                  for (final a in activeAlarms) {
                    final text = '${a.code}: ${a.message}${a.state == AlarmState.active ? ' (unacknowledged)' : ''}';
                    if (!_issues.contains(text)) _issues.add(text);
                  }
                }),
                icon: const Icon(Icons.playlist_add, size: 18),
                label: const Text('Add active alarms as open issues'),
              ),
            ],
            const SizedBox(height: 14),
            Text('Open issues', style: theme.textTheme.labelLarge),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _issue,
                    textCapitalization: TextCapitalization.sentences,
                    maxLength: _maxIssueLength,
                    maxLengthEnforcement: MaxLengthEnforcement.enforced,
                    buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
                    decoration: const InputDecoration(hintText: 'Add an issue for the next shift'),
                    onSubmitted: (_) => _addIssue(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(onPressed: _addIssue, icon: const Icon(Icons.add)),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final i in _issues) Chip(label: Text(i), onDeleted: () => setState(() => _issues.remove(i))),
              ],
            ),
            const SizedBox(height: 14),
            Text('Checklist', style: theme.textTheme.labelLarge),
            Card(
              child: Column(
                children: [
                  for (final item in ShiftHandover.checklistItems.entries)
                    CheckboxListTile(
                      value: _checklist[item.key] ?? false,
                      title: Text(item.value),
                      controlAffinity: ListTileControlAffinity.leading,
                      onChanged: (v) => setState(() => _checklist[item.key] = v ?? false),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(child: OutlinedButton(onPressed: _busy ? null : () => _save(submit: false), child: const Text('Save draft'))),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    onPressed: _busy ? null : () => _save(submit: true),
                    icon: _busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send_outlined),
                    label: const Text('Submit handover'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
