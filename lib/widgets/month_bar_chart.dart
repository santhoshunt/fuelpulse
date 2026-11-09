import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../theme/app_colors.dart';

/// One bar per month, value printed above it, month name below. Bars use
/// the palette's secondary colour. Touch or drag across the bars to lift
/// one: it stays bright with its month and amount in a bubble, the rest
/// fade, until the next touch.
class MonthBarChart extends StatefulWidget {
  final List<(DateTime month, double value)> bars;
  final String Function(double) formatValue;

  const MonthBarChart({
    super.key,
    required this.bars,
    required this.formatValue,
  });

  @override
  State<MonthBarChart> createState() => _MonthBarChartState();
}

class _MonthBarChartState extends State<MonthBarChart> {
  static const _plot = 133.0;
  int? _picked;

  @override
  void didUpdateWidget(MonthBarChart old) {
    super.didUpdateWidget(old);
    if (old.bars.length != widget.bars.length) _picked = null;
  }

  void _pick(double dx, double width) {
    final n = widget.bars.length;
    if (n == 0) return;
    final i = (dx / width * n).floor().clamp(0, n - 1);
    if (i != _picked) setState(() => _picked = i);
  }

  void _clear() {
    if (_picked != null) setState(() => _picked = null);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final bars = widget.bars;
    final top = bars.isEmpty ? 0.0 : bars.map((b) => b.$2).reduce(math.max);
    final label = TextStyle(color: colors.textSecondary, fontSize: 11);
    return TapRegion(
      // A touch anywhere else puts the reading away.
      onTapOutside: (_) => _clear(),
      child: LayoutBuilder(
      builder: (context, box) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (d) => _pick(d.localPosition.dx, box.maxWidth),
        onHorizontalDragStart: (d) => _pick(d.localPosition.dx, box.maxWidth),
        onHorizontalDragUpdate: (d) => _pick(d.localPosition.dx, box.maxWidth),
        child: Column(
          children: [
            SizedBox(
              height: 170,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
            Container(
              height: 170,
              decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: colors.cardBorder))),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var i = 0; i < bars.length; i++)
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          AnimatedOpacity(
                            duration: const Duration(milliseconds: 180),
                            opacity: _picked == null
                                ? 1
                                : _picked == i
                                    ? 0
                                    : 0.4,
                            child: FittedBox(
                                child: Text(widget.formatValue(bars[i].$2),
                                    style: label)),
                          ),
                          const SizedBox(height: 4),
                          AnimatedOpacity(
                            duration: const Duration(milliseconds: 180),
                            opacity: _picked == null || _picked == i ? 1 : 0.35,
                            child: Container(
                              constraints: const BoxConstraints(maxWidth: 30),
                              margin: const EdgeInsets.symmetric(horizontal: 3),
                              // A zero month keeps a sliver so the slot reads
                              // as a month with nothing, not a missing bar.
                              height: top > 0
                                  ? math.max(2, _plot * bars[i].$2 / top)
                                  : 2,
                              decoration: BoxDecoration(
                                color: colors.secondary,
                                borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(6),
                                    bottom: Radius.circular(2)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
                  if (_picked != null && _picked! < bars.length)
                    Positioned(
                      top: 0,
                      left: ((_picked! + 0.5) * box.maxWidth / bars.length - 70)
                          .clamp(0.0, math.max(0.0, box.maxWidth - 140)),
                      width: 140,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: colors.textPrimary,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                              '${DateFormat('MMM y').format(bars[_picked!].$1)} · '
                              '${widget.formatValue(bars[_picked!].$2)}',
                              style: TextStyle(
                                  color: colors.card,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                for (final (m, _) in bars)
                  Expanded(
                    child: Text(DateFormat('MMM').format(m),
                        textAlign: TextAlign.center,
                        style: label.copyWith(fontSize: 12)),
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
    );
  }
}
