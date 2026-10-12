import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'connectivity_providers.dart';
import 'core_providers.dart';
import 'plant_providers.dart';

/// Snapshot of a live dataset with offline / paused metadata.
class LiveData<T> {
  const LiveData({
    this.data,
    this.loading = false,
    this.error,
    this.updatedAt,
    this.fromCache = false,
    this.paused = false,
  });

  final T? data;
  final bool loading;
  final Object? error;
  final DateTime? updatedAt;

  /// True when [data] was restored from the offline cache and not yet refreshed.
  final bool fromCache;

  /// True while realtime updates are suspended (offline or app in background).
  final bool paused;

  bool get hasData => data != null;
  bool get isStale => fromCache || paused;

  LiveData<T> copyWith({
    T? data,
    bool? loading,
    Object? error,
    bool clearError = false,
    DateTime? updatedAt,
    bool? fromCache,
    bool? paused,
  }) =>
      LiveData<T>(
        data: data ?? this.data,
        loading: loading ?? this.loading,
        error: clearError ? null : (error ?? this.error),
        updatedAt: updatedAt ?? this.updatedAt,
        fromCache: fromCache ?? this.fromCache,
        paused: paused ?? this.paused,
      );
}

/// Base class for plant-scoped realtime datasets.
///
/// - subscribes to a Supabase stream for the selected plant
/// - keeps the last snapshot in the offline cache
/// - pauses while offline / in background and resumes automatically
abstract class LiveNotifier<T> extends Notifier<LiveData<T>> {
  StreamSubscription<T>? _sub;
  Timer? _retry;
  String? _plantId;

  String get cacheKey;

  Stream<T> source(String plantId);

  T decodeCache(dynamic json);

  Object? encodeCache(T data);

  @override
  LiveData<T> build() {
    final plantId = ref.watch(effectivePlantIdProvider);
    _plantId = plantId;
    ref.listen<bool>(liveEnabledProvider, (_, enabled) {
      if (plantId == null) return;
      if (enabled) {
        _subscribe(plantId);
      } else {
        _pause();
      }
    });
    ref.onDispose(_cancel);

    if (plantId == null) return const LiveData(loading: true);
    final cached = ref.read(offlineCacheProvider).get<T>('$cacheKey:$plantId', decodeCache);
    final enabled = ref.read(liveEnabledProvider);
    Future.microtask(() {
      if (_plantId == plantId && enabled) _subscribe(plantId);
    });
    return LiveData<T>(
      data: cached?.data,
      updatedAt: cached?.savedAt,
      fromCache: cached != null,
      loading: cached == null,
      paused: !enabled,
    );
  }

  void _cancel() {
    _sub?.cancel();
    _sub = null;
    _retry?.cancel();
    _retry = null;
  }

  void _subscribe(String plantId) {
    _cancel();
    state = state.copyWith(paused: false, loading: !state.hasData, clearError: true);
    try {
      _sub = source(plantId).listen(
        (data) {
          if (_plantId != plantId) return;
          ref.read(offlineCacheProvider).put('$cacheKey:$plantId', encodeCache(data));
          state = LiveData<T>(data: data, updatedAt: DateTime.now());
        },
        onError: (Object error, StackTrace stack) {
          if (_plantId != plantId) return;
          state = state.copyWith(error: error, loading: false);
          _scheduleRetry(plantId);
        },
      );
    } catch (e) {
      state = state.copyWith(error: e, loading: false);
      _scheduleRetry(plantId);
    }
  }

  void _scheduleRetry(String plantId) {
    _retry?.cancel();
    _retry = Timer(const Duration(seconds: 6), () {
      if (_plantId == plantId && ref.read(liveEnabledProvider)) _subscribe(plantId);
    });
  }

  void _pause() {
    _cancel();
    state = state.copyWith(paused: true, loading: false);
  }

  /// Force a resubscribe (pull-to-refresh).
  void refresh() {
    final plantId = _plantId;
    if (plantId != null && ref.read(liveEnabledProvider)) _subscribe(plantId);
  }
}
