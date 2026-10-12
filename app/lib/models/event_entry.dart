import 'json.dart';

class EventEntry {
  const EventEntry({
    required this.id,
    required this.ts,
    required this.category,
    required this.level,
    required this.message,
    required this.data,
    this.plantId,
    this.actor,
  });

  final int id;
  final DateTime ts;
  final String category;
  final String level;
  final String message;
  final Map<String, dynamic> data;
  final String? plantId;
  final String? actor;

  factory EventEntry.fromJson(Map<String, dynamic> json) => EventEntry(
        id: toInt(json['id']),
        ts: toDate(json['ts']) ?? DateTime.now(),
        category: json['category'] as String? ?? 'system',
        level: json['level'] as String? ?? 'info',
        message: json['message'] as String? ?? '',
        data: toMap(json['data']),
        plantId: json['plant_id'] as String?,
        actor: json['actor'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'ts': ts.toIso8601String(),
        'category': category,
        'level': level,
        'message': message,
        'data': data,
        'plant_id': plantId,
        'actor': actor,
      };
}
