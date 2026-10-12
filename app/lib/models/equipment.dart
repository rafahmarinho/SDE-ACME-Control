import 'json.dart';

enum EquipmentType { pump, valve, tank, sensor }

enum EquipmentMode { manual, auto }

class Equipment {
  const Equipment({
    required this.id,
    required this.plantId,
    required this.tag,
    required this.name,
    required this.type,
    required this.mode,
    required this.requestedState,
    required this.actualState,
    required this.position,
    required this.underMaintenance,
    required this.runtimeHours,
    required this.startsCount,
    required this.params,
    required this.sortOrder,
    this.area,
    this.fault,
    this.interlock,
    this.updatedAt,
  });

  final String id;
  final String plantId;
  final String tag;
  final String name;
  final EquipmentType type;
  final EquipmentMode mode;
  final String requestedState;
  final String actualState;
  final double position;
  final bool underMaintenance;
  final double runtimeHours;
  final int startsCount;
  final Map<String, dynamic> params;
  final int sortOrder;
  final String? area;
  final String? fault;
  final String? interlock;
  final DateTime? updatedAt;

  bool get isPump => type == EquipmentType.pump;
  bool get isValve => type == EquipmentType.valve;
  bool get isTank => type == EquipmentType.tank;
  bool get isSensor => type == EquipmentType.sensor;
  bool get isControllable => isPump || isValve;
  bool get isAuto => mode == EquipmentMode.auto;

  bool get isRunning => actualState == 'running';
  bool get isEngaged => actualState == 'running' || actualState == 'starting';
  bool get isActive => isEngaged || actualState == 'stopping';
  bool get isTripped => actualState == 'tripped';
  bool get isTransitioning =>
      actualState == 'starting' || actualState == 'stopping' || actualState == 'opening' || actualState == 'closing';
  bool get isOpen => actualState == 'open';
  bool get isClosed => actualState == 'closed';

  /// Whether the actual state matches what was requested.
  bool get inSync {
    if (isPump) {
      return requestedState == 'run' ? actualState == 'running' : actualState == 'stopped' || actualState == 'maintenance';
    }
    if (isValve) {
      return requestedState == 'open' ? actualState == 'open' : actualState == 'closed' || actualState == 'maintenance';
    }
    return true;
  }

  String get requestedLabel {
    switch (requestedState) {
      case 'run':
        return 'Run';
      case 'stop':
        return 'Stop';
      case 'open':
        return 'Open';
      case 'close':
        return 'Close';
      default:
        return '--';
    }
  }

  String get actualLabel {
    switch (actualState) {
      case 'ok':
        return 'OK';
      default:
        return actualState.isEmpty ? '--' : actualState[0].toUpperCase() + actualState.substring(1);
    }
  }

  String get unit => params['unit']?.toString() ?? '';
  double get ratedFlow => toDouble(params['rated_flow_m3h']);
  double get capacityM3 => toDouble(params['capacity_m3']);
  String? get sourceRef => params['source']?.toString();
  String? get sinkRef => params['sink']?.toString();
  String? get valveRef => params['valve']?.toString();
  String? get pumpRef => params['pump']?.toString();

  factory Equipment.fromJson(Map<String, dynamic> json) => Equipment(
        id: json['id'] as String,
        plantId: json['plant_id'] as String,
        tag: json['tag'] as String,
        name: json['name'] as String? ?? '',
        type: enumFromString(EquipmentType.values, json['type'], EquipmentType.sensor),
        mode: enumFromString(EquipmentMode.values, json['mode'], EquipmentMode.auto),
        requestedState: json['requested_state'] as String? ?? 'n/a',
        actualState: json['actual_state'] as String? ?? 'ok',
        position: toDouble(json['position']),
        underMaintenance: json['under_maintenance'] == true,
        runtimeHours: toDouble(json['runtime_hours']),
        startsCount: toInt(json['starts_count']),
        params: toMap(json['params']),
        sortOrder: toInt(json['sort_order']),
        area: json['area'] as String?,
        fault: json['fault'] as String?,
        interlock: json['interlock'] as String?,
        updatedAt: toDate(json['updated_at']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'plant_id': plantId,
        'tag': tag,
        'name': name,
        'type': type.name,
        'mode': mode.name,
        'requested_state': requestedState,
        'actual_state': actualState,
        'position': position,
        'under_maintenance': underMaintenance,
        'runtime_hours': runtimeHours,
        'starts_count': startsCount,
        'params': params,
        'sort_order': sortOrder,
        'area': area,
        'fault': fault,
        'interlock': interlock,
        'updated_at': updatedAt?.toIso8601String(),
      };
}
