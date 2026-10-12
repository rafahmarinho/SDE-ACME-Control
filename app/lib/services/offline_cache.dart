import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class CacheEntry<T> {
  const CacheEntry(this.data, this.savedAt);

  final T data;
  final DateTime savedAt;
}

/// Stores the latest snapshot of each live dataset so the app can show a
/// read-only view while offline or while the connection is being restored.
class OfflineCache {
  OfflineCache(this._prefs);

  final SharedPreferences _prefs;

  static const _prefix = 'cache:';

  void put(String key, Object? value) {
    try {
      _prefs.setString('$_prefix$key', jsonEncode({'at': DateTime.now().toIso8601String(), 'data': value}));
    } catch (_) {
      // never let caching break the UI
    }
  }

  CacheEntry<T>? get<T>(String key, T Function(dynamic json) decode) {
    final raw = _prefs.getString('$_prefix$key');
    if (raw == null) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final at = DateTime.tryParse(map['at']?.toString() ?? '') ?? DateTime.now();
      return CacheEntry(decode(map['data']), at);
    } catch (_) {
      return null;
    }
  }

  void remove(String key) => _prefs.remove('$_prefix$key');

  Future<void> clear() async {
    for (final k in _prefs.getKeys().where((k) => k.startsWith(_prefix)).toList()) {
      await _prefs.remove(k);
    }
  }
}
