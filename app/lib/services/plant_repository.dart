import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/plant.dart';

class PlantRepository {
  PlantRepository(this._client);

  final SupabaseClient _client;

  Future<List<Plant>> fetchPlants() async {
    final rows = await _client.from('plants').select().order('code');
    return rows.map(Plant.fromJson).toList();
  }

  Stream<List<Plant>> watchPlants() {
    return _client
        .from('plants')
        .stream(primaryKey: ['id'])
        .order('code', ascending: true)
        .map((rows) => rows.map(Plant.fromJson).toList()..sort((a, b) => a.code.compareTo(b.code)));
  }
}
