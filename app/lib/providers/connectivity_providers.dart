import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Device connectivity (network interface available).
class ConnectivityNotifier extends Notifier<bool> {
  StreamSubscription<List<ConnectivityResult>>? _sub;

  @override
  bool build() {
    _sub?.cancel();
    final connectivity = Connectivity();
    _sub = connectivity.onConnectivityChanged.listen((results) => state = _isOnline(results));
    connectivity.checkConnectivity().then((results) {
      state = _isOnline(results);
    }).catchError((_) {});
    ref.onDispose(() => _sub?.cancel());
    return true;
  }

  bool _isOnline(List<ConnectivityResult> results) =>
      results.isNotEmpty && results.any((r) => r != ConnectivityResult.none);

  /// Lets the data layer report reachability (e.g. after a failed request).
  void report(bool online) => state = online;
}

final connectivityProvider = NotifierProvider<ConnectivityNotifier, bool>(ConnectivityNotifier.new);

/// Whether the app is in the foreground. Background updates are paused when false.
class AppForegroundNotifier extends Notifier<bool> {
  @override
  bool build() => true;

  void set(bool foreground) {
    if (state != foreground) state = foreground;
  }
}

final appForegroundProvider = NotifierProvider<AppForegroundNotifier, bool>(AppForegroundNotifier.new);

/// Whether the control API answered the last calls.
class ApiReachableNotifier extends Notifier<bool> {
  @override
  bool build() => true;

  void set(bool reachable) {
    if (state != reachable) state = reachable;
  }
}

final apiReachableProvider = NotifierProvider<ApiReachableNotifier, bool>(ApiReachableNotifier.new);

/// Live updates run only when online and in the foreground.
final liveEnabledProvider = Provider<bool>((ref) => ref.watch(connectivityProvider) && ref.watch(appForegroundProvider));

/// Control actions require a connection to both Supabase and the API.
final canControlProvider = Provider<bool>((ref) => ref.watch(connectivityProvider) && ref.watch(apiReachableProvider));
