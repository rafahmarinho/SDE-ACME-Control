import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/shift_handover.dart';

class HandoverRepository {
  HandoverRepository(this._client);

  final SupabaseClient _client;

  Stream<List<ShiftHandover>> watchHandovers(String plantId, {int limit = 100}) {
    return _client
        .from('shift_handovers')
        .stream(primaryKey: ['id'])
        .eq('plant_id', plantId)
        .order('created_at', ascending: false)
        .limit(limit)
        .map((rows) => rows.map(ShiftHandover.fromJson).toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt)));
  }

  Future<ShiftHandover> create({
    required String plantId,
    required String shift,
    required DateTime shiftDate,
    required String fromUser,
    required String fromUserName,
    required String summary,
    required List<String> openIssues,
    required Map<String, bool> checklist,
    required bool submit,
    String? toUser,
    String? toUserName,
  }) async {
    final row = await _client
        .from('shift_handovers')
        .insert({
          'plant_id': plantId,
          'shift': shift,
          'shift_date': shiftDate.toIso8601String().substring(0, 10),
          'from_user': fromUser,
          'from_user_name': fromUserName,
          'to_user': toUser,
          'to_user_name': toUserName,
          'summary': summary.trim(),
          'open_issues': openIssues,
          'checklist': checklist,
          'status': submit ? 'submitted' : 'draft',
          'submitted_at': submit ? DateTime.now().toUtc().toIso8601String() : null,
        })
        .select()
        .single();
    return ShiftHandover.fromJson(row);
  }

  Future<ShiftHandover> update(String id, Map<String, dynamic> patch) async {
    final row = await _client.from('shift_handovers').update(patch).eq('id', id).select().single();
    return ShiftHandover.fromJson(row);
  }

  Future<ShiftHandover> submit(String id) => update(id, {
        'status': 'submitted',
        'submitted_at': DateTime.now().toUtc().toIso8601String(),
      });

  Future<ShiftHandover> acknowledge(String id, {required String userId, required String userName}) => update(id, {
        'status': 'acknowledged',
        'acknowledged_at': DateTime.now().toUtc().toIso8601String(),
        'acknowledged_by': userId,
        'to_user': userId,
        'to_user_name': userName,
      });
}
