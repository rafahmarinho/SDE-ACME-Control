import 'json.dart';

enum UserRole {
  operator,
  engineer,
  supervisor,
  maintenance;

  String get label {
    switch (this) {
      case UserRole.operator:
        return 'Operator';
      case UserRole.engineer:
        return 'Engineer';
      case UserRole.supervisor:
        return 'Supervisor';
      case UserRole.maintenance:
        return 'Maintenance';
    }
  }

  /// Start/stop pumps, open/close valves, change modes, acknowledge alarms.
  bool get canOperate => this == UserRole.operator || this == UserRole.engineer || this == UserRole.supervisor;

  /// Create and update work orders, lock equipment out for maintenance.
  bool get canMaintain => this == UserRole.maintenance || this == UserRole.engineer || this == UserRole.supervisor;

  /// Scenario selection, advancing the simulation, reset.
  bool get canSimulate => this == UserRole.engineer || this == UserRole.supervisor;

  /// Approve or reject setpoint change proposals.
  bool get canReviewSetpoints => this == UserRole.supervisor;

  bool get canProposeSetpoints => canOperate;

  bool get canHandover => canOperate;
}

class Profile {
  const Profile({
    required this.id,
    required this.email,
    required this.fullName,
    required this.role,
    required this.settings,
    this.avatarUrl,
    this.phone,
    this.defaultPlantId,
    this.updatedAt,
  });

  final String id;
  final String email;
  final String fullName;
  final UserRole role;
  final Map<String, dynamic> settings;
  final String? avatarUrl;
  final String? phone;
  final String? defaultPlantId;
  final DateTime? updatedAt;

  String get displayName => fullName.isNotEmpty ? fullName : email;

  String get initials {
    final parts = displayName.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
  }

  Profile copyWith({
    String? fullName,
    String? avatarUrl,
    String? phone,
    String? defaultPlantId,
    Map<String, dynamic>? settings,
    UserRole? role,
  }) =>
      Profile(
        id: id,
        email: email,
        fullName: fullName ?? this.fullName,
        role: role ?? this.role,
        settings: settings ?? this.settings,
        avatarUrl: avatarUrl ?? this.avatarUrl,
        phone: phone ?? this.phone,
        defaultPlantId: defaultPlantId ?? this.defaultPlantId,
        updatedAt: updatedAt,
      );

  factory Profile.fromJson(Map<String, dynamic> json) => Profile(
        id: json['id'] as String,
        email: json['email'] as String? ?? '',
        fullName: json['full_name'] as String? ?? '',
        role: enumFromString(UserRole.values, json['role'], UserRole.operator),
        settings: toMap(json['settings']),
        avatarUrl: json['avatar_url'] as String?,
        phone: json['phone'] as String?,
        defaultPlantId: json['default_plant_id'] as String?,
        updatedAt: toDate(json['updated_at']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'full_name': fullName,
        'role': role.name,
        'settings': settings,
        'avatar_url': avatarUrl,
        'phone': phone,
        'default_plant_id': defaultPlantId,
        'updated_at': updatedAt?.toIso8601String(),
      };
}
