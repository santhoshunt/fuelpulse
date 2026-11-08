import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// A row of period buttons (1M, 3M, 6M, 12M) for one Analytics card.
class PeriodSelector extends StatelessWidget {
  final int months;
  final List<int> options;
  final ValueChanged<int> onChanged;

  const PeriodSelector({
    super.key,
    required this.months,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
            colors.textPrimary.withValues(alpha: 0.07), colors.card),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          for (final m in options)
            Expanded(
              child: Semantics(
                button: true,
                selected: m == months,
                child: GestureDetector(
                  onTap: () => onChanged(m),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: m == months ? colors.card : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text('${m}M',
                        style: TextStyle(
                            fontSize: 14,
                            color: m == months
                                ? colors.textPrimary
                                : colors.textSecondary,
                            fontWeight: m == months
                                ? FontWeight.w600
                                : FontWeight.w400)),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
