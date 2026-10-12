import 'json.dart';

class Setpoint {
  const Setpoint({
    required this.id,
    required this.plantId,
    required this.key,
    required this.label,
    required this.value,
    required this.unit,
    required this.minValue,
    required this.maxValue,
    required this.groupName,
    this.description,
    this.updatedAt,
    this.updatedBy,
  });

  final String id;
  final String plantId;
  final String key;
  final String label;
  final double value;
  final String unit;
  final double minValue;
  final double maxValue;
  final String groupName;
  final String? description;
  final DateTime? updatedAt;
  final String? updatedBy;

  factory Setpoint.fromJson(Map<String, dynamic> json) => Setpoint(
        id: json['id'] as String,
        plantId: json['plant_id'] as String,
        key: json['key'] as String,
        label: json['label'] as String? ?? '',
        value: toDouble(json['value']),
        unit: json['unit'] as String? ?? '',
        minValue: toDouble(json['min_value']),
        maxValue: toDouble(json['max_value'], 100),
        groupName: json['group_name'] as String? ?? 'Process',
        description: json['description'] as String?,
        updatedAt: toDate(json['updated_at']),
        updatedBy: json['updated_by'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'plant_id': plantId,
        'key': key,
        'label': label,
        'value': value,
        'unit': unit,
        'min_value': minValue,
        'max_value': maxValue,
        'group_name': groupName,
        'description': description,
        'updated_at': updatedAt?.toIso8601String(),
        'updated_by': updatedBy,
      };
}

enum SetpointRequestStatus { pending, approved, rejected }

class SetpointRequest {
  const SetpointRequest({
    required this.id,
    required this.plantId,
    required this.setpointId,
    required this.setpointKey,
    required this.setpointLabel,
    required this.currentValue,
    required this.proposedValue,
    required this.justification,
    required this.status,
    required this.createdAt,
    this.requestedBy,
    this.requestedByName,
    this.reviewedBy,
    this.reviewedByName,
    this.reviewNote,
    this.reviewedAt,
  });

  final String id;
  final String plantId;
  final String setpointId;
  final String setpointKey;
  final String setpointLabel;
  final double currentValue;
  final double proposedValue;
  final String justification;
  final SetpointRequestStatus status;
  final DateTime createdAt;
  final String? requestedBy;
  final String? requestedByName;
  final String? reviewedBy;
  final String? reviewedByName;
  final String? reviewNote;
  final DateTime? reviewedAt;

  bool get isPending => status == SetpointRequestStatus.pending;

  factory SetpointRequest.fromJson(Map<String, dynamic> json) => SetpointRequest(
        id: json['id'] as String,
        plantId: json['plant_id'] as String,
        setpointId: json['setpoint_id'] as String,
        setpointKey: json['setpoint_key'] as String? ?? '',
        setpointLabel: json['setpoint_label'] as String? ?? '',
        currentValue: toDouble(json['current_value']),
        proposedValue: toDouble(json['proposed_value']),
        justification: json['justification'] as String? ?? '',
        status: enumFromString(SetpointRequestStatus.values, json['status'], SetpointRequestStatus.pending),
        createdAt: toDate(json['created_at']) ?? DateTime.now(),
        requestedBy: json['requested_by'] as String?,
        requestedByName: json['requested_by_name'] as String?,
        reviewedBy: json['reviewed_by'] as String?,
        reviewedByName: json['reviewed_by_name'] as String?,
        reviewNote: json['review_note'] as String?,
        reviewedAt: toDate(json['reviewed_at']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'plant_id': plantId,
        'setpoint_id': setpointId,
        'setpoint_key': setpointKey,
        'setpoint_label': setpointLabel,
        'current_value': currentValue,
        'proposed_value': proposedValue,
        'justification': justification,
        'status': status.name,
        'created_at': createdAt.toIso8601String(),
        'requested_by': requestedBy,
        'requested_by_name': requestedByName,
        'reviewed_by': reviewedBy,
        'reviewed_by_name': reviewedByName,
        'review_note': reviewNote,
        'reviewed_at': reviewedAt?.toIso8601String(),
      };
}
