import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/env.dart';
import 'providers/core_providers.dart';
import 'services/supabase_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!Env.isConfigured) {
    runApp(const ConfigErrorApp(message: 'SUPABASE_ANON_KEY is empty. The app cannot connect to Supabase.'));
    return;
  }

  final prefs = await SharedPreferences.getInstance();
  try {
    await initSupabase();
  } catch (e) {
    runApp(ConfigErrorApp(message: 'Supabase could not be initialised: $e'));
    return;
  }

  runApp(
    ProviderScope(
      overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
      child: const AcmeControlApp(),
    ),
  );
}
