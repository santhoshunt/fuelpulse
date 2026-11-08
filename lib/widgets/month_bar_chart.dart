import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../theme/app_colors.dart';

/// One bar per month, value printed above it, month name below. Bars use
/// the palette's secondary colour.
class MonthBarChart extends StatelessWidget {
  final List<(DateTime month, double value)> bars;
  final String Function(double) formatValue;

  const MonthBarChart({
    super.key,
    required this.bars,
    required this.formatValue,
  });

  static const _plot = 133.0;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final top = bars.isEmpty ? 0.0 : bars.map((b) => b.$2).reduce(math.max);
    final label = TextStyle(color: colors.textSecondary, fontSize: 11);
    return Column(
      children: [
        Container(
          height: 170,
          decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: colors.cardBorder))),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final (_, v) in bars)
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      FittedBox(child: Text(formatValue(v), style: label)),
                      const SizedBox(height: 4),
                      Container(
                        constraints: const BoxConstraints(maxWidth: 30),
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        // A zero month keeps a sliver so the slot reads as
                        // a month with nothing, not a missing bar.
                        height: top > 0 ? math.max(2, _plot * v / top) : 2,
                        decoration: BoxDecoration(
                          color: colors.secondary,
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(6),
                              bottom: Radius.circular(2)),
                        ),
                      ),
                    ],
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
    );
  }
}
