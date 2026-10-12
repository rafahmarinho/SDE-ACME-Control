import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/event_entry.dart';

class EventRepository {
  EventRepository(this._client);

  final SupabaseClient _client;

  Stream<List<EventEntry>> watchEvents(String plantId, {int limit = 150}) {
    return _client
        .from('events')
        .stream(primaryKey: ['id'])
        .eq('plant_id', plantId)
        .order('ts', ascending: false)
        .limit(limit)
        .map((rows) => rows.map(EventEntry.fromJson).toList()..sort((a, b) => b.ts.compareTo(a.ts) != 0 ? b.ts.compareTo(a.ts) : b.id.compareTo(a.id)));
  }

  Future<List<EventEntry>> fetchEvents(String plantId, {int limit = 300, String? category}) async {
    var query = _client.from('events').select().eq('plant_id', plantId);
    if (category != null) query = query.eq('category', category);
    final rows = await query.order('ts', ascending: false).limit(limit);
    return rows.map(EventEntry.fromJson).toList();
  }

  Future<void> log({
    required String plantId,
    required String category,
    required String message,
    required String actor,
    String level = 'info',
    Map<String, dynamic> data = const {},
  }) async {
    await _client.from('events').insert({
      'plant_id': plantId,
      'category': category,
      'level': level,
      'message': message,
      'actor': actor,
      'data': data,
    });
  }
}
