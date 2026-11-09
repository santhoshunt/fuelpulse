import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// A row of period buttons (1M, 3M, 6M, 12M) for one Analytics card, or of
/// any other choices given a [label].
class PeriodSelector extends StatelessWidget {
  final int months;
  final List<int> options;
  final ValueChanged<int> onChanged;

  /// The text for each option; months ("6M") when null.
  final String Function(int)? label;

  const PeriodSelector({
    super.key,
    required this.months,
    required this.options,
    required this.onChanged,
    this.label,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return SlidingSegments(
      labels: [for (final m in options) label?.call(m) ?? '${m}M'],
      selected: options.indexOf(months),
      onTap: (i) => onChanged(options[i]),
      background:
          Color.alphaBlend(colors.textPrimary.withValues(alpha: 0.07), colors.card),
      height: 34,
    );
  }
}

/// Segmented buttons whose white highlight slides to the one picked. Used
/// by [PeriodSelector] and the fill-up form's Odometer / KM Travelled
/// switch.
class SlidingSegments extends StatelessWidget {
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onTap;
  final Color background;
  final double height;

  /// Per label; a disabled one is dimmed and ignores taps. All enabled when
  /// null.
  final List<bool>? enabled;

  const SlidingSegments({
    super.key,
    required this.labels,
    required this.selected,
    required this.onTap,
    required this.background,
    required this.height,
    this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final n = labels.length;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: SizedBox(
        height: height,
        child: Stack(
          children: [
            if (selected >= 0)
              AnimatedAlign(
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeOutCubic,
                alignment: Alignment(n == 1 ? 0 : -1 + 2 * selected / (n - 1), 0),
                child: FractionallySizedBox(
                  widthFactor: 1 / n,
                  heightFactor: 1,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.card,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
            Row(
              children: [
                for (var i = 0; i < n; i++)
                  Expanded(
                    child: Semantics(
                      button: true,
                      selected: i == selected,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: enabled?[i] == false ? null : () => onTap(i),
                        child: Center(
                          child: AnimatedDefaultTextStyle(
                            duration: const Duration(milliseconds: 200),
                            // The theme's font: a bare TextStyle would drop
                            // it, which shows only where it differs from
                            // the phone's default (as in the README shots).
                            style: TextStyle(
                              fontFamily: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.fontFamily,
                              fontFamilyFallback: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.fontFamilyFallback,
                              fontSize: 14,
                              color: i == selected
                                  ? colors.textPrimary
                                  : colors.textSecondary.withValues(
                                      alpha: enabled?[i] == false ? 0.5 : 1),
                              fontWeight:
                                  i == selected ? FontWeight.w600 : FontWeight.w400,
                            ),
                            child: Text(labels[i]),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
