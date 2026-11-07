import 'package:flutter/material.dart';

import 'palettes.dart';

/// Every colour a screen needs, worked out once from the palette and the
/// light or dark mode. Screens read these through [AppColors.of] and never
/// hold a hex value of their own, so a palette or mode switch repaints all
/// of them alike.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  /// Behind everything.
  final Color page;

  /// Cards and list groups, a clear step off [page] in both modes.
  final Color card;
  final Color cardBorder;
  final Color textPrimary;
  final Color textSecondary;

  /// Buttons, active tab, links, line charts. Lightened in dark mode so it
  /// still reads on a dark card.
  final Color primary;

  /// Text and icons drawn on [primary].
  final Color onPrimary;

  /// Pale fill behind tags and icon tiles.
  final Color primaryTint;

  /// Softer primary for comparison bars that aren't the best one.
  final Color primarySoft;

  /// Bar charts and the tank level.
  final Color secondary;

  /// The dashboard gauge card fades from [gaugeStart] to [gaugeEnd].
  final Color gaugeStart;
  final Color gaugeEnd;
  final Color danger;
  final Color warning;

  const AppColors({
    required this.page,
    required this.card,
    required this.cardBorder,
    required this.textPrimary,
    required this.textSecondary,
    required this.primary,
    required this.onPrimary,
    required this.primaryTint,
    required this.primarySoft,
    required this.secondary,
    required this.gaugeStart,
    required this.gaugeEnd,
    required this.danger,
    required this.warning,
  });

  factory AppColors.from(Palette p, Brightness b) {
    final dark = b == Brightness.dark;
    final card = dark ? const Color(0xFF1C222D) : Colors.white;
    final primary = dark ? Color.lerp(p.primary, Colors.white, 0.35)! : p.primary;
    return AppColors(
      page: dark ? const Color(0xFF0B0D12) : const Color(0xFFF2F0EC),
      card: card,
      cardBorder: dark ? const Color(0xFF2C3442) : const Color(0xFFE4E0DA),
      textPrimary: dark ? const Color(0xFFF5F7FA) : const Color(0xFF1C1B1A),
      textSecondary: dark ? const Color(0xFF9AA6B8) : const Color(0xFF6B6660),
      primary: primary,
      onPrimary: primary.computeLuminance() > 0.35
          ? const Color(0xFF0B0D12)
          : Colors.white,
      primaryTint: Color.alphaBlend(primary.withValues(alpha: 0.12), card),
      primarySoft: Color.alphaBlend(primary.withValues(alpha: 0.45), card),
      secondary:
          dark ? Color.lerp(p.secondary, Colors.white, 0.15)! : p.secondary,
      gaugeStart: Color.lerp(
          p.primary, const Color(0xFF0A0A0F), dark ? 0.88 : 0.82)!,
      gaugeEnd: dark
          ? Color.lerp(p.primary, Colors.black, 0.10)!
          : Color.lerp(p.primary, Colors.white, 0.15)!,
      danger: dark ? const Color(0xFFF2867F) : const Color(0xFFB3261E),
      warning: dark ? const Color(0xFFE6C34A) : const Color(0xFF8A6D00),
    );
  }

  static AppColors of(BuildContext context) =>
      Theme.of(context).extension<AppColors>()!;

  @override
  AppColors copyWith({
    Color? page,
    Color? card,
    Color? cardBorder,
    Color? textPrimary,
    Color? textSecondary,
    Color? primary,
    Color? onPrimary,
    Color? primaryTint,
    Color? primarySoft,
    Color? secondary,
    Color? gaugeStart,
    Color? gaugeEnd,
    Color? danger,
    Color? warning,
  }) =>
      AppColors(
        page: page ?? this.page,
        card: card ?? this.card,
        cardBorder: cardBorder ?? this.cardBorder,
        textPrimary: textPrimary ?? this.textPrimary,
        textSecondary: textSecondary ?? this.textSecondary,
        primary: primary ?? this.primary,
        onPrimary: onPrimary ?? this.onPrimary,
        primaryTint: primaryTint ?? this.primaryTint,
        primarySoft: primarySoft ?? this.primarySoft,
        secondary: secondary ?? this.secondary,
        gaugeStart: gaugeStart ?? this.gaugeStart,
        gaugeEnd: gaugeEnd ?? this.gaugeEnd,
        danger: danger ?? this.danger,
        warning: warning ?? this.warning,
      );

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppColors(
      page: c(page, other.page),
      card: c(card, other.card),
      cardBorder: c(cardBorder, other.cardBorder),
      textPrimary: c(textPrimary, other.textPrimary),
      textSecondary: c(textSecondary, other.textSecondary),
      primary: c(primary, other.primary),
      onPrimary: c(onPrimary, other.onPrimary),
      primaryTint: c(primaryTint, other.primaryTint),
      primarySoft: c(primarySoft, other.primarySoft),
      secondary: c(secondary, other.secondary),
      gaugeStart: c(gaugeStart, other.gaugeStart),
      gaugeEnd: c(gaugeEnd, other.gaugeEnd),
      danger: c(danger, other.danger),
      warning: c(warning, other.warning),
    );
  }
}
