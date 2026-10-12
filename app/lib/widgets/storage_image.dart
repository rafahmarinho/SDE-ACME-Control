import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../providers/connectivity_providers.dart';
import '../providers/core_providers.dart';
import '../services/storage_service.dart';

/// Signed URL for an object path in the private `attachments` bucket.
final signedUrlProvider = FutureProvider.autoDispose.family<String, String>(
  (ref, path) => ref.watch(storageServiceProvider).signedUrl(path),
);

/// Shows an image stored in the private bucket. [source] is a storage path
/// (`maintenance/<plant>/<file>`, `avatars/<uid>.jpg`) or a legacy public URL.
/// While offline, or when the path cannot be resolved, a placeholder is shown.
class StorageImage extends ConsumerWidget {
  const StorageImage({
    super.key,
    required this.source,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
  });

  final String? source;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;

  Widget _box(IconData icon) => Container(
        width: width,
        height: height,
        color: AppColors.surfaceHigh,
        alignment: Alignment.center,
        child: Icon(icon, color: AppColors.muted),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final path = StorageService.normalize(source);
    final online = ref.watch(connectivityProvider);

    Widget child;
    if (path == null) {
      child = _box(Icons.broken_image_outlined);
    } else if (!online) {
      child = _box(Icons.cloud_off_outlined);
    } else {
      child = ref.watch(signedUrlProvider(path)).when(
            loading: () => SizedBox(
              width: width,
              height: height,
              child: const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
            ),
            error: (_, __) => _box(Icons.broken_image_outlined),
            data: (url) => Image.network(
              url,
              width: width,
              height: height,
              fit: fit,
              errorBuilder: (_, __, ___) => _box(Icons.broken_image_outlined),
            ),
          );
    }
    if (borderRadius == null) return child;
    return ClipRRect(borderRadius: borderRadius!, child: child);
  }
}
