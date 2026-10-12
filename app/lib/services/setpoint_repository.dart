import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/setpoint.dart';

class SetpointRepository {
  SetpointRepository(this._client);

  final SupabaseClient _client;

  Stream<List<Setpoint>> watchSetpoints(String plantId) {
    return _client
        .from('setpoints')
        .stream(primaryKey: ['id'])
        .eq('plant_id', plantId)
        .order('key', ascending: true)
        .map((rows) => rows.map(Setpoint.fromJson).toList()..sort((a, b) => a.groupName.compareTo(b.groupName) != 0 ? a.groupName.compareTo(b.groupName) : a.key.compareTo(b.key)));
  }

  Stream<List<SetpointRequest>> watchRequests(String plantId, {int limit = 100}) {
    return _client
        .from('setpoint_requests')
        .stream(primaryKey: ['id'])
        .eq('plant_id', plantId)
        .order('created_at', ascending: false)
        .limit(limit)
        .map((rows) => rows.map(SetpointRequest.fromJson).toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt)));
  }
}
