import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/formatters.dart';
import '../core/theme.dart';
import '../models/equipment.dart';
import '../models/process_state.dart';

/// Animated 2.5D schematic of the water treatment line:
/// intake -> P1 -> V1 -> T1 -> P2 -> V2 -> treatment -> T2 -> P3 -> V3 -> network.
///
/// Wide layout flows left to right, compact layout (phones) flows top to bottom.
class ProcessSchematic extends StatefulWidget {
  const ProcessSchematic({
    super.key,
    required this.equipment,
    required this.state,
    required this.compact,
    this.onTapEquipment,
    this.selectedTag,
  });

  final List<Equipment> equipment;
  final ProcessState state;
  final bool compact;
  final void Function(Equipment equipment)? onTapEquipment;
  final String? selectedTag;

  static double aspectRatio(bool compact) => compact ? _Layout.narrowSize.aspectRatio : _Layout.wideSize.aspectRatio;

  @override
  State<ProcessSchematic> createState() => _ProcessSchematicState();
}

class _ProcessSchematicState extends State<ProcessSchematic> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final layout = widget.compact ? _Layout.narrow() : _Layout.wide();
    final byTag = {for (final e in widget.equipment) e.tag: e};
    return AspectRatio(
      aspectRatio: layout.size.aspectRatio,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final scale = constraints.maxWidth / layout.size.width;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (details) {
              final p = details.localPosition / scale;
              for (final hit in layout.hits) {
                if (hit.rect.contains(p)) {
                  final e = byTag[hit.tag];
                  if (e != null) widget.onTapEquipment?.call(e);
                  return;
                }
              }
            },
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) => CustomPaint(
                size: Size.infinite,
                painter: _SchematicPainter(
                  layout: layout,
                  byTag: byTag,
                  state: widget.state,
                  phase: _controller.value,
                  scale: scale,
                  selectedTag: widget.selectedTag,
                  textColor: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// =============================================================== layout

class _Hit {
  const _Hit(this.rect, this.tag);

  final Rect rect;
  final String tag;
}

class _Pipe {
  const _Pipe(this.points, this.flowTag, this.pumpTag);

  final List<Offset> points;
  final String flowTag;
  final String pumpTag;
}

class _Layout {
  _Layout({
    required this.size,
    required this.vertical,
    required this.intake,
    required this.network,
    required this.p1,
    required this.v1,
    required this.p2,
    required this.v2,
    required this.p3,
    required this.v3,
    required this.t1,
    required this.t2,
    required this.treatment,
    required this.pipes,
  }) {
    hits = [
      _Hit(Rect.fromCircle(center: p1, radius: 36), 'P1'),
      _Hit(Rect.fromCircle(center: p2, radius: 36), 'P2'),
      _Hit(Rect.fromCircle(center: p3, radius: 36), 'P3'),
      _Hit(Rect.fromCircle(center: v1, radius: 28), 'V1'),
      _Hit(Rect.fromCircle(center: v2, radius: 28), 'V2'),
      _Hit(Rect.fromCircle(center: v3, radius: 28), 'V3'),
      _Hit(t1.inflate(10), 'T1'),
      _Hit(t2.inflate(10), 'T2'),
    ];
  }

  static const wideSize = Size(1180, 470);
  static const narrowSize = Size(440, 1220);

  final Size size;
  final bool vertical;
  final Offset intake;
  final Offset network;
  final Offset p1;
  final Offset v1;
  final Offset p2;
  final Offset v2;
  final Offset p3;
  final Offset v3;
  final Rect t1;
  final Rect t2;
  final Rect treatment;
  final List<_Pipe> pipes;
  late final List<_Hit> hits;

  factory _Layout.wide() {
    const y = 330.0;
    const t1 = Rect.fromLTWH(320, 110, 130, 240);
    const t2 = Rect.fromLTWH(800, 95, 140, 255);
    const treatment = Rect.fromLTWH(648, 290, 92, 80);
    return _Layout(
      size: wideSize,
      vertical: false,
      intake: const Offset(60, y),
      network: const Offset(1135, y),
      p1: const Offset(165, y),
      v1: const Offset(245, y),
      p2: const Offset(520, y),
      v2: const Offset(600, y),
      p3: const Offset(1000, y),
      v3: const Offset(1068, y),
      t1: t1,
      t2: t2,
      treatment: treatment,
      pipes: [
        _Pipe([const Offset(100, y), const Offset(165, y), const Offset(245, y), const Offset(285, y), const Offset(285, 150), Offset(t1.left, 150)], 'FT1', 'P1'),
        _Pipe([Offset(t1.right, y), const Offset(520, y), const Offset(600, y), Offset(treatment.left, y)], 'FT2', 'P2'),
        _Pipe([Offset(treatment.right, y), const Offset(770, y), const Offset(770, 135), Offset(t2.left, 135)], 'FT2', 'P2'),
        _Pipe([Offset(t2.right, y), const Offset(1000, y), const Offset(1068, y), const Offset(1105, y)], 'FT3', 'P3'),
      ],
    );
  }

  factory _Layout.narrow() {
    const x = 220.0;
    const t1 = Rect.fromLTWH(130, 300, 180, 175);
    const t2 = Rect.fromLTWH(120, 790, 200, 180);
    const treatment = Rect.fromLTWH(150, 660, 140, 72);
    return _Layout(
      size: narrowSize,
      vertical: true,
      intake: const Offset(x, 60),
      network: const Offset(x, 1160),
      p1: const Offset(x, 150),
      v1: const Offset(x, 228),
      p2: const Offset(x, 545),
      v2: const Offset(x, 615),
      p3: const Offset(x, 1030),
      v3: const Offset(x, 1098),
      t1: t1,
      t2: t2,
      treatment: treatment,
      pipes: [
        _Pipe([const Offset(x, 92), const Offset(x, 150), const Offset(x, 228), Offset(x, t1.top + 8)], 'FT1', 'P1'),
        _Pipe([Offset(x, t1.bottom - 4), const Offset(x, 545), const Offset(x, 615), Offset(x, treatment.top)], 'FT2', 'P2'),
        _Pipe([Offset(x, treatment.bottom), Offset(x, t2.top + 8)], 'FT2', 'P2'),
        _Pipe([Offset(x, t2.bottom - 4), const Offset(x, 1030), const Offset(x, 1098), const Offset(x, 1135)], 'FT3', 'P3'),
      ],
    );
  }
}

// ============================================================== painter

class _SchematicPainter extends CustomPainter {
  _SchematicPainter({
    required this.layout,
    required this.byTag,
    required this.state,
    required this.phase,
    required this.scale,
    required this.textColor,
    this.selectedTag,
  });

  final _Layout layout;
  final Map<String, Equipment> byTag;
  final ProcessState state;
  final double phase;
  final double scale;
  final Color textColor;
  final String? selectedTag;

  static const _pipeDark = Color(0xFF26324A);
  static const _pipeEdge = Color(0xFF3B4A66);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(scale);

    _drawGrid(canvas);
    for (final pipe in layout.pipes) {
      _drawPipe(canvas, pipe);
    }
    _drawIntake(canvas);
    _drawNetwork(canvas);
    _drawTank(canvas, layout.t1, 'T1', 'LT1');
    _drawTank(canvas, layout.t2, 'T2', 'LT2');
    _drawTreatment(canvas);
    _drawValve(canvas, layout.v1, 'V1');
    _drawValve(canvas, layout.v2, 'V2');
    _drawValve(canvas, layout.v3, 'V3');
    _drawPump(canvas, layout.p1, 'P1', 'PT1');
    _drawPump(canvas, layout.p2, 'P2', 'PT2');
    _drawPump(canvas, layout.p3, 'P3', 'PT3');
    _drawFlowLabels(canvas);

    canvas.restore();
  }

  // ----------------------------------------------------------- helpers

  double _flowFraction(String flowTag, String pumpTag) {
    final flow = state.value(flowTag) ?? 0;
    final rated = byTag[pumpTag]?.ratedFlow ?? 100;
    if (rated <= 0) return 0;
    return (flow / rated).clamp(0.0, 1.0);
  }

  void _text(
    Canvas canvas,
    String text,
    Offset at, {
    double size = 12,
    Color? color,
    FontWeight weight = FontWeight.w500,
    TextAlign align = TextAlign.center,
    double maxWidth = 200,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(fontSize: size, color: color ?? textColor, fontWeight: weight, fontFeatures: const [FontFeature.tabularFigures()]),
      ),
      textDirection: TextDirection.ltr,
      textAlign: align,
      maxLines: 2,
    )..layout(maxWidth: maxWidth);
    final dx = align == TextAlign.center
        ? at.dx - painter.width / 2
        : align == TextAlign.right
            ? at.dx - painter.width
            : at.dx;
    painter.paint(canvas, Offset(dx, at.dy - painter.height / 2));
  }

  void _drawGrid(Canvas canvas) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.025)
      ..strokeWidth = 1;
    const step = 40.0;
    for (double x = 0; x < layout.size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, layout.size.height), paint);
    }
    for (double y = 0; y < layout.size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(layout.size.width, y), paint);
    }
  }

  void _drawPipe(Canvas canvas, _Pipe pipe) {
    final path = Path()..moveTo(pipe.points.first.dx, pipe.points.first.dy);
    for (final p in pipe.points.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = _pipeEdge
        ..style = PaintingStyle.stroke
        ..strokeWidth = 14
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = _pipeDark
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );

    final fraction = _flowFraction(pipe.flowTag, pipe.pumpTag);
    if (fraction <= 0.01) return;

    // water fill
    canvas.drawPath(
      path,
      Paint()
        ..color = AppColors.waterDeep.withValues(alpha: 0.9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );

    // moving dashes
    const dash = 12.0;
    const gap = 14.0;
    final speed = 0.4 + fraction * 1.2;
    final offset = (phase * speed * (dash + gap) * 3) % (dash + gap);
    final metrics = path.computeMetrics();
    final dashPaint = Paint()
      ..color = AppColors.water.withValues(alpha: 0.55 + 0.45 * fraction)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    for (final metric in metrics) {
      double d = -offset;
      while (d < metric.length) {
        final start = math.max(0.0, d);
        final end = math.min(metric.length, d + dash);
        if (end > start) {
          canvas.drawPath(metric.extractPath(start, end), dashPaint);
        }
        d += dash + gap;
      }
    }
  }

  void _drawFlowLabels(Canvas canvas) {
    final muted = textColor.withValues(alpha: 0.7);
    String fmt(String tag) => '${fmtNum(state.value(tag))} m³/h';
    if (!layout.vertical) {
      _text(canvas, 'FT1', const Offset(275, 222), size: 11, color: muted, align: TextAlign.right);
      _text(canvas, fmt('FT1'), const Offset(275, 238), size: 12, color: AppColors.water, weight: FontWeight.w700, align: TextAlign.right);
      _text(canvas, 'FT2', const Offset(760, 208), size: 11, color: muted, align: TextAlign.right);
      _text(canvas, fmt('FT2'), const Offset(760, 224), size: 12, color: AppColors.water, weight: FontWeight.w700, align: TextAlign.right);
      _text(canvas, 'FT3', const Offset(1098, 290), size: 11, color: muted);
      _text(canvas, fmt('FT3'), const Offset(1098, 306), size: 12, color: AppColors.water, weight: FontWeight.w700);
    } else {
      _text(canvas, 'FT1  ${fmt('FT1')}', const Offset(238, 268), size: 11, color: AppColors.water, weight: FontWeight.w700, align: TextAlign.left);
      _text(canvas, 'FT2  ${fmt('FT2')}', const Offset(238, 760), size: 11, color: AppColors.water, weight: FontWeight.w700, align: TextAlign.left);
      _text(canvas, 'FT3  ${fmt('FT3')}', const Offset(238, 1000), size: 11, color: AppColors.water, weight: FontWeight.w700, align: TextAlign.left);
    }
  }

  void _drawIntake(Canvas canvas) {
    final c = layout.intake;
    final available = state.conditions.sourceAvailable;
    final rect = layout.vertical ? Rect.fromCenter(center: c, width: 200, height: 60) : Rect.fromCenter(center: c, width: 84, height: 110);
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(10));
    canvas.drawRRect(
      rrect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: available
              ? [AppColors.water.withValues(alpha: 0.35), AppColors.waterDeep.withValues(alpha: 0.6)]
              : [AppColors.steelDark.withValues(alpha: 0.5), AppColors.steelDark],
        ).createShader(rect),
    );
    canvas.drawRRect(rrect, Paint()..color = _pipeEdge..style = PaintingStyle.stroke..strokeWidth = 2);

    // waves
    final wave = Paint()
      ..color = (available ? AppColors.water : AppColors.steel).withValues(alpha: 0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (var i = 0; i < 3; i++) {
      final y = rect.top + 18 + i * 14 + (layout.vertical ? 0 : 12);
      final path = Path();
      final shift = phase * 12 + i * 4;
      for (double x = rect.left + 8; x <= rect.right - 8; x += 2) {
        final yy = y + math.sin((x + shift) / 6) * 3;
        if (x == rect.left + 8) {
          path.moveTo(x, yy);
        } else {
          path.lineTo(x, yy);
        }
      }
      canvas.drawPath(path, wave);
    }
    final labelAt = layout.vertical ? Offset(rect.left - 8, c.dy) : Offset(c.dx, rect.bottom + 16);
    _text(
      canvas,
      available ? 'River intake' : 'Intake lost',
      labelAt,
      size: 11,
      color: available ? textColor.withValues(alpha: 0.75) : AppColors.danger,
      align: layout.vertical ? TextAlign.right : TextAlign.center,
      weight: available ? FontWeight.w500 : FontWeight.w700,
    );
    if (!available) {
      final p = Paint()
        ..color = AppColors.danger
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(c + const Offset(-14, -14), c + const Offset(14, 14), p);
      canvas.drawLine(c + const Offset(-14, 14), c + const Offset(14, -14), p);
    }
  }

  void _drawNetwork(Canvas canvas) {
    final c = layout.network;
    final pt3 = state.value('PT3') ?? 0;
    final demand = state.conditions.demandM3h;
    final rect = layout.vertical ? Rect.fromCenter(center: c, width: 200, height: 64) : Rect.fromCenter(center: c, width: 70, height: 70);
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(10));
    canvas.drawRRect(rrect, Paint()..color = AppColors.surfaceHigher);
    canvas.drawRRect(rrect, Paint()..color = _pipeEdge..style = PaintingStyle.stroke..strokeWidth = 2);

    // simple city icon: three buildings
    final b = Paint()..color = AppColors.primary.withValues(alpha: 0.8);
    final baseY = rect.bottom - 10;
    final cx = layout.vertical ? rect.left + 36 : c.dx;
    canvas.drawRect(Rect.fromLTWH(cx - 24, baseY - 26, 14, 26), b);
    canvas.drawRect(Rect.fromLTWH(cx - 7, baseY - 40, 14, 40), b);
    canvas.drawRect(Rect.fromLTWH(cx + 10, baseY - 20, 14, 20), b);

    if (layout.vertical) {
      _text(canvas, 'Distribution network', Offset(rect.left + 66, c.dy - 16), size: 11, align: TextAlign.left, color: textColor.withValues(alpha: 0.8));
      _text(canvas, 'PT3 ${fmtNum(pt3, decimals: 2)} bar', Offset(rect.left + 66, c.dy + 2), size: 12, weight: FontWeight.w700, align: TextAlign.left, color: pt3 < 2.5 ? AppColors.danger : AppColors.running);
      _text(canvas, 'Demand ${fmtNum(demand)} m³/h', Offset(rect.left + 66, c.dy + 18), size: 11, align: TextAlign.left, color: textColor.withValues(alpha: 0.7));
    } else {
      _text(canvas, 'Network', Offset(c.dx, rect.bottom + 14), size: 11, color: textColor.withValues(alpha: 0.8));
      _text(canvas, 'Demand ${fmtNum(demand)} m³/h', Offset(c.dx, rect.bottom + 30), size: 11, color: textColor.withValues(alpha: 0.7), maxWidth: 120);
      _text(canvas, 'PT3 ${fmtNum(pt3, decimals: 2)} bar', Offset(c.dx, rect.top - 16), size: 12, weight: FontWeight.w700, color: pt3 < 2.5 ? AppColors.danger : AppColors.running);
    }
  }

  void _drawTank(Canvas canvas, Rect rect, String tag, String levelTag) {
    final eq = byTag[tag];
    final tank = state.tank(tag);
    final level = (tank?.level ?? state.value(levelTag) ?? 0).clamp(0.0, 100.0);
    final faulted = state.isFaulted(levelTag);
    final selected = selectedTag == tag;
    const ry = 14.0;

    // body
    final body = Rect.fromLTRB(rect.left, rect.top + ry, rect.right, rect.bottom - ry);
    final bodyPaint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFF3A4660), Color(0xFF1C2538), Color(0xFF2A3650)],
        stops: [0, 0.55, 1],
      ).createShader(body);
    canvas.drawRect(body, bodyPaint);

    // water
    final waterTop = body.bottom - body.height * level / 100;
    final water = Rect.fromLTRB(body.left, waterTop, body.right, body.bottom);
    if (water.height > 0) {
      canvas.drawRect(
        water,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.water.withValues(alpha: 0.75), AppColors.waterDeep.withValues(alpha: 0.95)],
          ).createShader(water),
      );
      // surface ellipse (3D)
      canvas.drawOval(
        Rect.fromCenter(center: Offset(rect.center.dx, waterTop), width: rect.width, height: ry * 2),
        Paint()..color = AppColors.water.withValues(alpha: 0.9),
      );
      // ripple highlight
      canvas.drawOval(
        Rect.fromCenter(center: Offset(rect.center.dx - rect.width * 0.15, waterTop), width: rect.width * 0.35, height: ry * 0.7),
        Paint()..color = Colors.white.withValues(alpha: 0.18 + 0.08 * math.sin(phase * 2 * math.pi)),
      );
    }
    // bottom ellipse
    canvas.drawOval(
      Rect.fromCenter(center: Offset(rect.center.dx, body.bottom), width: rect.width, height: ry * 2),
      Paint()..color = (water.height > 0 ? AppColors.waterDeep : const Color(0xFF1C2538)),
    );
    // top rim
    canvas.drawOval(
      Rect.fromCenter(center: Offset(rect.center.dx, body.top), width: rect.width, height: ry * 2),
      Paint()..color = const Color(0xFF3B4A66).withValues(alpha: 0.9),
    );
    // outline
    final outline = Paint()
      ..color = selected ? AppColors.primary : _pipeEdge
      ..style = PaintingStyle.stroke
      ..strokeWidth = selected ? 3 : 2;
    canvas.drawLine(Offset(body.left, body.top), Offset(body.left, body.bottom), outline);
    canvas.drawLine(Offset(body.right, body.top), Offset(body.right, body.bottom), outline);
    canvas.drawOval(Rect.fromCenter(center: Offset(rect.center.dx, body.top), width: rect.width, height: ry * 2), outline);
    canvas.drawArc(Rect.fromCenter(center: Offset(rect.center.dx, body.bottom), width: rect.width, height: ry * 2), 0, math.pi, false, outline);

    // level marks
    if (eq != null) {
      final marks = {'HH': eq.params['hh'], 'H': eq.params['h'], 'L': eq.params['l'], 'LL': eq.params['ll']};
      marks.forEach((label, raw) {
        final v = (raw is num) ? raw.toDouble() : double.tryParse('$raw');
        if (v == null) return;
        final y = body.bottom - body.height * v / 100;
        final color = label.startsWith('H') ? AppColors.warning : AppColors.danger;
        canvas.drawLine(Offset(body.right, y), Offset(body.right + 8, y), Paint()..color = color.withValues(alpha: 0.9)..strokeWidth = 1.5);
        _text(canvas, label, Offset(body.right + 12, y), size: 9, color: color.withValues(alpha: 0.9), align: TextAlign.left);
      });
    }

    // text
    final nameY = rect.top - 14;
    _text(canvas, '$tag · ${eq?.name ?? ''}', Offset(rect.center.dx, nameY), size: 12, weight: FontWeight.w600, maxWidth: rect.width + 80);
    _text(canvas, '${fmtNum(level)} %', Offset(rect.center.dx, rect.center.dy - 6), size: 20, weight: FontWeight.w800, color: faulted ? AppColors.warning : Colors.white);
    if (tank != null) {
      _text(canvas, '${fmtNum(tank.volume, decimals: 0)} / ${fmtNum(tank.capacity, decimals: 0)} m³', Offset(rect.center.dx, rect.center.dy + 14), size: 10, color: Colors.white.withValues(alpha: 0.85));
    }
    if (faulted) {
      _text(canvas, '$levelTag FAULT', Offset(rect.center.dx, rect.center.dy + 30), size: 10, weight: FontWeight.w700, color: AppColors.warning);
    }
    if (eq != null && eq.underMaintenance) {
      _text(canvas, 'MAINTENANCE', Offset(rect.center.dx, rect.bottom + 14), size: 10, weight: FontWeight.w700, color: AppColors.maintenance);
    }
  }

  void _drawTreatment(Canvas canvas) {
    final rect = layout.treatment;
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(10));
    canvas.drawRRect(rrect, Paint()..color = AppColors.surfaceHigher);
    canvas.drawRRect(rrect, Paint()..color = _pipeEdge..style = PaintingStyle.stroke..strokeWidth = 2);
    final tu = state.value('TU1');
    final cl = state.value('CL1');
    final x = rect.center.dx;
    _text(canvas, 'Filtration + Cl₂', Offset(x, rect.top + 14), size: 11, weight: FontWeight.w600, maxWidth: rect.width - 4);
    _text(canvas, 'TU1 ${fmtNum(tu, decimals: 2)} NTU', Offset(x, rect.top + 36), size: 11, color: (tu ?? 0) > 1 ? AppColors.warning : AppColors.running, weight: FontWeight.w600, maxWidth: rect.width - 4);
    _text(canvas, 'CL1 ${fmtNum(cl, decimals: 2)} mg/L', Offset(x, rect.top + 56), size: 11, color: AppColors.running, weight: FontWeight.w600, maxWidth: rect.width - 4);
  }

  void _drawValve(Canvas canvas, Offset c, String tag) {
    final eq = byTag[tag];
    final position = eq?.position ?? 0;
    final selected = selectedTag == tag;
    final Color color;
    if (eq == null) {
      color = AppColors.steel;
    } else if (eq.underMaintenance) {
      color = AppColors.maintenance;
    } else if (position >= 99.5) {
      color = AppColors.running;
    } else if (position <= 0.5) {
      color = AppColors.steel;
    } else {
      color = AppColors.warning;
    }
    const r = 15.0;
    final body = Paint()..color = color;
    final edge = Paint()
      ..color = selected ? AppColors.primary : Colors.black.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = selected ? 2.5 : 1.5;

    canvas.save();
    canvas.translate(c.dx, c.dy);
    if (layout.vertical) canvas.rotate(math.pi / 2);
    final left = Path()
      ..moveTo(-r, -r * 0.8)
      ..lineTo(0, 0)
      ..lineTo(-r, r * 0.8)
      ..close();
    final right = Path()
      ..moveTo(r, -r * 0.8)
      ..lineTo(0, 0)
      ..lineTo(r, r * 0.8)
      ..close();
    canvas.drawPath(left, body);
    canvas.drawPath(right, body);
    canvas.drawPath(left, edge);
    canvas.drawPath(right, edge);
    // actuator
    canvas.drawLine(Offset.zero, const Offset(0, -r - 6), Paint()..color = color..strokeWidth = 3);
    canvas.drawRect(Rect.fromCenter(center: const Offset(0, -r - 11), width: 16, height: 10), Paint()..color = color.withValues(alpha: 0.9));
    canvas.restore();

    final labelAt = layout.vertical ? Offset(c.dx + 30, c.dy) : Offset(c.dx, c.dy + 34);
    final align = layout.vertical ? TextAlign.left : TextAlign.center;
    final stateText = eq == null
        ? ''
        : eq.underMaintenance
            ? 'MAINT'
            : position >= 99.5
                ? 'OPEN'
                : position <= 0.5
                    ? 'CLOSED'
                    : '${position.round()} %';
    _text(canvas, layout.vertical ? '$tag  $stateText' : tag, labelAt, size: 11, weight: FontWeight.w700, align: align);
    if (!layout.vertical) {
      _text(canvas, stateText, Offset(c.dx, c.dy + 48), size: 10, color: color, weight: FontWeight.w600);
    }
    if (eq != null && eq.mode == EquipmentMode.manual) {
      final at = layout.vertical ? Offset(c.dx - 30, c.dy) : Offset(c.dx, c.dy - 36);
      _text(canvas, 'MAN', at, size: 9, color: AppColors.warning, weight: FontWeight.w700, align: layout.vertical ? TextAlign.right : TextAlign.center);
    }
  }

  void _drawPump(Canvas canvas, Offset c, String tag, String pressureTag) {
    final eq = byTag[tag];
    final selected = selectedTag == tag;
    const r = 24.0;
    final Color color;
    if (eq == null) {
      color = AppColors.steel;
    } else if (eq.underMaintenance) {
      color = AppColors.maintenance;
    } else if (eq.isTripped) {
      color = AppColors.critical;
    } else if (eq.isRunning) {
      color = AppColors.running;
    } else if (eq.isTransitioning) {
      color = AppColors.warning;
    } else {
      color = AppColors.steel;
    }

    // glow when running
    if (eq != null && eq.isActive) {
      canvas.drawCircle(c, r + 6, Paint()..color = color.withValues(alpha: 0.18));
    }
    // sphere body
    final rect = Rect.fromCircle(center: c, radius: r);
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.4, -0.5),
          radius: 0.9,
          colors: [Color.lerp(color, Colors.white, 0.35)!, color, Color.lerp(color, Colors.black, 0.45)!],
          stops: const [0, 0.5, 1],
        ).createShader(rect),
    );
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..color = selected ? AppColors.primary : Colors.black.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = selected ? 3 : 1.5,
    );

    // impeller
    final speed = (eq?.position ?? 0) / 100;
    final angle = (eq != null && eq.isActive) ? phase * 2 * math.pi * (1 + speed * 2) : 0.0;
    final blade = Paint()
      ..color = Colors.black.withValues(alpha: 0.45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 3; i++) {
      final a = angle + i * 2 * math.pi / 3;
      final p1 = c + Offset(math.cos(a), math.sin(a)) * 5;
      final p2 = c + Offset(math.cos(a + 0.6), math.sin(a + 0.6)) * (r - 6);
      canvas.drawLine(p1, p2, blade);
    }
    canvas.drawCircle(c, 4, Paint()..color = Colors.black.withValues(alpha: 0.55));

    // maintenance hatch
    if (eq != null && eq.underMaintenance) {
      canvas.save();
      canvas.clipPath(Path()..addOval(rect));
      final hatch = Paint()
        ..color = Colors.black.withValues(alpha: 0.35)
        ..strokeWidth = 3;
      for (double d = -r * 2; d < r * 2; d += 9) {
        canvas.drawLine(c + Offset(d, -r), c + Offset(d + r * 2, r), hatch);
      }
      canvas.restore();
    }
    // fault badge
    if (eq != null && (eq.isTripped || eq.interlock != null)) {
      final badgeC = c + const Offset(r - 4, -r + 4);
      canvas.drawCircle(badgeC, 8, Paint()..color = eq.isTripped ? AppColors.critical : AppColors.warning);
      _text(canvas, '!', badgeC, size: 11, weight: FontWeight.w900, color: Colors.black);
    }

    // labels
    final stateText = eq == null
        ? ''
        : eq.underMaintenance
            ? 'MAINTENANCE'
            : eq.actualState.toUpperCase();
    final pressure = state.value(pressureTag);
    if (layout.vertical) {
      _text(canvas, tag, Offset(c.dx + 36, c.dy - 10), size: 12, weight: FontWeight.w800, align: TextAlign.left);
      _text(canvas, stateText, Offset(c.dx + 36, c.dy + 6), size: 10, color: color, weight: FontWeight.w700, align: TextAlign.left);
      _text(canvas, '$pressureTag ${fmtNum(pressure, decimals: 2)} bar', Offset(c.dx - 36, c.dy - 10), size: 10, align: TextAlign.right, color: textColor.withValues(alpha: 0.8));
      _text(canvas, eq?.mode == EquipmentMode.manual ? 'MANUAL' : 'AUTO', Offset(c.dx - 36, c.dy + 6), size: 9, align: TextAlign.right, color: eq?.mode == EquipmentMode.manual ? AppColors.warning : textColor.withValues(alpha: 0.6), weight: FontWeight.w700);
    } else {
      _text(canvas, tag, Offset(c.dx, c.dy + r + 12), size: 12, weight: FontWeight.w800);
      _text(canvas, stateText, Offset(c.dx, c.dy + r + 26), size: 10, color: color, weight: FontWeight.w700, maxWidth: 90);
      _text(canvas, eq?.mode == EquipmentMode.manual ? 'MANUAL' : 'AUTO', Offset(c.dx, c.dy + r + 39), size: 9, color: eq?.mode == EquipmentMode.manual ? AppColors.warning : textColor.withValues(alpha: 0.6), weight: FontWeight.w700);
      _text(canvas, '$pressureTag ${fmtNum(pressure, decimals: 2)} bar', Offset(c.dx, c.dy - r - 14), size: 10, color: textColor.withValues(alpha: 0.8));
    }
  }

  @override
  bool shouldRepaint(covariant _SchematicPainter oldDelegate) => true;
}
