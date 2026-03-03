import 'package:flutter/material.dart';

/// A performant glossy card container that mimics the PWA glass-panel look:
///  - Dark base with subtle gradient
///  - Accent-colored glowing border
///  - Top-left sheen highlight
///  - Soft outer glow shadow
///
/// No BackdropFilter — all effects are paint-only for scroll perf.
class GlossyCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final double borderRadius;

  /// Override border glow color (defaults to theme accent).
  final Color? glowColor;

  const GlossyCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.margin = EdgeInsets.zero,
    this.borderRadius = 16,
    this.glowColor,
  });

  @override
  Widget build(BuildContext context) {
    final accent = glowColor ?? Theme.of(context).colorScheme.primary;
    final radius = BorderRadius.circular(borderRadius);

    return RepaintBoundary(
      child: Container(
        margin: margin,
        decoration: BoxDecoration(
          borderRadius: radius,
          // Outer glow
          boxShadow: [
            BoxShadow(
              color: accent.withValues(alpha: 0.12),
              blurRadius: 18,
              spreadRadius: -2,
              offset: const Offset(0, 2),
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: CustomPaint(
            painter: _GlossyPainter(accent: accent, borderRadius: borderRadius),
            child: Container(
              padding: padding,
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

/// Custom painter for the glossy card effect.
/// Draws:
///  1. Dark base fill
///  2. Accent-tinted edge gradient (top-left to bottom-right)
///  3. Top-left sheen highlight
///  4. Accent-colored border with glow
class _GlossyPainter extends CustomPainter {
  final Color accent;
  final double borderRadius;

  _GlossyPainter({required this.accent, required this.borderRadius});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(borderRadius));

    // 1. Dark base
    final basePaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          const Color(0xFF161619),
          const Color(0xFF0F0F12),
          const Color(0xFF0A0A0D),
        ],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(rect);
    canvas.drawRRect(rrect, basePaint);

    // 2. Subtle accent bleed from top-left corner
    final accentBleed = Paint()
      ..shader = RadialGradient(
        center: Alignment.topLeft,
        radius: 1.2,
        colors: [
          accent.withValues(alpha: 0.08),
          accent.withValues(alpha: 0.02),
          Colors.transparent,
        ],
        stops: const [0.0, 0.4, 1.0],
      ).createShader(rect);
    canvas.drawRRect(rrect, accentBleed);

    // 3. Top-left sheen (white highlight)
    final sheenPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.8, -0.8),
        radius: 0.8,
        colors: [
          Colors.white.withValues(alpha: 0.07),
          Colors.white.withValues(alpha: 0.02),
          Colors.transparent,
        ],
        stops: const [0.0, 0.3, 1.0],
      ).createShader(rect);
    canvas.drawRRect(rrect, sheenPaint);

    // 4. Glowing border
    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          accent.withValues(alpha: 0.40),
          accent.withValues(alpha: 0.15),
          Colors.white.withValues(alpha: 0.06),
        ],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(rect);
    canvas.drawRRect(rrect, borderPaint);
  }

  @override
  bool shouldRepaint(_GlossyPainter oldDelegate) =>
      accent != oldDelegate.accent || borderRadius != oldDelegate.borderRadius;
}
