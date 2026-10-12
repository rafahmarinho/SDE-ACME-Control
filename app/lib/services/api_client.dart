import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/equipment.dart';
import '../models/scenario.dart';
import '../models/setpoint.dart';

class ApiException implements Exception {
  const ApiException(this.status, this.message, {this.code = 'error', this.details});

  final int status;
  final String message;
  final String code;
  final dynamic details;

  bool get isNetwork => status == 0;
  bool get isRejected => status == 409;
  bool get isForbidden => status == 403;

  @override
  String toString() => message;
}

class TickResult {
  const TickResult({required this.ticked, this.simTime, this.raised = const [], this.cleared = const []});

  final bool ticked;
  final DateTime? simTime;
  final List<String> raised;
  final List<String> cleared;
}

class AdvanceResult {
  const AdvanceResult({
    required this.simulatedSeconds,
    required this.steps,
    required this.events,
    required this.raised,
    required this.cleared,
    this.simTime,
  });

  final int simulatedSeconds;
  final int steps;
  final int events;
  final List<Map<String, dynamic>> raised;
  final List<String> cleared;
  final DateTime? simTime;
}

/// HTTP client for the command and simulation API (TypeScript on Vercel).
class ApiClient {
  ApiClient({required this.baseUrl, required this.tokenProvider, http.Client? client})
      : _http = client ?? http.Client();

  final String baseUrl;
  final String? Function() tokenProvider;
  final http.Client _http;

  static const _timeout = Duration(seconds: 25);

  Uri _uri(String path) => Uri.parse('$baseUrl$path');

  Map<String, String> _headers() {
    final token = tokenProvider();
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Future<Map<String, dynamic>> _send(Future<http.Response> Function() request) async {
    http.Response response;
    try {
      response = await request().timeout(_timeout);
    } on TimeoutException {
      throw const ApiException(0, 'The control API did not respond in time. Check your connection and try again.');
    } catch (e) {
      throw ApiException(0, 'Cannot reach the control API. Control actions need a connection.', details: e.toString());
    }
    Map<String, dynamic> body;
    try {
      body = response.body.isEmpty ? <String, dynamic>{} : jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      body = {'message': response.body};
    }
    if (response.statusCode >= 200 && response.statusCode < 300) return body;
    throw ApiException(
      response.statusCode,
      body['message']?.toString() ?? 'Request failed (${response.statusCode})',
      code: body['error']?.toString() ?? 'error',
      details: body['details'],
    );
  }

  Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body) =>
      _send(() => _http.post(_uri(path), headers: _headers(), body: jsonEncode(body)));

  Future<Map<String, dynamic>> get(String path) => _send(() => _http.get(_uri(path), headers: _headers()));

  // ----------------------------------------------------------------- commands

  Future<Equipment?> sendCommand({
    required String plantId,
    required String equipmentId,
    required String type,
    Object? value,
  }) async {
    final body = await post('/commands', {
      'plantId': plantId,
      'equipmentId': equipmentId,
      'type': type,
      if (value != null) 'value': value,
    });
    final eq = body['equipment'];
    return eq is Map<String, dynamic> ? Equipment.fromJson(eq) : null;
  }

  Future<Equipment> setMaintenance(String equipmentId, {required bool underMaintenance, String? note}) async {
    final body = await post('/equipment/$equipmentId/maintenance', {
      'underMaintenance': underMaintenance,
      if (note != null && note.isNotEmpty) 'note': note,
    });
    return Equipment.fromJson(body['equipment'] as Map<String, dynamic>);
  }

  // --------------------------------------------------------------- simulation

  Future<TickResult> tick(String plantId) async {
    final body = await post('/sim/tick', {'plantId': plantId});
    return TickResult(
      ticked: body['ticked'] == true,
      simTime: body['simTime'] == null ? null : DateTime.tryParse(body['simTime'].toString()),
      raised: (body['raised'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      cleared: (body['cleared'] as List?)?.map((e) => e.toString()).toList() ?? const [],
    );
  }

  Future<AdvanceResult> advance(String plantId, int seconds) async {
    final body = await post('/sim/advance', {'plantId': plantId, 'seconds': seconds});
    return AdvanceResult(
      simulatedSeconds: (body['simulatedSeconds'] as num?)?.toInt() ?? seconds,
      steps: (body['steps'] as num?)?.toInt() ?? 0,
      events: (body['events'] as num?)?.toInt() ?? 0,
      raised: (body['raised'] as List?)?.cast<Map<String, dynamic>>() ?? const [],
      cleared: (body['cleared'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      simTime: body['simTime'] == null ? null : DateTime.tryParse(body['simTime'].toString()),
    );
  }

  Future<void> loadScenario(String plantId, String code) => post('/sim/scenario', {'plantId': plantId, 'scenario': code});

  Future<void> control(String plantId, {required bool running, double? speed}) =>
      post('/sim/control', {'plantId': plantId, 'running': running, if (speed != null) 'speed': speed});

  Future<void> resetDemoData({String? plantId}) => post('/sim/reset', {if (plantId != null) 'plantId': plantId});

  Future<List<Scenario>> scenarios() async {
    final body = await get('/sim/scenarios');
    final list = body['scenarios'] as List? ?? const [];
    return list.map((e) => Scenario.fromJson(e as Map<String, dynamic>)).toList();
  }

  // ---------------------------------------------------------------- setpoints

  Future<SetpointRequest> proposeSetpoint({
    required String plantId,
    required String setpointId,
    required double proposedValue,
    required String justification,
  }) async {
    final body = await post('/setpoints/requests', {
      'plantId': plantId,
      'setpointId': setpointId,
      'proposedValue': proposedValue,
      'justification': justification,
    });
    return SetpointRequest.fromJson(body['request'] as Map<String, dynamic>);
  }

  Future<SetpointRequest> reviewSetpoint(String requestId, {required bool approve, String? note}) async {
    final body = await post('/setpoints/requests/$requestId/review', {
      'decision': approve ? 'approve' : 'reject',
      if (note != null && note.isNotEmpty) 'note': note,
    });
    return SetpointRequest.fromJson(body['request'] as Map<String, dynamic>);
  }
}
