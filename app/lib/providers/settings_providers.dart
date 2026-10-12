import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_providers.dart';
import 'core_providers.dart';

class AppSettings {
  const AppSettings({
    this.themeMode = ThemeMode.dark,
    this.refreshSeconds = 2,
    this.confirmCommands = true,
    this.alarmBanner = true,
    this.showSimClock = true,
  });

  final ThemeMode themeMode;

  /// Seconds between simulation ticks requested by this client.
  final int refreshSeconds;

  /// Ask for confirmation before start/stop/open/close commands.
  final bool confirmCommands;

  /// Show a banner at the top of every page while critical alarms are active.
  final bool alarmBanner;

  final bool showSimClock;

  AppSettings copyWith({
    ThemeMode? themeMode,
    int? refreshSeconds,
    bool? confirmCommands,
    bool? alarmBanner,
    bool? showSimClock,
  }) =>
      AppSettings(
        themeMode: themeMode ?? this.themeMode,
        refreshSeconds: refreshSeconds ?? this.refreshSeconds,
        confirmCommands: confirmCommands ?? this.confirmCommands,
        alarmBanner: alarmBanner ?? this.alarmBanner,
        showSimClock: showSimClock ?? this.showSimClock,
      );

  Map<String, dynamic> toJson() => {
        'theme': themeMode.name,
        'refresh_seconds': refreshSeconds,
        'confirm_commands': confirmCommands,
        'alarm_banner': alarmBanner,
        'show_sim_clock': showSimClock,
      };

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
        themeMode: ThemeMode.values.firstWhere(
          (m) => m.name == json['theme'],
          orElse: () => ThemeMode.dark,
        ),
        refreshSeconds: (json['refresh_seconds'] as num?)?.toInt().clamp(1, 15) ?? 2,
        confirmCommands: json['confirm_commands'] != false,
        alarmBanner: json['alarm_banner'] != false,
        showSimClock: json['show_sim_clock'] != false,
      );
}

class SettingsNotifier extends Notifier<AppSettings> {
  static const _key = 'app_settings';

  @override
  AppSettings build() {
    final prefs = ref.watch(sharedPrefsProvider);
    // Profile settings (synced across devices) win over local ones once loaded.
    final remote = ref.watch(profileProvider).value?.settings;
    if (remote != null && remote.isNotEmpty) return AppSettings.fromJson(remote);
    final raw = prefs.getString(_key);
    if (raw == null) return const AppSettings();
    try {
      return AppSettings.fromJson(_decode(raw));
    } catch (_) {
      return const AppSettings();
    }
  }

  Map<String, dynamic> _decode(String raw) {
    final map = <String, dynamic>{};
    for (final part in raw.split(';')) {
      final kv = part.split('=');
      if (kv.length != 2) continue;
      final v = kv[1];
      map[kv[0]] = v == 'true' ? true : v == 'false' ? false : int.tryParse(v) ?? v;
    }
    return map;
  }

  String _encode(AppSettings s) => s.toJson().entries.map((e) => '${e.key}=${e.value}').join(';');

  Future<void> update(AppSettings settings) async {
    state = settings;
    await ref.read(sharedPrefsProvider).setString(_key, _encode(settings));
    final signedIn = ref.read(sessionProvider) != null;
    if (signedIn) {
      try {
        await ref.read(profileProvider.notifier).save(settings: settings.toJson());
      } catch (_) {
        // offline: local copy is kept, profile sync happens on the next change
      }
    }
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);
