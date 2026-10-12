import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_providers.dart';
import 'core_providers.dart';
import 'settings_providers.dart';

/// Signs the user out after a period of inactivity (configurable in Settings)
/// or once the session is older than [absoluteTimeout], whichever comes first.
///
/// The state is the moment the current session started (null when signed out).
/// Pointer activity is reported through [touch] from the root `Listener` in
/// `app.dart`; the check runs every [_tick].
class SessionGuard extends Notifier<DateTime?> {
  static const absoluteTimeout = Duration(hours: 12);
  static const _tick = Duration(seconds: 30);
  static const _prefsKey = 'session_started_at';

  DateTime _lastActivity = DateTime.now();
  Timer? _timer;
  bool _signingOut = false;

  @override
  DateTime? build() {
    ref.listen(authStateProvider, (_, next) {
      final event = next.value?.event;
      final session = next.value?.session;
      if (event == AuthChangeEvent.signedOut) {
        _clear();
      } else if (event == AuthChangeEvent.signedIn && session != null) {
        _start(DateTime.now());
      } else if (session != null && state == null) {
        // initialSession / passwordRecovery: a session we did not see start.
        _start(_restoredStart(session));
      }
    });
    _timer?.cancel();
    _timer = Timer.periodic(_tick, (_) => _check());
    ref.onDispose(() => _timer?.cancel());

    final session = ref.read(authServiceProvider).session;
    if (session == null) return null;
    final start = _restoredStart(session);
    _persist(start);
    return start;
  }

  /// Records user activity. Cheap: no listeners are notified.
  void touch() => _lastActivity = DateTime.now();

  DateTime _restoredStart(Session session) {
    final prefs = ref.read(sharedPrefsProvider);
    final stored = DateTime.tryParse(prefs.getString(_prefsKey) ?? '');
    if (stored != null) return stored;
    final fromToken = DateTime.tryParse(session.user.lastSignInAt ?? '');
    return fromToken?.toLocal() ?? DateTime.now();
  }

  void _start(DateTime at) {
    _lastActivity = DateTime.now();
    _persist(at);
    state = at;
  }

  void _persist(DateTime at) => ref.read(sharedPrefsProvider).setString(_prefsKey, at.toIso8601String());

  void _clear() {
    ref.read(sharedPrefsProvider).remove(_prefsKey);
    state = null;
  }

  Future<void> _check() async {
    if (_signingOut) return;
    final auth = ref.read(authServiceProvider);
    if (!auth.isSignedIn) return;
    final now = DateTime.now();
    final idleLimit = Duration(minutes: ref.read(settingsProvider).idleTimeoutMinutes);
    String? reason;
    if (now.difference(_lastActivity) > idleLimit) {
      reason = 'idle';
    } else {
      final startedAt = state ?? _restoredStart(auth.session!);
      if (state == null) _start(startedAt);
      if (now.difference(startedAt) > absoluteTimeout) reason = 'expired';
    }
    if (reason == null) return;
    _signingOut = true;
    try {
      await signOutEverywhere(ref.read, reason: reason);
    } finally {
      _signingOut = false;
    }
  }
}

final sessionGuardProvider = NotifierProvider<SessionGuard, DateTime?>(SessionGuard.new);
