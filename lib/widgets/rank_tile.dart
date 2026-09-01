import 'package:flutter/material.dart';
import '../utils/constants.dart';
import 'glossy_card.dart';

/// Single row in a ranking list (brands, fuel types).
class RankTile extends StatelessWidget {
  final int rank;
  final String label;
  final int fillCount;
  final double totalLiters;
  final double efficiency;
  final double bestEfficiency;
  final double deltaVsOverall;

  /// Rendered before the delta chip; when null, the label renders as text.
  final Widget? leading;

  /// Extra strings appended to the bottom detail row after fills/litres.
  final List<String> extraDetails;

  const RankTile({
    super.key,
    required this.rank,
    required this.label,
    required this.fillCount,
    required this.totalLiters,
    required this.efficiency,
    required this.bestEfficiency,
    required this.deltaVsOverall,
    this.leading,
    this.extraDetails = const [],
  });

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final barFraction =
        bestEfficiency > 0 ? (efficiency / bestEfficiency).clamp(0.0, 1.0) : 0.0;
    final isPositive = deltaVsOverall >= 0;

    return GlossyCard(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      borderRadius: 14,
      child: Column(
        children: [
          Row(
            children: [
              // Rank
              SizedBox(
                width: 28,
                child: Text(
                  '#$rank',
                  style: TextStyle(
                    color: accent,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
              // Leading — Expanded (not Spacer) so a long label
              // ellipsizes instead of crowding the delta chip.
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: leading ??
                      Text(
                        label,
                        style: const TextStyle(
                            color: kTextPrimary, fontSize: 13),
                        overflow: TextOverflow.ellipsis,
                      ),
                ),
              ),
              // Delta
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: (isPositive
                          ? const Color(0xFF22C55E)
                          : const Color(0xFFEF4444))
                      .withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${isPositive ? '▲' : '▼'} ${deltaVsOverall.abs().toStringAsFixed(1)}',
                  style: TextStyle(
                    color: isPositive
                        ? const Color(0xFF22C55E)
                        : const Color(0xFFEF4444),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // km/L value
              Text(
                '${efficiency.toStringAsFixed(1)} km/L',
                style: const TextStyle(
                  color: kTextPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Efficiency bar
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 6,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return Stack(
                    children: [
                      Container(
                        width: constraints.maxWidth,
                        color: Colors.white.withValues(alpha: 0.08),
                      ),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 500),
                        width: constraints.maxWidth * barFraction,
                        decoration: BoxDecoration(
                          color: accent,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 8),
          // Detail row
          Row(
            children: [
              Text(
                '$fillCount fills',
                style: const TextStyle(color: kTextMuted, fontSize: 12),
              ),
              const SizedBox(width: 16),
              Text(
                '${totalLiters.toStringAsFixed(1)} L total',
                style: const TextStyle(color: kTextMuted, fontSize: 12),
              ),
              for (final detail in extraDetails) ...[
                const SizedBox(width: 16),
                Flexible(
                  child: Text(
                    detail,
                    style: const TextStyle(color: kTextMuted, fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
