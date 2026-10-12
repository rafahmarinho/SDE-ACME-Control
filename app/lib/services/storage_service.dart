import 'package:supabase_flutter/supabase_flutter.dart';

/// Resolves objects in the private `attachments` bucket to short-lived signed URLs.
class StorageService {
  StorageService(this._client);

  final SupabaseClient _client;

  static const bucket = 'attachments';
  static const _ttl = Duration(seconds: 3600);

  /// Refresh a little before the server-side expiry so a cached URL never fails mid-load.
  static const _safety = Duration(minutes: 5);

  final _cache = <String, _SignedEntry>{};

  /// Legacy rows stored a full public URL; extract the object path from it.
  static String? pathFromUrl(String? url) {
    if (url == null || url.isEmpty) return null;
    const marker = '/storage/v1/object/public/$bucket/';
    final i = url.indexOf(marker);
    if (i < 0) return null;
    final rest = url.substring(i + marker.length);
    final q = rest.indexOf('?');
    final path = q < 0 ? rest : rest.substring(0, q);
    return path.isEmpty ? null : Uri.decodeComponent(path);
  }

  /// Accepts either a storage path or a legacy public URL and returns the path.
  static String? normalize(String? pathOrUrl) {
    if (pathOrUrl == null || pathOrUrl.isEmpty) return null;
    if (pathOrUrl.startsWith('http://') || pathOrUrl.startsWith('https://')) return pathFromUrl(pathOrUrl);
    return pathOrUrl;
  }

  Future<String> signedUrl(String path) async {
    final now = DateTime.now();
    final hit = _cache[path];
    if (hit != null && hit.expiresAt.isAfter(now)) return hit.url;
    final url = await _client.storage.from(bucket).createSignedUrl(path, _ttl.inSeconds);
    _cache[path] = _SignedEntry(url, now.add(_ttl - _safety));
    return url;
  }

  /// Drop a cached URL (e.g. after re-uploading the same path).
  void invalidate(String path) => _cache.remove(path);

  void clear() => _cache.clear();
}

class _SignedEntry {
  const _SignedEntry(this.url, this.expiresAt);

  final String url;
  final DateTime expiresAt;
}
