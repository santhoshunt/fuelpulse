import 'package:flutter/material.dart';
import '../utils/constants.dart';

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
    final accent = Theme.of(context).colorScheme.primary;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: 0.07),
            Colors.white.withValues(alpha: 0.03),
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          _tab(
            label: 'Odometer',
            selected: !isKmMode,
            accent: accent,
            onTap: () => onChanged(false),
            enabled: true,
          ),
          _tab(
            label: 'KM Travelled',
            selected: isKmMode,
            accent: accent,
            onTap: () => onChanged(true),
            enabled: kmModeEnabled,
          ),
        ],
      ),
    );
  }

  Widget _tab({
    required String label,
    required bool selected,
    required Color accent,
    required VoidCallback onTap,
    required bool enabled,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? accent.withValues(alpha: 0.15) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: !enabled && !selected
                  ? kTextMuted
                  : selected
                      ? accent
                      : kTextSecondary,
              fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }
}
