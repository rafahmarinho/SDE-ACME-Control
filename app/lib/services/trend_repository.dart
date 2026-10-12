import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/trend_sample.dart';

class TrendRepository {
  TrendRepository(this._client);

  final SupabaseClient _client;

  Future<List<TrendSample>> fetchSamples(
    String plantId, {
    required List<String> tags,
    required DateTime since,
    int limit = 6000,
  }) async {
    if (tags.isEmpty) return const [];
    final rows = await _client
        .from('trend_samples')
        .select('tag, ts, value')
        .eq('plant_id', plantId)
        .inFilter('tag', tags)
        .gte('ts', since.toUtc().toIso8601String())
        .order('ts', ascending: true)
        .limit(limit);
    return rows.map(TrendSample.fromJson).toList();
  }
}
