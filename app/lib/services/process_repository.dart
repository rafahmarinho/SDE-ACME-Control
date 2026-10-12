import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/equipment.dart';
import '../models/process_state.dart';

class ProcessRepository {
  ProcessRepository(this._client);

  final SupabaseClient _client;

  Stream<ProcessState?> watchState(String plantId) {
    return _client
        .from('process_state')
        .stream(primaryKey: ['plant_id'])
        .eq('plant_id', plantId)
        .map((rows) => rows.isEmpty ? null : ProcessState.fromJson(rows.first));
  }

  Future<ProcessState?> fetchState(String plantId) async {
    final row = await _client.from('process_state').select().eq('plant_id', plantId).maybeSingle();
    return row == null ? null : ProcessState.fromJson(row);
  }

  Stream<List<Equipment>> watchEquipment(String plantId) {
    return _client
        .from('equipment')
        .stream(primaryKey: ['id'])
        .eq('plant_id', plantId)
        .order('sort_order', ascending: true)
        .map((rows) => rows.map(Equipment.fromJson).toList()..sort((a, b) => a.sortOrder.compareTo(b.sortOrder)));
  }

  Future<List<Equipment>> fetchEquipment(String plantId) async {
    final rows = await _client.from('equipment').select().eq('plant_id', plantId).order('sort_order');
    return rows.map(Equipment.fromJson).toList();
  }

  Future<Equipment?> fetchEquipmentById(String id) async {
    final row = await _client.from('equipment').select().eq('id', id).maybeSingle();
    return row == null ? null : Equipment.fromJson(row);
  }
}
