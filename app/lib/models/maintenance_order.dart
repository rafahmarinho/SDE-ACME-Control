import 'json.dart';

enum MaintenanceStatus { open, inProgress, done, cancelled }

enum MaintenancePriority { low, medium, high, critical }

String maintenanceStatusToDb(MaintenanceStatus s) => s == MaintenanceStatus.inProgress ? 'in_progress' : s.name;

MaintenanceStatus maintenanceStatusFromDb(dynamic v) {
  switch (v?.toString()) {
    case 'in_progress':
      return MaintenanceStatus.inProgress;
    case 'done':
      return MaintenanceStatus.done;
    case 'cancelled':
      return MaintenanceStatus.cancelled;
    default:
      return MaintenanceStatus.open;
  }
}

String maintenanceStatusLabel(MaintenanceStatus s) {
  switch (s) {
    case MaintenanceStatus.open:
      return 'Open';
    case MaintenanceStatus.inProgress:
      return 'In progress';
    case MaintenanceStatus.done:
      return 'Done';
    case MaintenanceStatus.cancelled:
      return 'Cancelled';
  }
}

/// File stored in the private `attachments` bucket.
///
/// New rows carry the storage object [path]; rows written before the bucket
/// became private only have a public [url], from which the path is derived.
class Attachment {
  const Attachment({required this.name, this.path, this.url, this.contentType});

  final String name;
  final String? path;
  final String? url;
  final String? contentType;

  static const _legacyMarker = '/storage/v1/object/public/attachments/';

  static String? pathFromLegacyUrl(String? url) {
    if (url == null) return null;
    final i = url.indexOf(_legacyMarker);
    if (i < 0) return null;
    var rest = url.substring(i + _legacyMarker.length);
    final q = rest.indexOf('?');
    if (q >= 0) rest = rest.substring(0, q);
    return rest.isEmpty ? null : Uri.decodeComponent(rest);
  }

  /// Storage path to sign, or null when the row cannot be resolved.
  String? get storagePath => path ?? pathFromLegacyUrl(url);

  factory Attachment.fromJson(Map<String, dynamic> json) => Attachment(
        name: json['name'] as String? ?? 'file',
        path: json['path'] as String?,
        url: json['url'] as String?,
        contentType: json['content_type'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        if (path != null) 'path': path,
        if (url != null) 'url': url,
        'content_type': contentType,
      };

  bool get isImage => (contentType ?? '').startsWith('image/');
}

class MaintenanceOrder {
  const MaintenanceOrder({
    required this.id,
    required this.plantId,
    required this.code,
    required this.title,
    required this.description,
    required this.priority,
    required this.status,
    required this.attachments,
    required this.createdAt,
    this.equipmentId,
    this.equipmentTag,
    this.assignedTo,
    this.assignedToName,
    this.scheduledFor,
    this.startedAt,
    this.completedAt,
    this.workNotes,
    this.createdBy,
    this.createdByName,
    this.updatedAt,
  });

  final String id;
  final String plantId;
  final String code;
  final String title;
  final String description;
  final MaintenancePriority priority;
  final MaintenanceStatus status;
  final List<Attachment> attachments;
  final DateTime createdAt;
  final String? equipmentId;
  final String? equipmentTag;
  final String? assignedTo;
  final String? assignedToName;
  final DateTime? scheduledFor;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final String? workNotes;
  final String? createdBy;
  final String? createdByName;
  final DateTime? updatedAt;

  bool get isClosed => status == MaintenanceStatus.done || status == MaintenanceStatus.cancelled;

  factory MaintenanceOrder.fromJson(Map<String, dynamic> json) => MaintenanceOrder(
        id: json['id'] as String,
        plantId: json['plant_id'] as String,
        code: json['code'] as String? ?? '',
        title: json['title'] as String? ?? '',
        description: json['description'] as String? ?? '',
        priority: enumFromString(MaintenancePriority.values, json['priority'], MaintenancePriority.medium),
        status: maintenanceStatusFromDb(json['status']),
        attachments: (json['attachments'] is List)
            ? (json['attachments'] as List).map((e) => Attachment.fromJson(toMap(e))).toList()
            : const [],
        createdAt: toDate(json['created_at']) ?? DateTime.now(),
        equipmentId: json['equipment_id'] as String?,
        equipmentTag: json['equipment_tag'] as String?,
        assignedTo: json['assigned_to'] as String?,
        assignedToName: json['assigned_to_name'] as String?,
        scheduledFor: toDate(json['scheduled_for']),
        startedAt: toDate(json['started_at']),
        completedAt: toDate(json['completed_at']),
        workNotes: json['work_notes'] as String?,
        createdBy: json['created_by'] as String?,
        createdByName: json['created_by_name'] as String?,
        updatedAt: toDate(json['updated_at']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'plant_id': plantId,
        'code': code,
        'title': title,
        'description': description,
        'priority': priority.name,
        'status': maintenanceStatusToDb(status),
        'attachments': attachments.map((a) => a.toJson()).toList(),
        'created_at': createdAt.toIso8601String(),
        'equipment_id': equipmentId,
        'equipment_tag': equipmentTag,
        'assigned_to': assignedTo,
        'assigned_to_name': assignedToName,
        'scheduled_for': scheduledFor?.toIso8601String(),
        'started_at': startedAt?.toIso8601String(),
        'completed_at': completedAt?.toIso8601String(),
        'work_notes': workNotes,
        'created_by': createdBy,
        'created_by_name': createdByName,
        'updated_at': updatedAt?.toIso8601String(),
      };
}
