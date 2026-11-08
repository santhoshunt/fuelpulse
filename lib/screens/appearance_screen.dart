import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/palettes.dart';
import '../utils/appearance_prefs.dart';
import 'settings/settings_widgets.dart';

/// Light, dark or the phone's mode, and the colour palette. Every choice
/// applies at once to the whole app, this page included, so the page is
/// its own preview.
class AppearanceScreen extends StatelessWidget {
  const AppearanceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Appearance')),
      body: ValueListenableBuilder<Appearance>(
        valueListenable: appearance,
        builder: (context, a, _) {
          final colors = AppColors.of(context);
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              sectionHeader('Theme'),
              const SizedBox(height: 12),
              SegmentedButton<ThemeMode>(
                segments: const [
                  ButtonSegment(value: ThemeMode.light, label: Text('Light')),
                  ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
                  ButtonSegment(value: ThemeMode.system, label: Text('System')),
                ],
                selected: {a.mode},
                showSelectedIcon: false,
                onSelectionChanged: (s) =>
                    saveAppearance(a.copyWith(mode: s.first)),
              ),
              const SizedBox(height: 28),
              sectionHeader('Preview: ${a.palette.name}'),
              const SizedBox(height: 12),
              _Preview(colors: colors),
              const SizedBox(height: 28),
              sectionHeader('${kPalettes.length} palettes'),
              const SizedBox(height: 12),
              GridView.count(
                crossAxisCount: 5,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 12,
                childAspectRatio: 0.8,
                children: [
                  for (final p in kPalettes)
                    _Swatch(
                      palette: p,
                      selected: p.id == a.paletteId,
                      onTap: () => saveAppearance(a.copyWith(paletteId: p.id)),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                  'Each palette is a primary colour for buttons, tabs and '
                  'charts, and a partner for spend bars and the tank level.',
                  style: TextStyle(color: colors.textSecondary, fontSize: 13)),
            ],
          );
        },
      ),
    );
  }
}

/// A small sample of the app in the current palette: the gauge gradient, a
/// button, spend bars and a progress bar.
class _Preview extends StatelessWidget {
  final AppColors colors;

  const _Preview({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 64,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              alignment: Alignment.centerLeft,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: LinearGradient(
                    colors: [colors.gaugeStart, colors.gaugeEnd]),
              ),
              child: const Text('28.0 km/L',
                  style: TextStyle(
                      color: AppColors.gaugeInk,
                      fontSize: 22,
                      fontWeight: FontWeight.w700)),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                FilledButton(onPressed: () {}, child: const Text('Save')),
                const Spacer(),
                Text('View all ›',
                    style: TextStyle(
                        color: colors.primary, fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 48,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final h in const [0.4, 0.55, 0.3, 0.7, 1.0, 0.6])
                    Expanded(
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 6),
                        height: 48 * h,
                        decoration: BoxDecoration(
                          color: colors.secondary,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: 0.7,
                minHeight: 6,
                color: colors.primarySoft,
                backgroundColor: colors.cardBorder,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A palette as a circle split into its primary and partner colours.
class _Swatch extends StatelessWidget {
  final Palette palette;
  final bool selected;
  final VoidCallback onTap;

  const _Swatch(
      {required this.palette, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: '${palette.name} palette',
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          children: [
            Container(
              width: 48,
              height: 48,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                    color: selected ? colors.textPrimary : Colors.transparent,
                    width: 2),
              ),
              child: ClipOval(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(flex: 3, child: ColoredBox(color: palette.primary)),
                    Expanded(
                        flex: 2, child: ColoredBox(color: palette.secondary)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 4),
            ExcludeSemantics(
              child: Text(palette.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: colors.textSecondary, fontSize: 12)),
            ),
          ],
        ),
      ),
    );
  }
}
