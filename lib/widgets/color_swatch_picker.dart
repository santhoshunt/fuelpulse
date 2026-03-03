import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import '../models/theme_preference.dart';
import '../utils/constants.dart';

/// Grid of theme color swatches + custom color picker.
class ColorSwatchPicker extends StatelessWidget {
  final ThemePreference current;
  final ValueChanged<ThemePreference> onChanged;

  const ColorSwatchPicker({
    super.key,
    required this.current,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Neon section
        const Text(
          'Neon',
          style: TextStyle(color: kTextSecondary, fontSize: 12),
        ),
        const SizedBox(height: 8),
        _buildSwatchRow(kThemePresets.where((p) => p.category == 'Neon').toList()),
        const SizedBox(height: 16),
        // Classic section
        const Text(
          'Classic',
          style: TextStyle(color: kTextSecondary, fontSize: 12),
        ),
        const SizedBox(height: 8),
        _buildSwatchRow(
            kThemePresets.where((p) => p.category == 'Classic').toList()),
        const SizedBox(height: 16),
        // Actions
        Row(
          children: [
            _actionButton(
              context,
              icon: Icons.colorize,
              label: 'Custom',
              onTap: () => _openCustomPicker(context),
            ),
            const SizedBox(width: 12),
            _actionButton(
              context,
              icon: Icons.refresh,
              label: 'Reset',
              onTap: () => onChanged(ThemePreference.defaults),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSwatchRow(List<ThemePresetSwatch> presets) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: presets.map((preset) {
        final isSelected =
            current.accent.toUpperCase() == preset.accent.toUpperCase();
        final color = ThemePreference.hexToColor(preset.accent);

        return GestureDetector(
          onTap: () => onChanged(preset.toThemePreference()),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: isSelected
                  ? Border.all(color: Colors.white, width: 3)
                  : Border.all(
                      color: Colors.white.withValues(alpha: 0.15), width: 1),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: color.withValues(alpha: 0.5),
                        blurRadius: 12,
                        spreadRadius: 1,
                      ),
                    ]
                  : [],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _actionButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: kTextSecondary),
            const SizedBox(width: 6),
            Text(label,
                style: const TextStyle(color: kTextSecondary, fontSize: 13)),
          ],
        ),
      ),
    );
  }

  void _openCustomPicker(BuildContext context) {
    Color pickerColor = current.accentColor;

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Pick a color'),
          content: SingleChildScrollView(
            child: ColorPicker(
              pickerColor: pickerColor,
              onColorChanged: (c) => pickerColor = c,
              enableAlpha: false,
              labelTypes: const [],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final hex =
                    '#${pickerColor.toARGB32().toRadixString(16).substring(2).toUpperCase()}';
                onChanged(ThemePreference.fromAccent(hex));
                Navigator.pop(ctx);
              },
              child: const Text('Apply'),
            ),
          ],
        );
      },
    );
  }
}
