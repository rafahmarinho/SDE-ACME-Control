import 'json.dart';

class TankState {
  const TankState({
    required this.level,
    required this.volume,
    required this.capacity,
    required this.inflow,
    required this.outflow,
  });

  final double level;
  final double volume;
  final double capacity;
  final double inflow;
  final double outflow;

  double get netFlow => inflow - outflow;

  factory TankState.fromJson(Map<String, dynamic> json) => TankState(
        level: toDouble(json['level']),
        volume: toDouble(json['volume']),
        capacity: toDouble(json['capacity'], 1),
        inflow: toDouble(json['inflow']),
        outflow: toDouble(json['outflow']),
      );

  Map<String, dynamic> toJson() => {
        'level': level,
        'volume': volume,
        'capacity': capacity,
        'inflow': inflow,
        'outflow': outflow,
      };
}

class ProcessConditions {
  const ProcessConditions({
    required this.sourceAvailable,
    required this.demandFactor,
    required this.demandNominal,
    required this.demandM3h,
    required this.sensorFaults,
    required this.overflowM3h,
  });

  final bool sourceAvailable;
  final double demandFactor;
  final double demandNominal;
  final double demandM3h;
  final List<String> sensorFaults;
  final double overflowM3h;

  factory ProcessConditions.fromJson(Map<String, dynamic> json) => ProcessConditions(
        sourceAvailable: json['source_available'] != false,
        demandFactor: toDouble(json['demand_factor'], 1),
        demandNominal: toDouble(json['demand_nominal']),
        demandM3h: toDouble(json['demand_m3h']),
        sensorFaults: toStringList(json['sensor_faults']),
        overflowM3h: toDouble(json['overflow_m3h']),
      );

  Map<String, dynamic> toJson() => {
        'source_available': sourceAvailable,
        'demand_factor': demandFactor,
        'demand_nominal': demandNominal,
        'demand_m3h': demandM3h,
        'sensor_faults': sensorFaults,
        'overflow_m3h': overflowM3h,
      };
}

class ProcessState {
  const ProcessState({
    required this.plantId,
    required this.scenario,
    required this.simTime,
    required this.speed,
    required this.running,
    required this.values,
    required this.tanks,
    required this.conditions,
    this.lastTickAt,
    this.updatedAt,
  });

  final String plantId;
  final String scenario;
  final DateTime simTime;
  final double speed;
  final bool running;
  final Map<String, double> values;
  final Map<String, TankState> tanks;
  final ProcessConditions conditions;
  final DateTime? lastTickAt;
  final DateTime? updatedAt;

  double? value(String tag) => values[tag];
  TankState? tank(String tag) => tanks[tag];
  bool isFaulted(String tag) => conditions.sensorFaults.contains(tag);

  factory ProcessState.fromJson(Map<String, dynamic> json) {
    final values = <String, double>{};
    toMap(json['values']).forEach((k, v) => values[k] = toDouble(v));
    final tanks = <String, TankState>{};
    toMap(json['tanks']).forEach((k, v) => tanks[k] = TankState.fromJson(toMap(v)));
    return ProcessState(
      plantId: json['plant_id'] as String,
      scenario: json['scenario'] as String? ?? 'normal',
      simTime: toDate(json['sim_time']) ?? DateTime.now(),
      speed: toDouble(json['speed'], 1),
      running: json['running'] != false,
      values: values,
      tanks: tanks,
      conditions: ProcessConditions.fromJson(toMap(json['conditions'])),
      lastTickAt: toDate(json['last_tick_at']),
      updatedAt: toDate(json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() => {
        'plant_id': plantId,
        'scenario': scenario,
        'sim_time': simTime.toIso8601String(),
        'speed': speed,
        'running': running,
        'values': values,
        'tanks': tanks.map((k, v) => MapEntry(k, v.toJson())),
        'conditions': conditions.toJson(),
        'last_tick_at': lastTickAt?.toIso8601String(),
        'updated_at': updatedAt?.toIso8601String(),
      };
}
