import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/alarm.dart';

class AlarmRepository {
  AlarmRepository(this._client);

  final SupabaseClient _client;

  Stream<List<Alarm>> watchAlarms(String plantId, {int limit = 300}) {
    return _client
        .from('alarms')
        .stream(primaryKey: ['id'])
        .eq('plant_id', plantId)
        .order('raised_at', ascending: false)
        .limit(limit)
        .map((rows) => rows.map(Alarm.fromJson).toList()..sort((a, b) => b.raisedAt.compareTo(a.raisedAt)));
  }

  Future<List<Alarm>> fetchAlarms(String plantId, {int limit = 300}) async {
    final rows = await _client.from('alarms').select().eq('plant_id', plantId).order('raised_at', ascending: false).limit(limit);
    return rows.map(Alarm.fromJson).toList();
  }

  Future<void> acknowledge(String alarmId, {required String userId, required String userName}) async {
    await _client
        .from('alarms')
        .update({
          'state': 'acknowledged',
          'acked_at': DateTime.now().toUtc().toIso8601String(),
          'acked_by': userId,
          'acked_by_name': userName,
        })
        .eq('id', alarmId)
        .eq('state', 'active');
  }

  Future<int> acknowledgeAll(String plantId, {required String userId, required String userName}) async {
    final rows = await _client
        .from('alarms')
        .update({
          'state': 'acknowledged',
          'acked_at': DateTime.now().toUtc().toIso8601String(),
          'acked_by': userId,
          'acked_by_name': userName,
        })
        .eq('plant_id', plantId)
        .eq('state', 'active')
        .select('id');
    return rows.length;
  }
}
