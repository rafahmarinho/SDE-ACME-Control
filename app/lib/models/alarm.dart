import 'json.dart';

enum AlarmSeverity { low, medium, high, critical }

enum AlarmState { active, acknowledged, cleared }

class Alarm {
  const Alarm({
    required this.id,
    required this.plantId,
    required this.code,
    required this.severity,
    required this.message,
    required this.state,
    required this.raisedAt,
    this.equipmentId,
    this.tag,
    this.value,
    this.ackedAt,
    this.ackedBy,
    this.ackedByName,
    this.clearedAt,
  });

  final String id;
  final String plantId;
  final String code;
  final AlarmSeverity severity;
  final String message;
  final AlarmState state;
  final DateTime raisedAt;
  final String? equipmentId;
  final String? tag;
  final double? value;
  final DateTime? ackedAt;
  final String? ackedBy;
  final String? ackedByName;
  final DateTime? clearedAt;

  bool get isActive => state == AlarmState.active;
  bool get isOpen => state != AlarmState.cleared;

  factory Alarm.fromJson(Map<String, dynamic> json) => Alarm(
        id: json['id'] as String,
        plantId: json['plant_id'] as String,
        code: json['code'] as String,
        severity: enumFromString(AlarmSeverity.values, json['severity'], AlarmSeverity.medium),
        message: json['message'] as String? ?? '',
        state: enumFromString(AlarmState.values, json['state'], AlarmState.active),
        raisedAt: toDate(json['raised_at']) ?? DateTime.now(),
        equipmentId: json['equipment_id'] as String?,
        tag: json['tag'] as String?,
        value: toDoubleOrNull(json['value']),
        ackedAt: toDate(json['acked_at']),
        ackedBy: json['acked_by'] as String?,
        ackedByName: json['acked_by_name'] as String?,
        clearedAt: toDate(json['cleared_at']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'plant_id': plantId,
        'code': code,
        'severity': severity.name,
        'message': message,
        'state': state.name,
        'raised_at': raisedAt.toIso8601String(),
        'equipment_id': equipmentId,
        'tag': tag,
        'value': value,
        'acked_at': ackedAt?.toIso8601String(),
        'acked_by': ackedBy,
        'acked_by_name': ackedByName,
        'cleared_at': clearedAt?.toIso8601String(),
      };
}
