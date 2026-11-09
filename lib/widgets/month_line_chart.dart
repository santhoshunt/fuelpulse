import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../theme/app_colors.dart';

/// One point per month as a line with a filled area, for ranges too long
/// for a bar a month. Touch or drag along it to read a month in a bubble,
/// the same way as [TrendChart]; the reading stays until the next touch.
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

  void _clear() {
    if (_picked != null) setState(() => _picked = null);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final pts = widget.points;
    if (pts.isEmpty) return const SizedBox.shrink();
    return TapRegion(
      // A touch anywhere else puts the reading away.
      onTapOutside: (_) => _clear(),
      child: LayoutBuilder(
      builder: (context, box) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (d) => _pick(d.localPosition.dx, box.maxWidth),
        onHorizontalDragStart: (d) => _pick(d.localPosition.dx, box.maxWidth),
        onHorizontalDragUpdate: (d) => _pick(d.localPosition.dx, box.maxWidth),
        child: SizedBox(
          height: 170,
          width: box.maxWidth,
          child: CustomPaint(
            painter: _ChartPainter(
              values: [for (final p in pts) p.$2],
              months: [for (final p in pts) p.$1],
              picked: _picked,
              formatValue: widget.formatValue,
              line: colors.secondary,
              marker: colors.textSecondary,
              bubble: colors.textPrimary,
              bubbleText: colors.card,
              label: colors.textSecondary,
              axis: colors.cardBorder,
            ),
          ),
        ),
      ),
    ),
    );
  }
}

class _ChartPainter extends CustomPainter {
  static const pad = 8.0;
  final List<double> values;
  final List<DateTime> months;
  final int? picked;
  final String Function(double) formatValue;
  final Color line, marker, bubble, bubbleText, label, axis;

  _ChartPainter({
    required this.values,
    required this.months,
    required this.picked,
    required this.formatValue,
    required this.line,
    required this.marker,
    required this.bubble,
    required this.bubbleText,
    required this.label,
    required this.axis,
  });

  TextPainter _text(String s, Color c, double size, FontWeight w) => TextPainter(
        text: TextSpan(
            text: s, style: TextStyle(color: c, fontSize: size, fontWeight: w)),
        textDirection: TextDirection.ltr,
      )..layout();

  @override
  void paint(Canvas canvas, Size size) {
    const labelH = 16.0, topRoom = 20.0;
    final plotBottom = size.height - labelH;
    final top = values.reduce(math.max);
    final n = values.length;
    double x(int i) =>
        n < 2 ? size.width / 2 : pad + (size.width - 2 * pad) * i / (n - 1);
    double y(double v) => top <= 0
        ? plotBottom
        : plotBottom - (plotBottom - topRoom) * v / top;

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

    // A label under each January, plus the first month, skipping any that
    // would touch the one before.
    var lastRight = -1.0;
    for (var i = 0; i < n; i++) {
      if (i != 0 && months[i].month != 1) continue;
      final tp = _text(
          i == 0 && months[i].month != 1
              ? DateFormat('MMM yy').format(months[i])
              : '${months[i].year}',
          label,
          11,
          FontWeight.w400);
      final left = (x(i) - tp.width / 2).clamp(0.0, size.width - tp.width);
      if (left < lastRight + 6) continue;
      tp.paint(canvas, Offset(left, plotBottom + 3));
      lastRight = left + tp.width;
    }

    final p = picked;
    if (p == null || p >= n) return;
    final at = Offset(x(p), y(values[p]));
    final dash = Paint()
      ..color = marker
      ..strokeWidth = 1;
    for (var yy = 2.0; yy < plotBottom; yy += 6) {
      canvas.drawLine(
          Offset(at.dx, yy), Offset(at.dx, math.min(yy + 3, plotBottom)), dash);
    }
    canvas.drawCircle(at, 5, Paint()..color = line);
    canvas.drawCircle(at, 2.5, Paint()..color = bubbleText);
    final date =
        _text(DateFormat('MMM y').format(months[p]), bubbleText, 10, FontWeight.w400);
    final value = _text(formatValue(values[p]), bubbleText, 12, FontWeight.w700);
    final w = math.max(date.width, value.width) + 16;
    final h = date.height + value.height + 10;
    final left = (at.dx - w / 2).clamp(0.0, size.width - w);
    final topY = at.dy - 10 - h >= 0 ? at.dy - 10 - h : at.dy + 10;
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(left, topY, w, h), const Radius.circular(8)),
        Paint()..color = bubble);
    date.paint(canvas, Offset(left + (w - date.width) / 2, topY + 5));
    value.paint(
        canvas, Offset(left + (w - value.width) / 2, topY + 5 + date.height));
  }

  @override
  bool shouldRepaint(_ChartPainter old) =>
      old.picked != picked || old.values != values || old.line != line;
}
