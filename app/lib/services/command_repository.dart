import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/command.dart';

class CommandRepository {
  CommandRepository(this._client);

  final SupabaseClient _client;

  Stream<List<CommandRecord>> watchCommands(String plantId, {int limit = 200}) {
    return _client
        .from('commands')
        .stream(primaryKey: ['id'])
        .eq('plant_id', plantId)
        .order('created_at', ascending: false)
        .limit(limit)
        .map((rows) => rows.map(CommandRecord.fromJson).toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt)));
  }
}
