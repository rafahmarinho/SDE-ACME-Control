import 'json.dart';

enum CommandStatus { pending, accepted, rejected, executed, failed }

class CommandRecord {
  const CommandRecord({
    required this.id,
    required this.plantId,
    required this.type,
    required this.status,
    required this.createdAt,
    this.equipmentId,
    this.equipmentTag,
    this.userId,
    this.userName,
    this.value,
    this.reason,
    this.executedAt,
  });

  final String id;
  final String plantId;
  final String type;
  final CommandStatus status;
  final DateTime createdAt;
  final String? equipmentId;
  final String? equipmentTag;
  final String? userId;
  final String? userName;
  final dynamic value;
  final String? reason;
  final DateTime? executedAt;

  String get label {
    switch (type) {
      case 'set_mode':
        return 'Mode → ${value ?? '?'}';
      case 'start':
        return 'Start';
      case 'stop':
        return 'Stop';
      case 'open':
        return 'Open';
      case 'close':
        return 'Close';
      case 'reset':
        return 'Reset';
      default:
        return type;
    }
  }

  factory CommandRecord.fromJson(Map<String, dynamic> json) => CommandRecord(
        id: json['id'] as String,
        plantId: json['plant_id'] as String,
        type: json['type'] as String? ?? '',
        status: enumFromString(CommandStatus.values, json['status'], CommandStatus.pending),
        createdAt: toDate(json['created_at']) ?? DateTime.now(),
        equipmentId: json['equipment_id'] as String?,
        equipmentTag: json['equipment_tag'] as String?,
        userId: json['user_id'] as String?,
        userName: json['user_name'] as String?,
        value: json['value'],
        reason: json['reason'] as String?,
        executedAt: toDate(json['executed_at']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'plant_id': plantId,
        'type': type,
        'status': status.name,
        'created_at': createdAt.toIso8601String(),
        'equipment_id': equipmentId,
        'equipment_tag': equipmentTag,
        'user_id': userId,
        'user_name': userName,
        'value': value,
        'reason': reason,
        'executed_at': executedAt?.toIso8601String(),
      };
}
