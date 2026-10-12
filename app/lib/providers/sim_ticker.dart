import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/api_client.dart';
import 'auth_providers.dart';
import 'connectivity_providers.dart';
import 'core_providers.dart';
import 'plant_providers.dart';
import 'settings_providers.dart';

/// Drives the simulation while the app is open: every few seconds it asks the
/// API to advance the selected plant. The server only advances once per
/// interval no matter how many clients are connected (claim_tick RPC).
class SimTicker extends Notifier<bool> {
  Timer? _timer;
  bool _inFlight = false;
  int _failures = 0;

  @override
  bool build() {
    final plantId = ref.watch(effectivePlantIdProvider);
    final enabled = ref.watch(liveEnabledProvider);
    final signedIn = ref.watch(sessionProvider) != null;
    final interval = ref.watch(settingsProvider).refreshSeconds;
    ref.onDispose(() => _timer?.cancel());
    final active = plantId != null && enabled && signedIn;
    if (active) {
      _timer = Timer.periodic(Duration(seconds: interval), (_) => _tick(plantId));
      Future.microtask(() => _tick(plantId));
    }
    return active;
  }

  Future<void> _tick(String plantId) async {
    if (_inFlight) return;
    _inFlight = true;
    try {
      await ref.read(apiClientProvider).tick(plantId);
      _failures = 0;
      ref.read(apiReachableProvider.notifier).set(true);
    } on ApiException catch (e) {
      _failures += 1;
      if (e.isNetwork && _failures >= 2) ref.read(apiReachableProvider.notifier).set(false);
    } catch (_) {
      _failures += 1;
    } finally {
      _inFlight = false;
    }
  }
}

final simTickerProvider = NotifierProvider<SimTicker, bool>(SimTicker.new);
