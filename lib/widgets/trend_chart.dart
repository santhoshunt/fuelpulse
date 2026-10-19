import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import '../utils/constants.dart';
import 'glossy_card.dart';

/// Month axis labels for a chart running from [first] to [last]: "Jun", or
/// "Jun '26" once the range crosses a year boundary, where a bare "Jan"
/// would be ambiguous.
@visibleForTesting
DateFormat monthLabelFormat(DateTime first, DateTime last) =>
    first.year == last.year ? DateFormat('MMM') : DateFormat("MMM ''yy");

/// One value at one moment on a [TrendChart].
class TrendPoint {
  final DateTime x;
  final double y;
  const TrendPoint(this.x, this.y);
}

/// Line chart of a value over time inside a glossy card. Paint-only, like the
/// rest of the app's cards: no chart package.
class TrendChart extends StatelessWidget {
  final String title;

  /// Oldest first.
  final List<TrendPoint> points;

  /// Formats axis and average labels.
  final String Function(double) formatValue;

  /// Shown instead of the chart when there are fewer than 2 points.
  final String emptyMessage;

  const TrendChart({
    super.key,
    required this.title,
    required this.points,
    required this.formatValue,
    required this.emptyMessage,
  });

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    // Shown beside the title rather than inside the plot, where it could sit
    // on top of a data point.
    final mean = points.length < 2
        ? null
        : points.map((p) => p.y).reduce((a, b) => a + b) / points.length;

    return GlossyCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: kTextPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (mean != null)
                Text(
                  'avg ${formatValue(mean)}',
                  style: const TextStyle(color: kTextSecondary, fontSize: 12),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (points.length < 2)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                emptyMessage,
                style: const TextStyle(color: kTextMuted, fontSize: 13),
              ),
            )
          else
            SizedBox(
              height: 160,
              width: double.infinity,
              child: CustomPaint(
                painter: _TrendChartPainter(
                  // Logs sort by timestamp string, which can disagree with
                  // parse order after a CSV import with mixed formats.
                  points: [...points]..sort((a, b) => a.x.compareTo(b.x)),
                  color: accent,
                  formatValue: formatValue,
                  // TextPainter does not inherit DefaultTextStyle, so hand it
                  // the theme's font explicitly.
                  labelStyle: Theme.of(context).textTheme.bodySmall ??
                      const TextStyle(),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TrendChartPainter extends CustomPainter {
  final List<TrendPoint> points;
  final Color color;
  final String Function(double) formatValue;
  final TextStyle labelStyle;

  static const double _leftGutter = 40;
  static const double _bottomStrip = 18;
  static const double _topPad = 6;
  static const double _rightPad = 6;

  _TrendChartPainter({
    required this.points,
    required this.color,
    required this.formatValue,
    required this.labelStyle,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final plot = Rect.fromLTRB(_leftGutter, _topPad, size.width - _rightPad,
        size.height - _bottomStrip);

    // ── Y range, padded so the line never touches the edges ──
    final ys = points.map((p) => p.y).toList();
    final minY = ys.reduce((a, b) => a < b ? a : b);
    final maxY = ys.reduce((a, b) => a > b ? a : b);
    final span = maxY - minY;
    final pad = span > 0
        ? span * 0.1
        : (minY.abs() * 0.1 < 1 ? 1.0 : minY.abs() * 0.1);
    final lo = minY - pad;
    final hi = maxY + pad;
    double yPx(double v) => plot.bottom - (v - lo) / (hi - lo) * plot.height;

    // ── X positions, proportional to time ──
    final firstMs = points.first.x.millisecondsSinceEpoch;
    final lastMs = points.last.x.millisecondsSinceEpoch;
    final spanMs = lastMs - firstMs;
    double timePx(DateTime t) => spanMs > 0
        ? plot.left + (t.millisecondsSinceEpoch - firstMs) / spanMs * plot.width
        : plot.left;
    // Same-day points would stack on one x; spread them by index instead.
    double pointPx(int i) => spanMs > 0
        ? timePx(points[i].x)
        : plot.left + i / (points.length - 1) * plot.width;

    // ── Grid lines with value labels ──
    final gridPaint = Paint()
      ..color = kTextMuted.withValues(alpha: 0.35)
      ..strokeWidth = 1;
    final gridValues = span > 0 ? [minY, (minY + maxY) / 2, maxY] : [minY];
    for (final v in gridValues) {
      final y = yPx(v);
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), gridPaint);
      final tp = _text(formatValue(v), kTextMuted);
      tp.paint(canvas, Offset(_leftGutter - 6 - tp.width, y - tp.height / 2));
    }

    // ── Month labels along the bottom ──
    final first = points.first.x;
    final last = points.last.x;
    final monthFormat = monthLabelFormat(first, last);
    final ticks = <(double, String)>[];
    var month = DateTime(first.year, first.month);
    while (!month.isAfter(last)) {
      final at = month.isBefore(first) ? first : month;
      ticks.add((timePx(at), monthFormat.format(month)));
      month = DateTime(month.year, month.month + 1);
    }
    final step = (ticks.length / 4).ceil();
    double lastRight = double.negativeInfinity;
    for (int i = 0; i < ticks.length; i += step) {
      final tp = _text(ticks[i].$2, kTextMuted);
      final left = (ticks[i].$1 - tp.width / 2)
          .clamp(plot.left, size.width - tp.width);
      // Skip a label that would collide with the one before it.
      if (left < lastRight + 8) continue;
      tp.paint(canvas, Offset(left, plot.bottom + 4));
      lastRight = left + tp.width;
    }

    // ── Dashed average line (its value is labelled in the title row) ──
    final mean = ys.reduce((a, b) => a + b) / ys.length;
    final meanY = yPx(mean);
    final dashPaint = Paint()
      ..color = kTextSecondary.withValues(alpha: 0.5)
      ..strokeWidth = 1;
    for (double x = plot.left; x < plot.right; x += 8) {
      final end = (x + 4).clamp(plot.left, plot.right);
      canvas.drawLine(Offset(x, meanY), Offset(end, meanY), dashPaint);
    }

    // ── Data line and dots ──
    final path = Path();
    for (int i = 0; i < points.length; i++) {
      final o = Offset(pointPx(i), yPx(points[i].y));
      if (i == 0) {
        path.moveTo(o.dx, o.dy);
      } else {
        path.lineTo(o.dx, o.dy);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round,
    );
    final dotPaint = Paint()..color = color;
    for (int i = 0; i < points.length; i++) {
      canvas.drawCircle(Offset(pointPx(i), yPx(points[i].y)), 3, dotPaint);
    }
  }

  TextPainter _text(String s, Color c) => TextPainter(
        text: TextSpan(
            text: s, style: labelStyle.copyWith(color: c, fontSize: 10)),
        textDirection: TextDirection.ltr,
      )..layout();

  @override
  bool shouldRepaint(_TrendChartPainter old) =>
      old.points != points || old.color != color;
}
