import 'package:flutter/material.dart';
import '../utils/constants.dart';
import 'glossy_card.dart';

/// Single stat card with label + prominent value + optional subtitle.
class StatCard extends StatelessWidget {
  final String emoji;
  final String label;
  final String value;
  final String? subtitle;
  final Color? borderColor;
  final Color? backgroundColor;

  const StatCard({
    super.key,
    required this.emoji,
    required this.label,
    required this.value,
    this.subtitle,
    this.borderColor,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final border = borderColor ?? accent.withValues(alpha: 0.3);
    final bg = backgroundColor ?? Colors.white.withValues(alpha: 0.04);

    return GlossyCard(
          padding: const EdgeInsets.all(16),
          borderRadius: 18,
          glowColor: borderColor,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                emoji,
                style: const TextStyle(fontSize: 22),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                style: const TextStyle(
                  color: kTextSecondary,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: const TextStyle(
                  color: kTextPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  style: TextStyle(
                    color: accent,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
    );
  }
}
