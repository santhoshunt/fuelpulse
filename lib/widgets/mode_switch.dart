import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

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
    return Container(
      decoration: BoxDecoration(
        color: Color.alphaBlend(
            colors.textPrimary.withValues(alpha: 0.07), colors.page),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        children: [
          _tab(colors,
              label: 'Odometer',
              selected: !isKmMode,
              onTap: () => onChanged(false),
              enabled: true),
          _tab(colors,
              label: 'KM Travelled',
              selected: isKmMode,
              onTap: () => onChanged(true),
              enabled: kmModeEnabled),
        ],
      ),
    );
  }

  Widget _tab(
    AppColors colors, {
    required String label,
    required bool selected,
    required VoidCallback onTap,
    required bool enabled,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: 38,
          decoration: BoxDecoration(
            color: selected ? colors.card : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: selected
                  ? colors.textPrimary
                  : colors.textSecondary
                      .withValues(alpha: enabled ? 1 : 0.5),
              fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }
}
