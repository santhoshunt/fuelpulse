import 'package:flutter/material.dart';
import '../utils/tank_level_calculator.dart';

/// Horizontal fuel gauge bar widget.
class FuelGauge extends StatelessWidget {
  final double level;
  final double capacity;

  const FuelGauge({
    super.key,
    required this.level,
    required this.capacity,
  });

  @override
  Widget build(BuildContext context) {
    if (capacity <= 0) {
      return const SizedBox.shrink();
    }

    final pct = (level / capacity).clamp(0.0, 1.0);
    final tier = getFuelLevel(level, capacity);

    final Color barColor;
    switch (tier) {
      case FuelLevel.high:
        barColor = const Color(0xFF22C55E); // green
        break;
      case FuelLevel.mid:
        barColor = const Color(0xFFFBBF24); // amber
        break;
      case FuelLevel.low:
        barColor = const Color(0xFFEF4444); // red
        break;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            height: 5,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 400),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return Stack(
                    children: [
                      Container(
                        width: constraints.maxWidth,
                        color: Colors.white.withValues(alpha: 0.08),
                      ),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 400),
                        width: constraints.maxWidth * pct,
                        decoration: BoxDecoration(
                          color: barColor,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}
