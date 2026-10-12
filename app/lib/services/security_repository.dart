import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/security_event.dart';

/// Read-only access to the `security_events` audit log (supervisors only, enforced by RLS).
class SecurityRepository {
  SecurityRepository(this._client);

  final SupabaseClient _client;

  Future<List<SecurityEvent>> fetchLatest({int limit = 200}) async {
    final rows = await _client.from('security_events').select().order('ts', ascending: false).limit(limit);
    return rows.map(SecurityEvent.fromJson).toList();
  }
}
