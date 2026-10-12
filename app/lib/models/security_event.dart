import 'json.dart';

/// Row of the `security_events` audit table (written server-side only).
class SecurityEvent {
  const SecurityEvent({
    required this.id,
    required this.ts,
    required this.action,
    required this.outcome,
    required this.details,
    this.actorId,
    this.actorEmail,
    this.actorRole,
    this.status,
    this.path,
    this.ip,
    this.userAgent,
    this.requestId,
  });

  final int id;
  final DateTime ts;
  final String action;

  /// success | denied | error | rejected
  final String outcome;
  final Map<String, dynamic> details;
  final String? actorId;
  final String? actorEmail;
  final String? actorRole;
  final int? status;
  final String? path;
  final String? ip;
  final String? userAgent;
  final String? requestId;

  static const outcomes = ['success', 'denied', 'error', 'rejected'];

  String get actorLabel => actorEmail ?? actorId ?? 'anonymous';

  factory SecurityEvent.fromJson(Map<String, dynamic> json) => SecurityEvent(
        id: toInt(json['id']),
        ts: toDate(json['ts']) ?? DateTime.now(),
        action: json['action'] as String? ?? '',
        outcome: json['outcome'] as String? ?? 'success',
        details: toMap(json['details']),
        actorId: json['actor_id'] as String?,
        actorEmail: json['actor_email'] as String?,
        actorRole: json['actor_role'] as String?,
        status: json['status'] == null ? null : toInt(json['status']),
        path: json['path'] as String?,
        ip: json['ip'] as String?,
        userAgent: json['user_agent'] as String?,
        requestId: json['request_id'] as String?,
      );
}
