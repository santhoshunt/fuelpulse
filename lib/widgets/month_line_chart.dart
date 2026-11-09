import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../theme/app_colors.dart';

/// One point per month as a line with a filled area, for ranges too long
/// for a bar a month. Drag or tap along it to read a month; it starts on
/// the latest one.
class MonthLineChart extends StatefulWidget {
  final List<(DateTime month, double value)> points;
  final String Function(double) formatValue;

  const MonthLineChart({
    super.key,
    required this.points,
    required this.formatValue,
  });

  @override
  State<MonthLineChart> createState() => _MonthLineChartState();
}

class _MonthLineChartState extends State<MonthLineChart> {
  int? _picked;

  int get _index => (_picked ?? widget.points.length - 1)
      .clamp(0, math.max(0, widget.points.length - 1));

  @override
  void didUpdateWidget(MonthLineChart old) {
    super.didUpdateWidget(old);
    if (old.points.length != widget.points.length) _picked = null;
  }

  void _pick(double dx, double width) {
    final n = widget.points.length;
    if (n < 2) return;
    final i = ((dx - _ChartPainter.pad) / (width - 2 * _ChartPainter.pad) * (n - 1))
        .round()
        .clamp(0, n - 1);
    if (i != _picked) setState(() => _picked = i);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final pts = widget.points;
    if (pts.isEmpty) return const SizedBox.shrink();
    final (month, value) = pts[_index];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text.rich(
          TextSpan(
            text: '${DateFormat('MMM y').format(month)} · ',
            style: TextStyle(color: colors.textSecondary, fontSize: 13),
            children: [
              TextSpan(
                  text: widget.formatValue(value),
                  style: TextStyle(
                      color: colors.textPrimary, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
        const SizedBox(height: 6),
        LayoutBuilder(
          builder: (context, box) => GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) => _pick(d.localPosition.dx, box.maxWidth),
            onHorizontalDragUpdate: (d) =>
                _pick(d.localPosition.dx, box.maxWidth),
            child: SizedBox(
              height: 150,
              width: box.maxWidth,
              child: CustomPaint(
                painter: _ChartPainter(
                  values: [for (final p in pts) p.$2],
                  months: [for (final p in pts) p.$1],
                  picked: _index,
                  line: colors.secondary,
                  marker: colors.textSecondary,
                  dot: colors.card,
                  label: colors.textSecondary,
                  axis: colors.cardBorder,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ChartPainter extends CustomPainter {
  static const pad = 8.0;
  final List<double> values;
  final List<DateTime> months;
  final int picked;
  final Color line, marker, dot, label, axis;

  _ChartPainter({
    required this.values,
    required this.months,
    required this.picked,
    required this.line,
    required this.marker,
    required this.dot,
    required this.label,
    required this.axis,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const labelH = 16.0;
    final plotBottom = size.height - labelH;
    final top = values.reduce(math.max);
    final n = values.length;
    double x(int i) =>
        n < 2 ? size.width / 2 : pad + (size.width - 2 * pad) * i / (n - 1);
    double y(double v) =>
        top <= 0 ? plotBottom : plotBottom - (plotBottom - 6) * v / top;

    canvas.drawLine(Offset(0, plotBottom), Offset(size.width, plotBottom),
        Paint()..color = axis);

    final path = Path()..moveTo(x(0), y(values[0]));
    for (var i = 1; i < n; i++) {
      path.lineTo(x(i), y(values[i]));
    }
    final area = Path.from(path)
      ..lineTo(x(n - 1), plotBottom)
      ..lineTo(x(0), plotBottom)
      ..close();
    canvas.drawPath(area, Paint()..color = line.withValues(alpha: 0.15));
    canvas.drawPath(
        path,
        Paint()
          ..color = line
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeJoin = StrokeJoin.round);

    final px = x(picked);
    final dash = Paint()
      ..color = marker
      ..strokeWidth = 1;
    for (var yy = 2.0; yy < plotBottom; yy += 6) {
      canvas.drawLine(Offset(px, yy), Offset(px, math.min(yy + 3, plotBottom)), dash);
    }
    canvas.drawCircle(Offset(px, y(values[picked])), 5, Paint()..color = line);
    canvas.drawCircle(Offset(px, y(values[picked])), 2.5, Paint()..color = dot);

    // A label under each January, plus the first month, skipping any that
    // would touch the one before.
    var lastRight = -1.0;
    for (var i = 0; i < n; i++) {
      if (i != 0 && months[i].month != 1) continue;
      final tp = TextPainter(
        text: TextSpan(
            text: i == 0 && months[i].month != 1
                ? DateFormat('MMM yy').format(months[i])
                : '${months[i].year}',
            style: TextStyle(color: label, fontSize: 11)),
        textDirection: TextDirection.ltr,
      )..layout();
      final left = (x(i) - tp.width / 2).clamp(0.0, size.width - tp.width);
      if (left < lastRight + 6) continue;
      tp.paint(canvas, Offset(left, plotBottom + 3));
      lastRight = left + tp.width;
    }
  }

  @override
  bool shouldRepaint(_ChartPainter old) =>
      old.picked != picked || old.values != values || old.line != line;
}
