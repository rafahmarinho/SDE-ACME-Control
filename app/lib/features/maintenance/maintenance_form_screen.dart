import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../models/equipment.dart';
import '../../models/maintenance_order.dart';
import '../../models/profile.dart';
import '../../providers/auth_providers.dart';
import '../../providers/connectivity_providers.dart';
import '../../providers/core_providers.dart';
import '../../providers/live_notifiers.dart';
import '../../providers/plant_providers.dart';
import '../../widgets/common.dart';

class MaintenanceFormScreen extends ConsumerStatefulWidget {
  const MaintenanceFormScreen({super.key, this.equipmentId});

  final String? equipmentId;

  @override
  ConsumerState<MaintenanceFormScreen> createState() => _MaintenanceFormScreenState();
}

class _MaintenanceFormScreenState extends ConsumerState<MaintenanceFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _description = TextEditingController();
  MaintenancePriority _priority = MaintenancePriority.medium;
  String? _equipmentId;
  String? _assigneeId;
  DateTime? _scheduledFor;
  final List<Attachment> _attachments = [];
  bool _busy = false;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    _equipmentId = widget.equipmentId;
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    final plantId = ref.read(effectivePlantIdProvider);
    if (plantId == null) return;
    if (!ref.read(connectivityProvider)) {
      showSnack(context, 'Uploading attachments requires a connection.', error: true);
      return;
    }
    try {
      final picked = await ImagePicker().pickImage(source: source, maxWidth: 1600, imageQuality: 85);
      if (picked == null) return;
      setState(() => _uploading = true);
      final bytes = await picked.readAsBytes();
      final name = picked.name.isNotEmpty ? picked.name : 'photo.jpg';
      final ext = name.split('.').last.toLowerCase();
      final contentType = picked.mimeType ?? (ext == 'png' ? 'image/png' : ext == 'webp' ? 'image/webp' : 'image/jpeg');
      final attachment = await ref.read(maintenanceRepositoryProvider).uploadAttachment(plantId: plantId, bytes: bytes, fileName: name, contentType: contentType);
      setState(() => _attachments.add(attachment));
    } catch (e) {
      if (mounted) showSnack(context, 'Upload failed: ${describeError(e)}', error: true);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final date = await showDatePicker(context: context, initialDate: _scheduledFor ?? now, firstDate: now.subtract(const Duration(days: 1)), lastDate: now.add(const Duration(days: 365)));
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_scheduledFor ?? now.add(const Duration(hours: 1))));
    setState(() => _scheduledFor = DateTime(date.year, date.month, date.day, time?.hour ?? 8, time?.minute ?? 0));
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final plantId = ref.read(effectivePlantIdProvider);
    final profile = ref.read(profileProvider).value;
    if (plantId == null || profile == null) return;
    if (!ref.read(connectivityProvider)) {
      showSnack(context, 'Creating a work order requires a connection.', error: true);
      return;
    }
    final equipment = (ref.read(equipmentProvider).data ?? const <Equipment>[]).where((e) => e.id == _equipmentId).firstOrNull;
    final assignee = (ref.read(usersProvider).value ?? const <Profile>[]).where((u) => u.id == _assigneeId).firstOrNull;
    setState(() => _busy = true);
    try {
      final order = await ref.read(maintenanceRepositoryProvider).create(
            plantId: plantId,
            title: _title.text,
            description: _description.text,
            priority: _priority,
            createdBy: profile.id,
            createdByName: profile.displayName,
            equipmentId: equipment?.id,
            equipmentTag: equipment?.tag,
            assignedTo: assignee?.id,
            assignedToName: assignee?.displayName,
            scheduledFor: _scheduledFor,
            attachments: _attachments,
          );
      final events = ref.read(eventRepositoryProvider);
      await events.log(plantId: plantId, category: 'maintenance', message: 'Work order created: ${order.code} ${order.title}', actor: profile.displayName, data: {'order_id': order.id, 'tag': equipment?.tag});
      await events.log(plantId: plantId, category: 'integration', message: 'Simulated CMMS sync: work order ${order.code} exported', actor: 'system', data: {'system': 'CMMS', 'order_id': order.id});
      if (mounted) {
        showSnack(context, 'Work order ${order.code} created', success: true);
        context.go('/maintenance/${order.id}');
      }
    } catch (e) {
      if (mounted) showSnack(context, describeError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final equipment = ref.watch(equipmentProvider).data ?? const <Equipment>[];
    final users = ref.watch(usersProvider).value ?? const <Profile>[];
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
                IconButton(onPressed: () => context.go('/maintenance'), icon: const Icon(Icons.arrow_back)),
                Text('New work order', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _title,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Title', hintText: 'e.g. Replace mechanical seal on P1'),
              validator: (v) => (v == null || v.trim().length < 4) ? 'Enter a title (at least 4 characters)' : null,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _description,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Description', hintText: 'What needs to be done, findings, safety notes'),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String?>(
              initialValue: _equipmentId,
              decoration: const InputDecoration(labelText: 'Equipment'),
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('No specific equipment')),
                for (final e in equipment) DropdownMenuItem<String?>(value: e.id, child: Text('${e.tag} · ${e.name}')),
              ],
              onChanged: (v) => setState(() => _equipmentId = v),
            ),
            const SizedBox(height: 14),
            Text('Priority', style: theme.textTheme.labelLarge),
            const SizedBox(height: 6),
            SegmentedButton<MaintenancePriority>(
              segments: [
                for (final p in MaintenancePriority.values) ButtonSegment(value: p, label: Text(titleCase(p.name))),
              ],
              selected: {_priority},
              onSelectionChanged: (s) => setState(() => _priority = s.first),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String?>(
              initialValue: _assigneeId,
              decoration: const InputDecoration(labelText: 'Assign to'),
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('Unassigned')),
                for (final u in users) DropdownMenuItem<String?>(value: u.id, child: Text('${u.displayName} · ${u.role.label}')),
              ],
              onChanged: (v) => setState(() => _assigneeId = v),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: _pickDate,
              icon: const Icon(Icons.event),
              label: Text(_scheduledFor == null ? 'Schedule (optional)' : 'Scheduled for ${fmtDateTime(_scheduledFor)}'),
            ),
            const SizedBox(height: 18),
            Text('Attachments', style: theme.textTheme.labelLarge),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final a in _attachments)
                  Chip(
                    avatar: Icon(a.isImage ? Icons.image_outlined : Icons.attach_file, size: 16),
                    label: Text(a.name, overflow: TextOverflow.ellipsis),
                    onDeleted: () => setState(() => _attachments.remove(a)),
                  ),
                ActionChip(
                  avatar: _uploading ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.photo_library_outlined, size: 16),
                  label: const Text('Add photo'),
                  onPressed: _uploading ? null : () => _pickImage(ImageSource.gallery),
                ),
                if (!kIsWeb)
                  ActionChip(
                    avatar: const Icon(Icons.photo_camera_outlined, size: 16),
                    label: const Text('Take photo'),
                    onPressed: _uploading ? null : () => _pickImage(ImageSource.camera),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(child: OutlinedButton(onPressed: _busy ? null : () => context.go('/maintenance'), child: const Text('Cancel'))),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    onPressed: _busy || _uploading ? null : _save,
                    icon: _busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save_outlined),
                    label: const Text('Create work order'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('A simulated CMMS export is journaled when the order is created.', style: theme.textTheme.bodySmall?.copyWith(color: AppColors.muted)),
          ],
        ),
      ),
    );
  }
}
