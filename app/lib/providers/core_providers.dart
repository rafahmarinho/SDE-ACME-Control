import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/env.dart';
import '../services/alarm_repository.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/command_repository.dart';
import '../services/event_repository.dart';
import '../services/handover_repository.dart';
import '../services/maintenance_repository.dart';
import '../services/offline_cache.dart';
import '../services/plant_repository.dart';
import '../services/process_repository.dart';
import '../services/setpoint_repository.dart';
import '../services/trend_repository.dart';

/// Overridden in main() with the loaded instance.
final sharedPrefsProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('sharedPrefsProvider must be overridden');
});

final offlineCacheProvider = Provider<OfflineCache>((ref) => OfflineCache(ref.watch(sharedPrefsProvider)));

final supabaseClientProvider = Provider<SupabaseClient>((ref) => Supabase.instance.client);

final authServiceProvider = Provider<AuthService>((ref) => AuthService(ref.watch(supabaseClientProvider)));

final apiClientProvider = Provider<ApiClient>(
  (ref) => ApiClient(
    baseUrl: Env.apiBaseUrl,
    tokenProvider: () => ref.read(authServiceProvider).accessToken,
  ),
);

final plantRepositoryProvider = Provider((ref) => PlantRepository(ref.watch(supabaseClientProvider)));
final processRepositoryProvider = Provider((ref) => ProcessRepository(ref.watch(supabaseClientProvider)));
final alarmRepositoryProvider = Provider((ref) => AlarmRepository(ref.watch(supabaseClientProvider)));
final commandRepositoryProvider = Provider((ref) => CommandRepository(ref.watch(supabaseClientProvider)));
final setpointRepositoryProvider = Provider((ref) => SetpointRepository(ref.watch(supabaseClientProvider)));
final maintenanceRepositoryProvider = Provider((ref) => MaintenanceRepository(ref.watch(supabaseClientProvider)));
final handoverRepositoryProvider = Provider((ref) => HandoverRepository(ref.watch(supabaseClientProvider)));
final eventRepositoryProvider = Provider((ref) => EventRepository(ref.watch(supabaseClientProvider)));
final trendRepositoryProvider = Provider((ref) => TrendRepository(ref.watch(supabaseClientProvider)));
