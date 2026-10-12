import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/profile.dart';
import 'core_providers.dart';

final authStateProvider = StreamProvider<AuthState>((ref) => ref.watch(authServiceProvider).onAuthStateChange);

final sessionProvider = Provider<Session?>((ref) {
  ref.watch(authStateProvider);
  return ref.watch(authServiceProvider).session;
});

final currentUserIdProvider = Provider<String?>((ref) => ref.watch(sessionProvider)?.user.id);

class ProfileNotifier extends AsyncNotifier<Profile?> {
  @override
  Future<Profile?> build() async {
    final userId = ref.watch(currentUserIdProvider);
    if (userId == null) return null;
    final cache = ref.read(offlineCacheProvider);
    try {
      final profile = await ref.read(authServiceProvider).fetchProfile(userId);
      if (profile != null) cache.put('profile', profile.toJson());
      return profile;
    } catch (e) {
      final cached = cache.get('profile', (j) => Profile.fromJson(j as Map<String, dynamic>));
      if (cached != null && cached.data.id == userId) return cached.data;
      rethrow;
    }
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
