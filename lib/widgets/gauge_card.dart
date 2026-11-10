import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'lcd_odometer.dart';

/// The Dashboard's headline card: a speedometer-style gauge with the needle
/// on the average km/L, the odometer inside the dial, fuel left after the
/// last refill, and worst, last and best km/L along the bottom.
class GaugeCard extends StatelessWidget {
  final double? averageKmL;
  final double? worst;
  final double? last;
  final double? best;
  final int? odometerKm;
  final int? odometerTenths;
  final double? tankLitres;
  final double? tankCapacity;

  /// What [tankLitres] is ("Left now, about", "In the tank after the 16 Oct
  /// refill") and the line under the bar.
  final String? tankCaption;
  final String? tankNote;

  /// Shows an "Update reading" link under the tank.
  final VoidCallback? onUpdateReading;

  /// Shown under the dial in place of the numbers when there are no logs.
  final String? emptyMessage;

  /// A fixed From and To from Settings; null fits the scale to the values.
  final (double, double)? scale;

  /// Tapping the odometer in the dial, to see its readings.
  final VoidCallback? onOdometerTap;

  const GaugeCard({
    super.key,
    required this.averageKmL,
    this.worst,
    this.last,
    this.best,
    required this.odometerKm,
    this.odometerTenths,
    this.tankLitres,
    this.tankCapacity,
    this.tankCaption,
    this.tankNote,
    this.onUpdateReading,
    this.emptyMessage,
    this.scale,
    this.onOdometerTap,
  });

  /// Scale ends: 25 km/L wide on multiples of 5, centred on [centre] (the
  /// average), then widened in steps of 5 until every value fits.
  static (double, double) scaleFor(double? centre, List<double> values) {
    if (values.isEmpty) return (0, 25);
    final mid = centre ?? values.reduce((a, b) => a + b) / values.length;
    final low = values.reduce(math.min);
    final high = values.reduce(math.max);
    var lo = math.max(0.0, ((mid - 12.5) / 5).floor() * 5.0);
    while (lo > 0 && lo > low - 1) {
      lo -= 5;
    }
    var hi = lo + 25;
    while (hi < high + 1) {
      hi += 5;
    }
    return (lo, hi);
  }
  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final values = [averageKmL, worst, best, last].whereType<double>().toList();
    final (lo, hi) = scale ?? scaleFor(averageKmL, values);
    final arc = Color.lerp(colors.primary, Colors.white, 0.55)!;
    const ink = AppColors.gaugeInk;
    const soft = AppColors.gaugeInkSoft;
    final divider = Colors.white.withValues(alpha: 0.18);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          stops: const [0, 0.55, 1],
          colors: [
            colors.gaugeStart,
            Color.lerp(colors.gaugeStart, colors.gaugeEnd, 0.6)!,
            colors.gaugeEnd,
          ],
        ),
      ),
      child: DefaultTextStyle.merge(
        style: const TextStyle(color: ink),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LayoutBuilder(builder: (context, box) {
              final w = math.min(box.maxWidth, 340.0);
              final scale = w / 300;
              return Center(
                child: SizedBox(
                  width: w,
                  height: 235 * scale,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: CustomPaint(
                          painter: _GaugePainter(
                            lo: lo,
                            hi: hi,
                            value: averageKmL,
                            arc: arc,
                            labelStyle:
                                Theme.of(context).textTheme.bodySmall ??
                                    const TextStyle(),
                          ),
                        ),
                      ),
                      if (odometerKm != null)
                        Positioned(
                          top: 170 * scale,
                          left: 0,
                          right: 0,
                          child: Center(
                            child: GestureDetector(
                              onTap: onOdometerTap,
                              child: LcdOdometer(
                                  value: odometerKm!, tenths: odometerTenths),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            }),
            Text(
              averageKmL == null ? '—' : averageKmL!.toStringAsFixed(1),
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 48,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -1.5,
                  height: 1),
            ),
            const SizedBox(height: 4),
            const Text('KM/L AVERAGE',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, letterSpacing: 2, color: soft)),
            if (emptyMessage != null) ...[
              const SizedBox(height: 12),
              Text(emptyMessage!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 14, color: soft)),
            ],
            if (tankLitres != null && (tankCapacity ?? 0) > 0) ...[
              const SizedBox(height: 14),
              _tank(colors, soft),
            ],
            if (emptyMessage == null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.only(top: 12),
                decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: divider))),
                child: IntrinsicHeight(
                  child: Row(
                    children: [
                      _figure('WORST', worst, soft),
                      VerticalDivider(width: 1, color: divider),
                      _figure('LAST REFILL', last, soft),
                      VerticalDivider(width: 1, color: divider),
                      _figure('BEST', best, soft),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _tank(AppColors colors, Color soft) {
    final cap = tankCapacity!;
    final level = tankLitres!.clamp(0, cap).toDouble();
    final small = TextStyle(fontSize: 12, color: soft);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
                child: Text(tankCaption ?? 'In the tank after the last refill',
                    style: small)),
            Text('${level.toStringAsFixed(1)} of ${_trim(cap)} L', style: small),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: cap > 0 ? level / cap : 0,
            minHeight: 6,
            color: colors.secondary,
            backgroundColor: Colors.white.withValues(alpha: 0.18),
          ),
        ),
        if (tankNote != null) ...[
          const SizedBox(height: 6),
          Text(tankNote!, style: small),
        ],
        if (onUpdateReading != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: onUpdateReading,
              style: TextButton.styleFrom(
                  foregroundColor: AppColors.gaugeInk,
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact),
              child: const Text('Update odometer reading',
                  style: TextStyle(
                      decoration: TextDecoration.underline, fontSize: 13)),
            ),
          ),
      ],
    );
  }
  static String _trim(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  Widget _figure(String label, double? v, Color soft) {
    return Expanded(
      child: Column(
        children: [
          Text(label,
              style: TextStyle(fontSize: 11, letterSpacing: 1.2, color: soft)),
          const SizedBox(height: 2),
          Text.rich(
            TextSpan(
              text: v == null ? '—' : v.toStringAsFixed(1),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
              children: [
                if (v != null)
                  TextSpan(
                      text: ' km/L',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                          color: soft)),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  final double lo;
  final double hi;
  final double? value;
  final Color arc;
  final TextStyle labelStyle;

  _GaugePainter({
    required this.lo,
    required this.hi,
    required this.value,
    required this.arc,
    required this.labelStyle,
  });

  // The dial runs clockwise from bottom left (150°) to bottom right (30°).
  static const _start = 150 * math.pi / 180;
  static const _sweep = 240 * math.pi / 180;

  double _angle(double v) =>
      _start + _sweep * ((v - lo) / (hi - lo)).clamp(0.0, 1.0);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 300, size.height / 235);
    const c = Offset(150, 150);
    const r = 120.0;
    final ring = Rect.fromCircle(center: c, radius: r);
    Offset at(double a, double radius) =>
        c + Offset(math.cos(a), math.sin(a)) * radius;

    canvas.drawArc(
        ring,
        _start,
        _sweep,
        false,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.18)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 10
          ..strokeCap = StrokeCap.round);
    final v = value;
    if (v != null && v > lo) {
      canvas.drawArc(
          ring,
          _start,
          _angle(v) - _start,
          false,
          Paint()
            ..color = arc
            ..style = PaintingStyle.stroke
            ..strokeWidth = 10
            ..strokeCap = StrokeCap.round);
    }

    final major = Paint()
      ..color = AppColors.gaugeInk
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    final minor = Paint()
      ..color = AppColors.gaugeMinorTick
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i <= 10; i++) {
      final a = _start + _sweep * i / 10;
      if (i.isEven) {
        canvas.drawLine(at(a, 96), at(a, 108), major);
        final label = lo + (hi - lo) * i / 10;
        final tp = TextPainter(
          text: TextSpan(
              text: label.round().toString(),
              style: labelStyle.copyWith(
                  color: AppColors.gaugeInkSoft, fontSize: 12)),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, at(a, 137) - Offset(tp.width / 2, tp.height / 2));
      } else {
        canvas.drawLine(at(a, 101), at(a, 108), minor);
      }
    }

    final needleAngle = _angle(v ?? lo);
    canvas.drawLine(
        at(needleAngle + math.pi, 10),
        at(needleAngle, 110),
        Paint()
          ..color = AppColors.gaugeNeedle
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round);
    canvas.drawCircle(c, 9, Paint()..color = AppColors.gaugeHub);
    canvas.drawCircle(
        c,
        9,
        Paint()
          ..color = AppColors.gaugeMinorTick
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5);
    canvas.drawCircle(c, 2.5, Paint()..color = AppColors.gaugeNeedle);
  }

  @override
  bool shouldRepaint(_GaugePainter old) =>
      old.lo != lo || old.hi != hi || old.value != value || old.arc != arc;
}
