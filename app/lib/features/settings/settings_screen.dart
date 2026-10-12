import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/env.dart';
import '../../core/theme.dart';
import '../../providers/core_providers.dart';
import '../../providers/settings_providers.dart';
import '../../widgets/common.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final theme = Theme.of(context);

    return PageBody(
      maxWidth: 700,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(title: 'Appearance'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Theme', style: theme.textTheme.labelLarge),
                  const SizedBox(height: 8),
                  SegmentedButton<ThemeMode>(
                    segments: const [
                      ButtonSegment(value: ThemeMode.dark, label: Text('Dark'), icon: Icon(Icons.dark_mode_outlined)),
                      ButtonSegment(value: ThemeMode.light, label: Text('Light'), icon: Icon(Icons.light_mode_outlined)),
                      ButtonSegment(value: ThemeMode.system, label: Text('System'), icon: Icon(Icons.brightness_auto_outlined)),
                    ],
                    selected: {settings.themeMode},
                    onSelectionChanged: (s) => notifier.update(settings.copyWith(themeMode: s.first)),
                  ),
                  LabeledSwitch(
                    title: 'Show simulation clock in the top bar',
                    value: settings.showSimClock,
                    onChanged: (v) => notifier.update(settings.copyWith(showSimClock: v)),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          const SectionHeader(title: 'Live updates'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Simulation tick interval: ${settings.refreshSeconds} s', style: theme.textTheme.labelLarge),
                  Slider(
                    value: settings.refreshSeconds.toDouble(),
                    min: 1,
                    max: 10,
                    divisions: 9,
                    label: '${settings.refreshSeconds} s',
                    onChanged: (v) => notifier.update(settings.copyWith(refreshSeconds: v.round())),
                  ),
                  Text(
                    'How often this client asks the control API to advance the process. Updates pause automatically when the app is in the background or offline.',
                    style: theme.textTheme.bodySmall?.copyWith(color: AppColors.muted),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          const SectionHeader(title: 'Operations'),
          Card(
            child: Column(
              children: [
                LabeledSwitch(
                  title: 'Confirm commands',
                  subtitle: 'Ask before start, stop, open and close commands',
                  value: settings.confirmCommands,
                  onChanged: (v) => notifier.update(settings.copyWith(confirmCommands: v)),
                ),
                LabeledSwitch(
                  title: 'Critical alarm banner',
                  subtitle: 'Show a red banner on every page while a critical alarm is active',
                  value: settings.alarmBanner,
                  onChanged: (v) => notifier.update(settings.copyWith(alarmBanner: v)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const SectionHeader(title: 'Offline data'),
          Card(
            child: ListTile(
              leading: const Icon(Icons.cleaning_services_outlined),
              title: const Text('Clear cached data'),
              subtitle: const Text('Removes the saved snapshots used for the offline read-only view on this device.'),
              trailing: OutlinedButton(
                onPressed: () async {
                  await ref.read(offlineCacheProvider).clear();
                  if (context.mounted) showSnack(context, 'Offline cache cleared', success: true);
                },
                child: const Text('Clear'),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const SectionHeader(title: 'About'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const InfoRow('Application', 'ACME Control 1.0.0'),
                  InfoRow('Control API', Env.apiBaseUrl),
                  InfoRow('Supabase project', Uri.tryParse(Env.supabaseUrl)?.host ?? Env.supabaseUrl),
                  const InfoRow('Stack', 'Flutter · Material 3 · Riverpod · go_router · Supabase · Hono on Vercel'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
