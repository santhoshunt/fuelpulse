import 'package:flutter/material.dart';

/// One choice in Settings › Appearance. The primary colour carries buttons,
/// the active tab, links, line charts and the gauge card, about 70% of the
/// colour on screen. The secondary is its partner for bar charts and the tank
/// level, about 20%. Everything else is a tint of the primary or a neutral
/// grey (see `AppColors`), so a palette never needs a third hue tuned.
class Palette {
  final String id;
  final String name;
  final Color primary;
  final Color secondary;

  const Palette(this.id, this.name, this.primary, this.secondary);
}

/// Primaries are dark enough for white button text (4.5:1 or better);
/// partners sit in a different hue family so bars never blend into them.
const List<Palette> kPalettes = [
  Palette('blue', 'Blue', Color(0xFF1F5FBF), Color(0xFFD97706)),
  Palette('indigo', 'Indigo', Color(0xFF4338CA), Color(0xFFD97706)),
  Palette('teal', 'Teal', Color(0xFF0F766E), Color(0xFFEA580C)),
  Palette('green', 'Green', Color(0xFF15803D), Color(0xFFCA8A04)),
  Palette('emerald', 'Emerald', Color(0xFF047857), Color(0xFFE11D48)),
  Palette('orange', 'Orange', Color(0xFFC2410C), Color(0xFF0284C7)),
  Palette('red', 'Red', Color(0xFFB91C1C), Color(0xFFD97706)),
  Palette('pink', 'Pink', Color(0xFFBE185D), Color(0xFF0D9488)),
  Palette('purple', 'Purple', Color(0xFF6D28D9), Color(0xFFEA580C)),
  Palette('violet', 'Violet', Color(0xFF7C3AED), Color(0xFF0891B2)),
  Palette('maroon', 'Maroon', Color(0xFF7A1F3D), Color(0xFFB7791F)),
  Palette('slate', 'Slate', Color(0xFF334155), Color(0xFF0284C7)),
  Palette('coffee', 'Coffee', Color(0xFF7C4A1E), Color(0xFF0F766E)),
  Palette('navy', 'Navy', Color(0xFF1E3A8A), Color(0xFFE11D48)),
  Palette('ocean', 'Ocean', Color(0xFF0E7490), Color(0xFFEA580C)),
];

const String kDefaultPaletteId = 'blue';

/// The palette with [id]; blue for null or an id no longer offered.
Palette paletteById(String? id) => kPalettes.firstWhere(
      (p) => p.id == id,
      orElse: () => kPalettes.first,
    );
