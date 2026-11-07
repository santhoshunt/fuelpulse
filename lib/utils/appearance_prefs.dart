import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/palettes.dart';

/// Palette id from `kPalettes`, and `light`, `dark` or `system`.
const String kPaletteIdKey = 'fuel_palette_id';
const String kThemeModeKey = 'fuel_theme_mode';

/// What the app looks like: one of the palettes, in light, dark or the
/// phone's own mode.
@immutable
class Appearance {
  final String paletteId;
  final ThemeMode mode;

  const Appearance({this.paletteId = kDefaultPaletteId, this.mode = ThemeMode.system});

  Palette get palette => paletteById(paletteId);

  Appearance copyWith({String? paletteId, ThemeMode? mode}) => Appearance(
        paletteId: paletteId ?? this.paletteId,
        mode: mode ?? this.mode,
      );

  @override
  bool operator ==(Object other) =>
      other is Appearance &&
      other.paletteId == paletteId &&
      other.mode == mode;

  @override
  int get hashCode => Object.hash(paletteId, mode);
}

/// The app rebuilds its theme whenever this changes, so Settings and a
/// backup restore only have to save or reload.
final ValueNotifier<Appearance> appearance =
    ValueNotifier(const Appearance());

ThemeMode themeModeFromName(String? name) => ThemeMode.values.firstWhere(
      (m) => m.name == name,
      orElse: () => ThemeMode.system,
    );

/// Today's choice. An unknown palette id falls back to blue; pre-v2.2.0
/// accent colours have no palette and are not read.
Future<Appearance> loadAppearance() async {
  final prefs = await SharedPreferences.getInstance();
  return Appearance(
    paletteId: paletteById(prefs.getString(kPaletteIdKey)).id,
    mode: themeModeFromName(prefs.getString(kThemeModeKey)),
  );
}

Future<void> saveAppearance(Appearance a) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(kPaletteIdKey, a.paletteId);
  await prefs.setString(kThemeModeKey, a.mode.name);
  appearance.value = a;
}

/// Picks up a choice written straight to prefs, such as by a backup restore.
Future<void> reloadAppearance() async {
  appearance.value = await loadAppearance();
}
