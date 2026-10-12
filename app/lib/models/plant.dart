import 'json.dart';

class Plant {
  const Plant({
    required this.id,
    required this.code,
    required this.name,
    required this.location,
    required this.timezone,
    required this.status,
    required this.designCapacityM3h,
    this.description,
  });

  final String id;
  final String code;
  final String name;
  final String location;
  final String timezone;
  final String status;
  final double designCapacityM3h;
  final String? description;

  factory Plant.fromJson(Map<String, dynamic> json) => Plant(
        id: json['id'] as String,
        code: json['code'] as String,
        name: json['name'] as String,
        location: json['location'] as String? ?? '',
        timezone: json['timezone'] as String? ?? 'UTC',
        status: json['status'] as String? ?? 'online',
        designCapacityM3h: toDouble(json['design_capacity_m3h']),
        description: json['description'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'code': code,
        'name': name,
        'location': location,
        'timezone': timezone,
        'status': status,
        'design_capacity_m3h': designCapacityM3h,
        'description': description,
      };
}
