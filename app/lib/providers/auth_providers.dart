import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/profile.dart';
import 'core_providers.dart';

final authStateProvider = StreamProvider<AuthState>((ref) => ref.watch(authServiceProvider).onAuthStateChange);

final sessionProvider = Provider<Session?>((ref) {
  ref.watch(authStateProvider);
  return ref.watch(authServiceProvider).session;
});

final currentUserIdProvider = Provider<String?>((ref) => ref.watch(sessionProvider)?.user.id);

/// Reads a provider; satisfied by both `Ref.read` and `WidgetRef.read`
/// (call as `signOutEverywhere(ref.read)`).
typedef ProviderReader = T Function<T>(ProviderListenable<T> provider);

/// Why the user was signed out automatically (`idle` or `expired`). The router
/// consumes it when it redirects to `/login` so the page can explain.
class SignOutReasonNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? reason) => state = reason;

  String? consume() {
    final reason = state;
    state = null;
    return reason;
  }
}

final signOutReasonProvider = NotifierProvider<SignOutReasonNotifier, String?>(SignOutReasonNotifier.new);

/// Signs out and removes every trace of the user from this device: the
/// Supabase session, the offline cache (including the cached profile) and the
/// signed-URL cache. When [reason] is given the login page explains why.
Future<void> signOutEverywhere(ProviderReader read, {String? reason}) async {
  read(signOutReasonProvider.notifier).set(reason);
  try {
    await read(authServiceProvider).signOut();
  } catch (_) {
    // offline: the local session is dropped anyway
  }
  try {
    final cache = read(offlineCacheProvider);
    await cache.clear();
    cache.remove('profile');
    read(storageServiceProvider).clear();
  } catch (_) {
    // never block sign-out on cache cleanup
  }
}

// --------------------------------------------------------------- sign-in session

/// Per-sign-in bookkeeping: whether the "Signed in" audit event was written and
/// whether the "previous sign-in" notice still has to be shown.
class SignInSessionState {
  const SignInSessionState({
    this.userId,
    this.explicitSignIn = false,
    this.signInLogged = false,
    this.noticePending = false,
    this.previousSignInAt,
  });

  final String? userId;

  /// True when an [AuthChangeEvent.signedIn] was observed in this app run
  /// (as opposed to a session restored from storage).
  final bool explicitSignIn;
  final bool signInLogged;
  final bool noticePending;
  final DateTime? previousSignInAt;

  SignInSessionState copyWith({
    String? userId,
    bool? explicitSignIn,
    bool? signInLogged,
    bool? noticePending,
    DateTime? previousSignInAt,
  }) =>
      SignInSessionState(
        userId: userId ?? this.userId,
        explicitSignIn: explicitSignIn ?? this.explicitSignIn,
        signInLogged: signInLogged ?? this.signInLogged,
        noticePending: noticePending ?? this.noticePending,
        previousSignInAt: previousSignInAt ?? this.previousSignInAt,
      );
}

class SignInSessionNotifier extends Notifier<SignInSessionState> {
  @override
  SignInSessionState build() {
    ref.listen(authStateProvider, (_, next) {
      final event = next.value?.event;
      final userId = next.value?.session?.user.id;
      if (event == AuthChangeEvent.signedOut) {
        state = const SignInSessionState();
      } else if (event == AuthChangeEvent.signedIn && userId != null) {
        // A re-authentication (e.g. password change) of the same user is not a new sign-in.
        if (state.userId == userId && state.signInLogged) return;
        state = SignInSessionState(userId: userId, explicitSignIn: true);
      }
    });
    return const SignInSessionState();
  }

  static String get _platformName {
    if (kIsWeb) return 'web';
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.iOS:
        return 'ios';
      default:
        return defaultTargetPlatform.name;
    }
  }

  /// Called once the profile is loaded. Writes the audit event (once per
  /// explicit sign-in) and queues the previous sign-in notice (once per user).
  Future<void> onProfileLoaded(Profile profile) async {
    if (state.userId != profile.id) {
      state = SignInSessionState(userId: profile.id, explicitSignIn: false);
    }
    if (!state.noticePending && state.previousSignInAt == null && profile.previousSignInAt != null) {
      state = state.copyWith(noticePending: true, previousSignInAt: profile.previousSignInAt);
    }
    if (!state.explicitSignIn || state.signInLogged) return;
    state = state.copyWith(signInLogged: true);
    try {
      var plantId = profile.defaultPlantId;
      if (plantId == null) {
        final plants = await ref.read(plantRepositoryProvider).fetchPlants();
        plantId = plants.isEmpty ? null : plants.first.id;
      }
      if (plantId == null) return;
      await ref.read(eventRepositoryProvider).log(
            plantId: plantId,
            category: 'auth',
            message: 'Signed in on $_platformName',
            actor: profile.displayName,
            data: {'platform': _platformName, 'role': profile.role.name},
          );
    } catch (_) {
      // auditing must never block the UI
    }
  }

  /// Returns the pending "previous sign-in" timestamp once, then clears it.
  DateTime? consumeNotice() {
    if (!state.noticePending) return null;
    final at = state.previousSignInAt;
    state = state.copyWith(noticePending: false);
    return at;
  }
}

final signInSessionProvider = NotifierProvider<SignInSessionNotifier, SignInSessionState>(SignInSessionNotifier.new);

// ------------------------------------------------------------------- profile

class ProfileNotifier extends AsyncNotifier<Profile?> {
  @override
  Future<Profile?> build() async {
    final userId = ref.watch(currentUserIdProvider);
    if (userId == null) return null;
    final cache = ref.read(offlineCacheProvider);
    Profile? profile;
    try {
      profile = await ref.read(authServiceProvider).fetchProfile(userId);
      if (profile != null) cache.put('profile', profile.toJson());
    } catch (e) {
      final cached = cache.get('profile', (j) => Profile.fromJson(j as Map<String, dynamic>));
      if (cached != null && cached.data.id == userId) {
        profile = cached.data;
      } else {
        rethrow;
      }
    }
    if (profile != null) {
      final loaded = profile;
      final session = ref.read(signInSessionProvider.notifier);
      // Side effects run after build completes; they never block or fail the profile.
      Future<void>.microtask(() => session.onProfileLoaded(loaded)).catchError((_) {});
    }
    return profile;
  }

  Future<void> refresh() async {
    final userId = ref.read(currentUserIdProvider);
    if (userId == null) return;
    state = await AsyncValue.guard(() => ref.read(authServiceProvider).fetchProfile(userId));
  }

  Future<Profile> save({
    String? fullName,
    String? phone,
    String? avatarUrl,
    String? defaultPlantId,
    Map<String, dynamic>? settings,
  }) async {
    final userId = ref.read(currentUserIdProvider);
    if (userId == null) throw StateError('Not signed in');
    final updated = await ref.read(authServiceProvider).updateProfile(
          userId,
          fullName: fullName,
          phone: phone,
          avatarUrl: avatarUrl,
          defaultPlantId: defaultPlantId,
          settings: settings,
        );
    ref.read(offlineCacheProvider).put('profile', updated.toJson());
    state = AsyncData(updated);
    return updated;
  }
}

final profileProvider = AsyncNotifierProvider<ProfileNotifier, Profile?>(ProfileNotifier.new);

final roleProvider = Provider<UserRole>((ref) => ref.watch(profileProvider).value?.role ?? UserRole.operator);

final displayNameProvider = Provider<String>((ref) {
  final profile = ref.watch(profileProvider).value;
  if (profile != null) return profile.displayName;
  return ref.watch(sessionProvider)?.user.email ?? 'Unknown user';
});

/// Directory of all users (for assignment / handover pickers).
final usersProvider = FutureProvider<List<Profile>>((ref) async {
  ref.watch(sessionProvider);
  return ref.watch(authServiceProvider).fetchProfiles();
});
