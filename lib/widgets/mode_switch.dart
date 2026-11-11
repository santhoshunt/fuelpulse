import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import 'period_selector.dart' show SlidingSegments;

/// Segmented toggle switch between Odometer and KM Travelled modes.
class ModeSwitch extends StatelessWidget {
  final bool isKmMode; // false = Odometer, true = KM Travelled
  final bool kmModeEnabled;
  final ValueChanged<bool> onChanged;

  const ModeSwitch({
    super.key,
    required this.isKmMode,
    required this.kmModeEnabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return SlidingSegments(
      labels: const ['Odometer', 'Distance'],
      selected: isKmMode ? 1 : 0,
      enabled: [true, kmModeEnabled],
      onTap: (i) => onChanged(i == 1),
      background:
          Color.alphaBlend(colors.textPrimary.withValues(alpha: 0.07), colors.page),
      height: 38,
    );
  }
}
