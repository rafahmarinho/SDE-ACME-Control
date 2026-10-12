import 'json.dart';

enum HandoverStatus { draft, submitted, acknowledged }

class ShiftHandover {
  const ShiftHandover({
    required this.id,
    required this.plantId,
    required this.shift,
    required this.shiftDate,
    required this.summary,
    required this.openIssues,
    required this.checklist,
    required this.status,
    required this.createdAt,
    this.fromUser,
    this.fromUserName,
    this.toUser,
    this.toUserName,
    this.submittedAt,
    this.acknowledgedAt,
    this.acknowledgedBy,
    this.updatedAt,
  });

  final String id;
  final String plantId;
  final String shift;
  final DateTime shiftDate;
  final String summary;
  final List<String> openIssues;
  final Map<String, bool> checklist;
  final HandoverStatus status;
  final DateTime createdAt;
  final String? fromUser;
  final String? fromUserName;
  final String? toUser;
  final String? toUserName;
  final DateTime? submittedAt;
  final DateTime? acknowledgedAt;
  final String? acknowledgedBy;
  final DateTime? updatedAt;

  static const checklistItems = <String, String>{
    'alarms_reviewed': 'Active alarms reviewed',
    'levels_checked': 'Tank levels and pumps checked',
    'chemicals_checked': 'Chemical stocks checked',
    'logbook_updated': 'Logbook updated',
  };

  int get checklistDone => checklist.values.where((v) => v).length;

  factory ShiftHandover.fromJson(Map<String, dynamic> json) {
    final checklist = <String, bool>{};
    toMap(json['checklist']).forEach((k, v) => checklist[k] = v == true);
    return ShiftHandover(
      id: json['id'] as String,
      plantId: json['plant_id'] as String,
      shift: json['shift'] as String? ?? 'day',
      shiftDate: toDate(json['shift_date']) ?? DateTime.now(),
      summary: json['summary'] as String? ?? '',
      openIssues: toStringList(json['open_issues']),
      checklist: checklist,
      status: enumFromString(HandoverStatus.values, json['status'], HandoverStatus.draft),
      createdAt: toDate(json['created_at']) ?? DateTime.now(),
      fromUser: json['from_user'] as String?,
      fromUserName: json['from_user_name'] as String?,
      toUser: json['to_user'] as String?,
      toUserName: json['to_user_name'] as String?,
      submittedAt: toDate(json['submitted_at']),
      acknowledgedAt: toDate(json['acknowledged_at']),
      acknowledgedBy: json['acknowledged_by'] as String?,
      updatedAt: toDate(json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'plant_id': plantId,
        'shift': shift,
        'shift_date': shiftDate.toIso8601String(),
        'summary': summary,
        'open_issues': openIssues,
        'checklist': checklist,
        'status': status.name,
        'created_at': createdAt.toIso8601String(),
        'from_user': fromUser,
        'from_user_name': fromUserName,
        'to_user': toUser,
        'to_user_name': toUserName,
        'submitted_at': submittedAt?.toIso8601String(),
        'acknowledged_at': acknowledgedAt?.toIso8601String(),
        'acknowledged_by': acknowledgedBy,
        'updated_at': updatedAt?.toIso8601String(),
      };
}
