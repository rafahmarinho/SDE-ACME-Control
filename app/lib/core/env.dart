/// Build-time configuration. Pass values with
/// `flutter run --dart-define-from-file=env.json` (see env.example.json).
class Env {
  Env._();

  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'http://127.0.0.1:54321',
  );

  static const supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: '',
  );

  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:3001/api',
  );

  /// Public URL of the web app, used as redirect target for password recovery e-mails.
  static const webAppUrl = String.fromEnvironment(
    'WEB_APP_URL',
    defaultValue: 'http://localhost:3000',
  );

  /// Deep link used on Android / iOS for password recovery (registered in the
  /// Android manifest and iOS Info.plist, and in the Supabase redirect URLs).
  static const mobileAuthCallback = 'acmecontrol://auth/reset-password';

  static bool get isConfigured => supabaseAnonKey.isNotEmpty;
}
