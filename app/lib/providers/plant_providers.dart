import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/plant.dart';
import 'auth_providers.dart';
import 'core_providers.dart';

final plantsProvider = FutureProvider<List<Plant>>((ref) async {
  ref.watch(sessionProvider);
  final cache = ref.read(offlineCacheProvider);
  try {
    final plants = await ref.read(plantRepositoryProvider).fetchPlants();
    cache.put('plants', plants.map((p) => p.toJson()).toList());
    return plants;
  } catch (e) {
    final cached = cache.get('plants', (j) => (j as List).map((e) => Plant.fromJson(e as Map<String, dynamic>)).toList());
    if (cached != null && cached.data.isNotEmpty) return cached.data;
    rethrow;
  }
});

class SelectedPlantNotifier extends Notifier<String?> {
  static const _key = 'selected_plant_id';

  @override
  String? build() => ref.watch(sharedPrefsProvider).getString(_key);

  void select(String plantId) {
    state = plantId;
    ref.read(sharedPrefsProvider).setString(_key, plantId);
  }
}

final selectedPlantIdProvider = NotifierProvider<SelectedPlantNotifier, String?>(SelectedPlantNotifier.new);

/// The plant currently shown: explicit selection, else the profile default, else the first plant.
final selectedPlantProvider = Provider<Plant?>((ref) {
  final plants = ref.watch(plantsProvider).value ?? const <Plant>[];
  if (plants.isEmpty) return null;
  final selectedId = ref.watch(selectedPlantIdProvider);
  final defaultId = ref.watch(profileProvider).value?.defaultPlantId;
  for (final id in [selectedId, defaultId]) {
    if (id == null) continue;
    for (final p in plants) {
      if (p.id == id) return p;
    }
  }
  return plants.first;
});

final effectivePlantIdProvider = Provider<String?>((ref) => ref.watch(selectedPlantProvider)?.id);
