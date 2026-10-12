import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/maintenance_order.dart';

class MaintenanceRepository {
  MaintenanceRepository(this._client);

  final SupabaseClient _client;

  Stream<List<MaintenanceOrder>> watchOrders(String plantId, {int limit = 200}) {
    return _client
        .from('maintenance_orders')
        .stream(primaryKey: ['id'])
        .eq('plant_id', plantId)
        .order('created_at', ascending: false)
        .limit(limit)
        .map((rows) => rows.map(MaintenanceOrder.fromJson).toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt)));
  }

  Future<MaintenanceOrder> create({
    required String plantId,
    required String title,
    required String description,
    required MaintenancePriority priority,
    required String createdBy,
    required String createdByName,
    String? equipmentId,
    String? equipmentTag,
    String? assignedTo,
    String? assignedToName,
    DateTime? scheduledFor,
    List<Attachment> attachments = const [],
  }) async {
    final row = await _client
        .from('maintenance_orders')
        .insert({
          'plant_id': plantId,
          'title': title.trim(),
          'description': description.trim(),
          'priority': priority.name,
          'status': 'open',
          'created_by': createdBy,
          'created_by_name': createdByName,
          'equipment_id': equipmentId,
          'equipment_tag': equipmentTag,
          'assigned_to': assignedTo,
          'assigned_to_name': assignedToName,
          'scheduled_for': scheduledFor?.toUtc().toIso8601String(),
          'attachments': attachments.map((a) => a.toJson()).toList(),
        })
        .select()
        .single();
    return MaintenanceOrder.fromJson(row);
  }

  Future<MaintenanceOrder> update(String id, Map<String, dynamic> patch) async {
    final row = await _client.from('maintenance_orders').update(patch).eq('id', id).select().single();
    return MaintenanceOrder.fromJson(row);
  }

  Future<MaintenanceOrder> setStatus(String id, MaintenanceStatus status, {String? workNotes}) {
    final now = DateTime.now().toUtc().toIso8601String();
    final patch = <String, dynamic>{'status': maintenanceStatusToDb(status)};
    if (status == MaintenanceStatus.inProgress) patch['started_at'] = now;
    if (status == MaintenanceStatus.done) patch['completed_at'] = now;
    if (workNotes != null) patch['work_notes'] = workNotes;
    return update(id, patch);
  }

  Future<Attachment> uploadAttachment({
    required String plantId,
    required Uint8List bytes,
    required String fileName,
    required String contentType,
  }) async {
    final safeName = fileName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final path = 'maintenance/$plantId/${DateTime.now().millisecondsSinceEpoch}_$safeName';
    await _client.storage.from('attachments').uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: contentType, upsert: false),
        );
    // The bucket is private: only the object path is stored; readers sign it on demand.
    return Attachment(name: fileName, path: path, contentType: contentType);
  }
}
