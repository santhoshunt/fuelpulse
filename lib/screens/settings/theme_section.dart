import 'package:flutter/material.dart';
import '../../models/theme_preference.dart';
import '../../widgets/color_swatch_picker.dart';
import 'settings_widgets.dart';

class ThemeSection extends StatelessWidget {
  final ThemePreference current;
  final ValueChanged<ThemePreference> onChanged;

  const ThemeSection(
      {super.key, required this.current, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        sectionHeader('Theme Color'),
        const SizedBox(height: 12),
        ColorSwatchPicker(
          current: current,
          onChanged: onChanged,
        ),
      ],
    );
  }
}
