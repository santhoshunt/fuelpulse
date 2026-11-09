import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show NumberFormat;

import '../theme/app_colors.dart';
import '../utils/mileage_bands.dart' show bandColor;

final _grouped = NumberFormat('#,##,##0', 'en_IN');

/// A trip drawn as a line by odometer: green start, red end, a dot at each
/// fill-up made on it. Not a map: the app has no GPS.
class TripStrip extends StatelessWidget {
  final int startKm;
  final int endKm;
  final List<int> fillUpKms;

  /// Colours for drawing on a dark card (the shared trip image); the
  /// theme's when null.
  final Color? lineColor, fillColor, startColor, endColor, labelColor;

  const TripStrip({
    super.key,
    required this.startKm,
    required this.endKm,
    required this.fillUpKms,
    this.lineColor,
    this.fillColor,
    this.startColor,
    this.endColor,
    this.labelColor,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final b = Theme.of(context).brightness;
    return SizedBox(
      height: 64,
      child: CustomPaint(
        size: Size.infinite,
        painter: _StripPainter(
          startKm: startKm,
          endKm: endKm,
          fillUpKms: fillUpKms,
          line: lineColor ?? colors.secondary,
          fill: fillColor ?? colors.primary,
          start: startColor ?? bandColor(4, b),
          end: endColor ?? colors.danger,
          label: labelColor ?? colors.textSecondary,
        ),
      ),
    );
  }
}

class _StripPainter extends CustomPainter {
  final int startKm, endKm;
  final List<int> fillUpKms;
  final Color line, fill, start, end, label;

  _StripPainter({
    required this.startKm,
    required this.endKm,
    required this.fillUpKms,
    required this.line,
    required this.fill,
    required this.start,
    required this.end,
    required this.label,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const pad = 10.0, y = 22.0;
    final span = (endKm - startKm).clamp(1, 1 << 30).toDouble();
    double x(int km) =>
        pad + (size.width - 2 * pad) * ((km - startKm) / span).clamp(0.0, 1.0);
    canvas.drawLine(
        Offset(x(startKm), y),
        Offset(x(endKm), y),
        Paint()
          ..color = line
          ..strokeWidth = 5
          ..strokeCap = StrokeCap.round);
    for (final km in fillUpKms) {
      canvas.drawCircle(Offset(x(km), y), 7, Paint()..color = fill);
    }
    canvas.drawCircle(Offset(x(startKm), y), 6, Paint()..color = start);
    canvas.drawCircle(Offset(x(endKm), y), 6, Paint()..color = end);

    void text(String s, double cx, TextAlign align) {
      final tp = TextPainter(
        text: TextSpan(text: s, style: TextStyle(color: label, fontSize: 11)),
        textDirection: TextDirection.ltr,
      )..layout();
      final left = switch (align) {
        TextAlign.left => cx - pad,
        TextAlign.right => cx - tp.width + pad,
        _ => cx - tp.width / 2,
      };
      tp.paint(canvas,
          Offset(left.clamp(0.0, size.width - tp.width), y + 14));
    }

    text(_grouped.format(startKm), x(startKm), TextAlign.left);
    text(_grouped.format(endKm), x(endKm), TextAlign.right);
    // Middle labels only where they don't crowd the ends.
    for (final km in fillUpKms) {
      final cx = x(km);
      if (cx - x(startKm) > 48 && x(endKm) - cx > 48) {
        text(_grouped.format(km), cx, TextAlign.center);
      }
    }
  }

  @override
  bool shouldRepaint(_StripPainter old) =>
      old.startKm != startKm ||
      old.endKm != endKm ||
      old.fillUpKms != fillUpKms ||
      old.line != line;
}
