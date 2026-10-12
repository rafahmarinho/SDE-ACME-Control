import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/alarm.dart';
import '../models/command.dart';
import '../models/equipment.dart';
import '../models/event_entry.dart';
import '../models/maintenance_order.dart';
import '../models/process_state.dart';
import '../models/setpoint.dart';
import '../models/shift_handover.dart';
import 'core_providers.dart';
import 'live_data.dart';

List<T> _decodeList<T>(dynamic json, T Function(Map<String, dynamic>) fromJson) =>
    (json as List).map((e) => fromJson(e as Map<String, dynamic>)).toList();

// ----------------------------------------------------------------- process

class ProcessStateNotifier extends LiveNotifier<ProcessState> {
  @override
  String get cacheKey => 'process_state';

  @override
  Stream<ProcessState> source(String plantId) => ref.read(processRepositoryProvider).watchState(plantId).map((s) {
        if (s == null) throw StateError('No process data for this plant yet. Load the demo data from the Simulation page.');
        return s;
      });

  @override
  ProcessState decodeCache(dynamic json) => ProcessState.fromJson(json as Map<String, dynamic>);

  @override
  Object? encodeCache(ProcessState data) => data.toJson();
}

final processStateProvider = NotifierProvider<ProcessStateNotifier, LiveData<ProcessState>>(ProcessStateNotifier.new);

class EquipmentNotifier extends LiveNotifier<List<Equipment>> {
  @override
  String get cacheKey => 'equipment';

  @override
  Stream<List<Equipment>> source(String plantId) => ref.read(processRepositoryProvider).watchEquipment(plantId);

  @override
  List<Equipment> decodeCache(dynamic json) => _decodeList(json, Equipment.fromJson);

  @override
  Object? encodeCache(List<Equipment> data) => data.map((e) => e.toJson()).toList();
}

final equipmentProvider = NotifierProvider<EquipmentNotifier, LiveData<List<Equipment>>>(EquipmentNotifier.new);

final equipmentByTagProvider = Provider<Map<String, Equipment>>((ref) {
  final list = ref.watch(equipmentProvider).data ?? const <Equipment>[];
  return {for (final e in list) e.tag: e};
});

// ------------------------------------------------------------------ alarms

class AlarmsNotifier extends LiveNotifier<List<Alarm>> {
  @override
  String get cacheKey => 'alarms';

  @override
  Stream<List<Alarm>> source(String plantId) => ref.read(alarmRepositoryProvider).watchAlarms(plantId);

  @override
  List<Alarm> decodeCache(dynamic json) => _decodeList(json, Alarm.fromJson);

  @override
  Object? encodeCache(List<Alarm> data) => data.map((e) => e.toJson()).toList();
}

final alarmsProvider = NotifierProvider<AlarmsNotifier, LiveData<List<Alarm>>>(AlarmsNotifier.new);

final activeAlarmsProvider = Provider<List<Alarm>>((ref) {
  final list = ref.watch(alarmsProvider).data ?? const <Alarm>[];
  return list.where((a) => a.isOpen).toList();
});

final unacknowledgedAlarmCountProvider = Provider<int>((ref) {
  return ref.watch(activeAlarmsProvider).where((a) => a.isActive).length;
});

final criticalAlarmProvider = Provider<Alarm?>((ref) {
  final list = ref.watch(activeAlarmsProvider);
  for (final a in list) {
    if (a.severity == AlarmSeverity.critical) return a;
  }
  return null;
});

// ---------------------------------------------------------------- commands

class CommandsNotifier extends LiveNotifier<List<CommandRecord>> {
  @override
  String get cacheKey => 'commands';

  @override
  Stream<List<CommandRecord>> source(String plantId) => ref.read(commandRepositoryProvider).watchCommands(plantId);

  @override
  List<CommandRecord> decodeCache(dynamic json) => _decodeList(json, CommandRecord.fromJson);

  @override
  Object? encodeCache(List<CommandRecord> data) => data.map((e) => e.toJson()).toList();
}

final commandsProvider = NotifierProvider<CommandsNotifier, LiveData<List<CommandRecord>>>(CommandsNotifier.new);

// --------------------------------------------------------------- setpoints

class SetpointsNotifier extends LiveNotifier<List<Setpoint>> {
  @override
  String get cacheKey => 'setpoints';

  @override
  Stream<List<Setpoint>> source(String plantId) => ref.read(setpointRepositoryProvider).watchSetpoints(plantId);

  @override
  List<Setpoint> decodeCache(dynamic json) => _decodeList(json, Setpoint.fromJson);

  @override
  Object? encodeCache(List<Setpoint> data) => data.map((e) => e.toJson()).toList();
}

final setpointsProvider = NotifierProvider<SetpointsNotifier, LiveData<List<Setpoint>>>(SetpointsNotifier.new);

class SetpointRequestsNotifier extends LiveNotifier<List<SetpointRequest>> {
  @override
  String get cacheKey => 'setpoint_requests';

  @override
  Stream<List<SetpointRequest>> source(String plantId) => ref.read(setpointRepositoryProvider).watchRequests(plantId);

  @override
  List<SetpointRequest> decodeCache(dynamic json) => _decodeList(json, SetpointRequest.fromJson);

  @override
  Object? encodeCache(List<SetpointRequest> data) => data.map((e) => e.toJson()).toList();
}

final setpointRequestsProvider =
    NotifierProvider<SetpointRequestsNotifier, LiveData<List<SetpointRequest>>>(SetpointRequestsNotifier.new);

final pendingSetpointCountProvider = Provider<int>((ref) {
  return (ref.watch(setpointRequestsProvider).data ?? const <SetpointRequest>[]).where((r) => r.isPending).length;
});

// ------------------------------------------------------------- maintenance

class MaintenanceOrdersNotifier extends LiveNotifier<List<MaintenanceOrder>> {
  @override
  String get cacheKey => 'maintenance_orders';

  @override
  Stream<List<MaintenanceOrder>> source(String plantId) => ref.read(maintenanceRepositoryProvider).watchOrders(plantId);

  @override
  List<MaintenanceOrder> decodeCache(dynamic json) => _decodeList(json, MaintenanceOrder.fromJson);

  @override
  Object? encodeCache(List<MaintenanceOrder> data) => data.map((e) => e.toJson()).toList();
}

final maintenanceOrdersProvider =
    NotifierProvider<MaintenanceOrdersNotifier, LiveData<List<MaintenanceOrder>>>(MaintenanceOrdersNotifier.new);

final openMaintenanceCountProvider = Provider<int>((ref) {
  return (ref.watch(maintenanceOrdersProvider).data ?? const <MaintenanceOrder>[]).where((o) => !o.isClosed).length;
});

// --------------------------------------------------------------- handovers

class HandoversNotifier extends LiveNotifier<List<ShiftHandover>> {
  @override
  String get cacheKey => 'handovers';

  @override
  Stream<List<ShiftHandover>> source(String plantId) => ref.read(handoverRepositoryProvider).watchHandovers(plantId);

  @override
  List<ShiftHandover> decodeCache(dynamic json) => _decodeList(json, ShiftHandover.fromJson);

  @override
  Object? encodeCache(List<ShiftHandover> data) => data.map((e) => e.toJson()).toList();
}

final handoversProvider = NotifierProvider<HandoversNotifier, LiveData<List<ShiftHandover>>>(HandoversNotifier.new);

// ------------------------------------------------------------------ events

class EventsNotifier extends LiveNotifier<List<EventEntry>> {
  @override
  String get cacheKey => 'events';

  @override
  Stream<List<EventEntry>> source(String plantId) => ref.read(eventRepositoryProvider).watchEvents(plantId);

  @override
  List<EventEntry> decodeCache(dynamic json) => _decodeList(json, EventEntry.fromJson);

  @override
  Object? encodeCache(List<EventEntry> data) => data.map((e) => e.toJson()).toList();
}

final eventsProvider = NotifierProvider<EventsNotifier, LiveData<List<EventEntry>>>(EventsNotifier.new);
