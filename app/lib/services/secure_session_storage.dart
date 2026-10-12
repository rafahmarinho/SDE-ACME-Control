import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Persists the Supabase session in the platform secure store (Android
/// EncryptedSharedPreferences, iOS Keychain) instead of plain SharedPreferences.
///
/// Used on Android / iOS only; on web supabase_flutter keeps its default.
class SecureSessionStorage extends LocalStorage {
  const SecureSessionStorage();

  static const _key = 'acme_control.supabase.session';

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
  );

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> hasAccessToken() async {
    try {
      return await _storage.containsKey(key: _key);
    } catch (_) {
      return false;
    }
  }

  @override
  Future<String?> accessToken() async {
    try {
      return await _storage.read(key: _key);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> removePersistedSession() async {
    try {
      await _storage.delete(key: _key);
    } catch (_) {
      // nothing to remove or the store is unavailable
    }
  }

  @override
  Future<void> persistSession(String persistSessionString) async {
    await _storage.write(key: _key, value: persistSessionString);
  }
}
