import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/env.dart';

SupabaseClient get supabase => Supabase.instance.client;

Future<void> initSupabase() async {
  await Supabase.initialize(
    url: Env.supabaseUrl,
    // Accepts the project's publishable key (sb_publishable_...) or the legacy anon key.
    publishableKey: Env.supabaseAnonKey,
    authOptions: const FlutterAuthClientOptions(
      authFlowType: AuthFlowType.pkce,
      autoRefreshToken: true,
    ),
    realtimeClientOptions: const RealtimeClientOptions(eventsPerSecond: 20),
  );
}
