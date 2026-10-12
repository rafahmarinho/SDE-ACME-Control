import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../models/trend_sample.dart';
import '../../providers/connectivity_providers.dart';
import '../../providers/core_providers.dart';
import '../../providers/live_notifiers.dart';
import '../../providers/plant_providers.dart';
import '../../widgets/common.dart';

const _seriesColors = <Color>[
  AppColors.water,
  Color(0xFFA78BFA),
  AppColors.running,
  AppColors.warning,
  Color(0xFFF472B6),
  Color(0xFF60A5FA),
  Color(0xFFFB7185),
  AppColors.maintenance,
  Color(0xFF2DD4BF),
  Color(0xFFFACC15),
];

class TrendsScreen extends ConsumerStatefulWidget {
  const TrendsScreen({super.key});

  @override
  ConsumerState<TrendsScreen> createState() => _TrendsScreenState();
}

class _TrendsScreenState extends ConsumerState<TrendsScreen> {
  final Set<String> _tags = {'LT1', 'LT2'};
  Duration _range = const Duration(hours: 6);
  bool _normalize = false;
  bool _loading = true;
  Object? _error;
  List<TrendSample> _samples = const [];
  Timer? _timer;
  String? _plantId;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (ref.read(liveEnabledProvider)) _load(silent: true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    final plantId = ref.read(effectivePlantIdProvider);
    if (plantId == null) return;
    if (!silent) setState(() => _loading = true);
    try {
      final simNow = ref.read(processStateProvider).data?.simTime ?? DateTime.now();
      final since = simNow.subtract(_range);
      final samples = await ref.read(trendRepositoryProvider).fetchSamples(plantId, tags: _tags.toList(), since: since);
      if (mounted) {
        setState(() {
          _samples = samples;
          _error = null;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final plantId = ref.watch(effectivePlantIdProvider);
    if (plantId != _plantId) {
      _plantId = plantId;
      Future.microtask(_load);
    }
    final state = ref.watch(processStateProvider).data;
    final online = ref.watch(connectivityProvider);

    return PageBody(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final t in trendTags)
                FilterChip(
                  avatar: CircleAvatar(backgroundColor: _seriesColors[t.colorIndex], radius: 5),
                  label: Text(t.tag),
                  tooltip: '${t.label} (${t.unit})',
                  selected: _tags.contains(t.tag),
                  onSelected: (v) {
                    setState(() => v ? _tags.add(t.tag) : _tags.remove(t.tag));
                    _load();
                  },
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              SegmentedButton<Duration>(
                segments: const [
                  ButtonSegment(value: Duration(hours: 1), label: Text('1 h')),
                  ButtonSegment(value: Duration(hours: 6), label: Text('6 h')),
                  ButtonSegment(value: Duration(hours: 24), label: Text('24 h')),
                ],
                selected: {_range},
                onSelectionChanged: (s) {
                  setState(() => _range = s.first);
                  _load();
                },
              ),
              const SizedBox(width: 12),
              FilterChip(label: const Text('Normalise'), selected: _normalize, onSelected: (v) => setState(() => _normalize = v)),
              const Spacer(),
              IconButton(tooltip: 'Refresh', onPressed: online ? _load : null, icon: const Icon(Icons.refresh)),
            ],
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
              child: SizedBox(
                height: 360,
                child: _loading
                    ? const LoadingView(message: 'Loading trend data…')
                    : _error != null
                        ? ErrorView(error: _error, onRetry: _load)
                        : _samples.isEmpty
                            ? const EmptyView(icon: Icons.show_chart, title: 'No samples in this range', message: 'Advance the simulation or wait for new samples. One sample per tag is stored every simulated minute.')
                            : _Chart(samples: _samples, tags: _tags, normalize: _normalize),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              for (final t in trendTags.where((t) => _tags.contains(t.tag)))
                Chip(
                  avatar: CircleAvatar(backgroundColor: _seriesColors[t.colorIndex], radius: 5),
                  label: Text('${t.label}: ${fmtNum(state?.value(t.tag), decimals: t.unit == 'bar' || t.unit == 'NTU' || t.unit == 'mg/L' ? 2 : 1)} ${t.unit}'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Samples are stored in simulated time. Trend history refreshes every 30 s while online.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}

class _Chart extends StatelessWidget {
  const _Chart({required this.samples, required this.tags, required this.normalize});

  final List<TrendSample> samples;
  final Set<String> tags;
  final bool normalize;

  @override
  Widget build(BuildContext context) {
    final byTag = <String, List<TrendSample>>{};
    for (final s in samples) {
      byTag.putIfAbsent(s.tag, () => []).add(s);
    }
    final minX = samples.first.ts.millisecondsSinceEpoch.toDouble();
    final maxX = samples.map((s) => s.ts.millisecondsSinceEpoch).reduce((a, b) => a > b ? a : b).toDouble();
    final span = (maxX - minX).clamp(1, double.infinity);

    final bars = <LineChartBarData>[];
    double minY = double.infinity;
    double maxY = -double.infinity;
    for (final info in trendTags) {
      final list = byTag[info.tag];
      if (list == null || list.isEmpty) continue;
      final seriesMax = list.map((s) => s.value).reduce((a, b) => a > b ? a : b);
      final scale = normalize && seriesMax > 0 ? 100 / seriesMax : 1.0;
      final spots = [for (final s in list) FlSpot(s.ts.millisecondsSinceEpoch.toDouble(), s.value * scale)];
      for (final p in spots) {
        if (p.y < minY) minY = p.y;
        if (p.y > maxY) maxY = p.y;
      }
      bars.add(
        LineChartBarData(
          spots: spots,
          color: _seriesColors[info.colorIndex],
          barWidth: 2,
          isCurved: false,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(show: true, color: _seriesColors[info.colorIndex].withValues(alpha: 0.06)),
        ),
      );
    }
    if (!minY.isFinite) {
      minY = 0;
      maxY = 1;
    }
    final pad = (maxY - minY) * 0.1 + 0.5;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;

    return LineChart(
      LineChartData(
        minX: minX,
        maxX: maxX,
        minY: (minY - pad).clamp(normalize ? 0 : -double.infinity, double.infinity),
        maxY: maxY + pad,
        lineBarsData: bars,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) => FlLine(color: AppColors.outline.withValues(alpha: 0.6), strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 46,
              getTitlesWidget: (value, meta) => Text(fmtNum(value, decimals: maxY - minY < 5 ? 2 : 0), style: TextStyle(fontSize: 10, color: muted)),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              interval: span / 5,
              getTitlesWidget: (value, meta) {
                if (value == meta.min || value == meta.max) return const SizedBox.shrink();
                final dt = DateTime.fromMillisecondsSinceEpoch(value.toInt());
                return Padding(padding: const EdgeInsets.only(top: 6), child: Text(fmtTimeShort(dt), style: TextStyle(fontSize: 10, color: muted)));
              },
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => AppColors.surfaceHigher,
            getTooltipItems: (spots) => [
              for (final s in spots)
                LineTooltipItem(
                  '${trendTags.firstWhere((t) => _seriesColors[t.colorIndex] == s.bar.color, orElse: () => trendTags.first).tag} ${fmtNum(s.y, decimals: 2)}\n${fmtTimeShort(DateTime.fromMillisecondsSinceEpoch(s.x.toInt()))}',
                  TextStyle(color: s.bar.color ?? Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
