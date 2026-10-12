import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/formatters.dart';
import '../core/theme.dart';
import '../models/alarm.dart';
import '../models/equipment.dart';
import '../models/maintenance_order.dart';
import '../providers/connectivity_providers.dart';
import '../providers/live_data.dart';
import '../services/storage_service.dart';
import 'storage_image.dart';

// ------------------------------------------------------------------ colors

Color severityColor(AlarmSeverity s) {
  switch (s) {
    case AlarmSeverity.low:
      return AppColors.primary;
    case AlarmSeverity.medium:
      return AppColors.warning;
    case AlarmSeverity.high:
      return AppColors.maintenance;
    case AlarmSeverity.critical:
      return AppColors.critical;
  }
}

String severityLabel(AlarmSeverity s) => s.name[0].toUpperCase() + s.name.substring(1);

Color priorityColor(MaintenancePriority p) {
  switch (p) {
    case MaintenancePriority.low:
      return AppColors.primary;
    case MaintenancePriority.medium:
      return AppColors.warning;
    case MaintenancePriority.high:
      return AppColors.maintenance;
    case MaintenancePriority.critical:
      return AppColors.critical;
  }
}

Color equipmentStateColor(Equipment e) {
  if (e.underMaintenance || e.actualState == 'maintenance') return AppColors.maintenance;
  if (e.isTripped) return AppColors.critical;
  if (e.isPump) {
    if (e.isRunning) return AppColors.running;
    if (e.isTransitioning) return AppColors.warning;
    return AppColors.steel;
  }
  if (e.isValve) {
    if (e.isOpen) return AppColors.running;
    if (e.isTransitioning) return AppColors.warning;
    return AppColors.steel;
  }
  return AppColors.primary;
}

Color commandStatusColor(String status) {
  switch (status) {
    case 'executed':
      return AppColors.running;
    case 'accepted':
    case 'pending':
      return AppColors.warning;
    case 'rejected':
    case 'failed':
      return AppColors.danger;
    default:
      return AppColors.steel;
  }
}

// ----------------------------------------------------------------- widgets

class StatusChip extends StatelessWidget {
  const StatusChip({
    super.key,
    required this.label,
    required this.color,
    this.icon,
    this.dense = false,
    this.outlined = false,
  });

  final String label;
  final Color color;
  final IconData? icon;
  final bool dense;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: dense ? 7 : 10, vertical: dense ? 2 : 4),
      decoration: BoxDecoration(
        color: outlined ? Colors.transparent : color.withValues(alpha: 0.16),
        border: Border.all(color: color.withValues(alpha: outlined ? 0.9 : 0.4)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: dense ? 12 : 14, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(color: color, fontSize: dense ? 11 : 12, fontWeight: FontWeight.w600, letterSpacing: 0.2),
          ),
        ],
      ),
    );
  }
}

class SeverityDot extends StatelessWidget {
  const SeverityDot(this.severity, {super.key, this.size = 10});

  final AlarmSeverity severity;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = severityColor(severity);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 6)],
      ),
    );
  }
}

class KpiTile extends StatelessWidget {
  const KpiTile({
    super.key,
    required this.label,
    required this.value,
    this.unit,
    this.icon,
    this.color,
    this.subtitle,
    this.onTap,
    this.progress,
  });

  final String label;
  final String value;
  final String? unit;
  final IconData? icon;
  final Color? color;
  final String? subtitle;
  final VoidCallback? onTap;

  /// 0..1 bar under the value (e.g. tank level).
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = color ?? theme.colorScheme.primary;
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 16, color: accent),
                    const SizedBox(width: 6),
                  ],
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Flexible(
                    child: Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700, color: accent),
                    ),
                  ),
                  if (unit != null) ...[
                    const SizedBox(width: 4),
                    Text(unit!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  ],
                ],
              ),
              if (progress != null) ...[
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress!.clamp(0, 1),
                    minHeight: 6,
                    backgroundColor: accent.withValues(alpha: 0.15),
                    color: accent,
                  ),
                ),
              ],
              if (subtitle != null) ...[
                const SizedBox(height: 6),
                Text(
                  subtitle!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class LoadingView extends StatelessWidget {
  const LoadingView({super.key, this.message = 'Loading…'});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3)),
          const SizedBox(height: 14),
          Text(message, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}

String describeError(Object? error) {
  if (error == null) return 'Something went wrong.';
  final text = error.toString();
  if (text.contains('SocketException') || text.contains('Failed host lookup') || text.contains('XMLHttpRequest')) {
    return 'No connection to the server. Check your network and try again.';
  }
  if (text.contains('JWT') || text.contains('expired')) return 'Your session expired. Please sign in again.';
  return text.replaceFirst(RegExp(r'^\w+Exception: '), '').replaceFirst('Bad state: ', '');
}

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.error, this.onRetry, this.title = 'Could not load data'});

  final Object? error;
  final VoidCallback? onRetry;
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 44, color: AppColors.danger),
              const SizedBox(height: 12),
              Text(title, style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
              const SizedBox(height: 6),
              Text(describeError(error), textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
              if (onRetry != null) ...[
                const SizedBox(height: 16),
                FilledButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Retry')),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class EmptyView extends StatelessWidget {
  const EmptyView({
    super.key,
    required this.title,
    this.message,
    this.icon = Icons.inbox_outlined,
    this.action,
  });

  final String title;
  final String? message;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(title, style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
            if (message != null) ...[
              const SizedBox(height: 6),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title, this.subtitle, this.trailing, this.padding});

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: padding ?? const EdgeInsets.only(bottom: 10, top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                if (subtitle != null)
                  Text(subtitle!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class SearchField extends StatelessWidget {
  const SearchField({super.key, required this.onChanged, this.hint = 'Search', this.controller});

  final ValueChanged<String> onChanged;
  final String hint;
  final TextEditingController? controller;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: const Icon(Icons.search, size: 20),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
    );
  }
}

class InfoRow extends StatelessWidget {
  const InfoRow(this.label, this.value, {super.key, this.valueColor});

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(label, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ),
          Expanded(
            child: Text(value, style: theme.textTheme.bodyMedium?.copyWith(color: valueColor, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }
}

/// Scrollable page body with a max width and consistent padding.
class PageBody extends StatelessWidget {
  const PageBody({super.key, required this.child, this.maxWidth = 1240, this.padding, this.scrollable = true});

  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry? padding;
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final content = Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(padding: padding ?? const EdgeInsets.all(16), child: child),
      ),
    );
    return scrollable ? SingleChildScrollView(child: content) : content;
  }
}

/// Inline note shown when data comes from the offline cache or updates are paused.
class StaleNotice extends StatelessWidget {
  const StaleNotice(this.live, {super.key});

  final LiveData<dynamic> live;

  @override
  Widget build(BuildContext context) {
    if (!live.isStale || !live.hasData) return const SizedBox.shrink();
    final text = live.paused
        ? 'Updates paused · showing data from ${fmtRelative(live.updatedAt)}'
        : 'Offline copy · last updated ${fmtRelative(live.updatedAt)}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          const Icon(Icons.history, size: 14, color: AppColors.warning),
          const SizedBox(width: 6),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 12, color: AppColors.warning))),
        ],
      ),
    );
  }
}

/// Renders a live dataset with loading / error / data states.
class LiveBuilder<T> extends StatelessWidget {
  const LiveBuilder({
    super.key,
    required this.live,
    required this.builder,
    this.onRetry,
    this.loadingMessage = 'Loading…',
  });

  final LiveData<T> live;
  final Widget Function(BuildContext context, T data) builder;
  final VoidCallback? onRetry;
  final String loadingMessage;

  @override
  Widget build(BuildContext context) {
    final data = live.data;
    if (data != null) return builder(context, data);
    if (live.error != null) return ErrorView(error: live.error, onRetry: onRetry);
    if (live.paused) {
      return const EmptyView(
        icon: Icons.cloud_off_outlined,
        title: 'No data available offline',
        message: 'Connect to the network to load this page. Cached data will appear here once it has been loaded at least once.',
      );
    }
    return LoadingView(message: loadingMessage);
  }
}

// ----------------------------------------------------------------- helpers

void showSnack(BuildContext context, String message, {bool error = false, bool success = false}) {
  final scheme = Theme.of(context).colorScheme;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              error ? Icons.error_outline : success ? Icons.check_circle_outline : Icons.info_outline,
              size: 18,
              color: error ? AppColors.danger : success ? AppColors.running : scheme.primary,
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
        duration: Duration(seconds: error ? 5 : 3),
      ),
    );
}

Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  bool destructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
        FilledButton(
          style: destructive ? FilledButton.styleFrom(backgroundColor: AppColors.danger) : null,
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Profile picture from the private bucket. [imagePath] is the storage path
/// (`avatars/<uid>.jpg`) or a legacy public URL; it is resolved to a signed URL.
/// Initials are shown while loading, offline, or when there is no picture.
class UserAvatar extends ConsumerWidget {
  const UserAvatar({super.key, required this.initials, this.imagePath, this.radius = 16});

  final String initials;
  final String? imagePath;
  final double radius;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final path = StorageService.normalize(imagePath);
    String? url;
    if (path != null && ref.watch(connectivityProvider)) {
      url = ref.watch(signedUrlProvider(path)).value;
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: scheme.primary.withValues(alpha: 0.2),
      foregroundImage: url != null ? NetworkImage(url) : null,
      onForegroundImageError: url != null ? (_, __) {} : null,
      child: Text(
        initials,
        style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w700, fontSize: radius * 0.8),
      ),
    );
  }
}

class LabeledSwitch extends StatelessWidget {
  const LabeledSwitch({super.key, required this.title, required this.value, required this.onChanged, this.subtitle});

  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle!),
      value: value,
      onChanged: onChanged,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
    );
  }
}
