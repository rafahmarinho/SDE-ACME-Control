import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/env.dart';
import 'secure_session_storage.dart';

SupabaseClient get supabase => Supabase.instance.client;

Future<void> initSupabase() async {
  await Supabase.initialize(
    url: Env.supabaseUrl,
    // Accepts the project's publishable key (sb_publishable_...) or the legacy anon key.
    publishableKey: Env.supabaseAnonKey,
    authOptions: FlutterAuthClientOptions(
      authFlowType: AuthFlowType.pkce,
      autoRefreshToken: true,
      // Mobile: keep the session in the platform secure store. Web keeps the default.
      localStorage: kIsWeb ? null : const SecureSessionStorage(),
    ),
    realtimeClientOptions: const RealtimeClientOptions(eventsPerSecond: 20),
  );
}
