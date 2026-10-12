import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../models/plant.dart';
import '../../models/profile.dart';
import '../../providers/auth_providers.dart';
import '../../providers/connectivity_providers.dart';
import '../../providers/core_providers.dart';
import '../../providers/plant_providers.dart';
import '../../widgets/common.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  String? _defaultPlantId;
  bool _initialised = false;
  bool _busy = false;
  bool _uploading = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  void _init(Profile p) {
    if (_initialised) return;
    _initialised = true;
    _name.text = p.fullName;
    _phone.text = p.phone ?? '';
    _defaultPlantId = p.defaultPlantId;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (!ref.read(connectivityProvider)) {
      showSnack(context, 'Saving your profile requires a connection.', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(profileProvider.notifier).save(fullName: _name.text, phone: _phone.text, defaultPlantId: _defaultPlantId);
      if (mounted) showSnack(context, 'Profile saved', success: true);
    } catch (e) {
      if (mounted) showSnack(context, describeError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickAvatar() async {
    final profile = ref.read(profileProvider).value;
    if (profile == null) return;
    if (!ref.read(connectivityProvider)) {
      showSnack(context, 'Uploading a picture requires a connection.', error: true);
      return;
    }
    try {
      final picked = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 512, maxHeight: 512, imageQuality: 85);
      if (picked == null) return;
      setState(() => _uploading = true);
      final bytes = await picked.readAsBytes();
      final ext = picked.name.split('.').last.toLowerCase();
      final contentType = picked.mimeType ?? (ext == 'png' ? 'image/png' : ext == 'webp' ? 'image/webp' : 'image/jpeg');
      final url = await ref.read(authServiceProvider).uploadAvatar(profile.id, bytes, contentType);
      await ref.read(profileProvider.notifier).save(avatarUrl: url);
      if (mounted) showSnack(context, 'Profile picture updated', success: true);
    } catch (e) {
      if (mounted) showSnack(context, 'Upload failed: ${describeError(e)}', error: true);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(profileProvider);
    final plants = ref.watch(plantsProvider).value ?? const <Plant>[];
    final theme = Theme.of(context);

    return profileAsync.when(
      loading: () => const LoadingView(message: 'Loading profile…'),
      error: (e, _) => ErrorView(error: e, onRetry: () => ref.read(profileProvider.notifier).refresh()),
      data: (profile) {
        if (profile == null) return const EmptyView(title: 'Not signed in');
        _init(profile);
        return PageBody(
          maxWidth: 700,
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: [
                        Stack(
                          children: [
                            UserAvatar(initials: profile.initials, imageUrl: profile.avatarUrl, radius: 36),
                            Positioned(
                              right: -4,
                              bottom: -4,
                              child: IconButton.filled(
                                tooltip: 'Change picture',
                                onPressed: _uploading ? null : _pickAvatar,
                                icon: _uploading ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.photo_camera_outlined, size: 16),
                                iconSize: 16,
                                padding: const EdgeInsets.all(6),
                                constraints: const BoxConstraints(),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(width: 18),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(profile.displayName, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                              Text(profile.email, style: theme.textTheme.bodySmall?.copyWith(color: AppColors.muted)),
                              const SizedBox(height: 8),
                              StatusChip(label: profile.role.label, color: AppColors.primary, icon: Icons.badge_outlined),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Full name', prefixIcon: Icon(Icons.person_outline)),
                  validator: (v) => (v == null || v.trim().length < 2) ? 'Enter your name' : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Phone', prefixIcon: Icon(Icons.phone_outlined), hintText: 'Used for on-call notifications (simulated)'),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  initialValue: profile.email,
                  readOnly: true,
                  enabled: false,
                  decoration: const InputDecoration(labelText: 'E-mail (sign-in)', prefixIcon: Icon(Icons.mail_outline)),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String?>(
                  initialValue: _defaultPlantId,
                  decoration: const InputDecoration(labelText: 'Default plant', prefixIcon: Icon(Icons.factory_outlined)),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('First available plant')),
                    for (final p in plants) DropdownMenuItem<String?>(value: p.id, child: Text('${p.code} · ${p.name}')),
                  ],
                  onChanged: (v) => setState(() => _defaultPlantId = v),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _busy ? null : _save,
                  icon: _busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save_outlined),
                  label: const Text('Save profile'),
                ),
                const SizedBox(height: 10),
                Text(
                  'Roles are assigned by a supervisor. Profile updated ${fmtRelative(profile.updatedAt)}.',
                  style: theme.textTheme.bodySmall?.copyWith(color: AppColors.muted),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
