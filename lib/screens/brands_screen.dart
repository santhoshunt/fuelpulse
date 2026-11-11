import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../utils/brand_grades.dart';
import '../utils/custom_pictures.dart';
import '../utils/page_routes.dart';
import '../widgets/add_fuel_type_dialog.dart';
import '../widgets/brand_logo.dart';
import 'settings/settings_widgets.dart';

/// Fuel brands and the grades each sells, offered in the refill form.
class BrandsScreen extends StatefulWidget {
  const BrandsScreen({super.key});

  @override
  State<BrandsScreen> createState() => _BrandsScreenState();
}

class _BrandsScreenState extends State<BrandsScreen> {
  Map<String, List<String>> _map = const {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final map = await loadBrandGrades();
    if (mounted) setState(() => _map = map);
  }

  Future<void> _add() async {
    final name = await showAddFuelTypeDialog(context,
        title: 'Add pump brand', hint: 'e.g. Reliance');
    if (name == null || name.trim().isEmpty) return;
    if (!await addBrand(name) && mounted) {
      showSettingsSnack(context, '"${name.trim()}" already exists.');
    }
    await _load();
  }

  Future<void> _open(String brand) async {
    await Navigator.push(
        context, SmoothPageRoute(page: BrandEditScreen(brand: brand)));
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Brands'),
        actions: [
          IconButton(
              tooltip: 'Add brand',
              icon: const Icon(Icons.add),
              onPressed: _add),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          settingsGroup([
            for (final e in _map.entries)
              InkWell(
                onTap: () => _open(e.key),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                  child: Row(
                    children: [
                      BrandLogo(brandName: e.key, size: 40),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(e.key,
                                style: TextStyle(
                                    color: colors.textPrimary,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600)),
                            Text(e.value.join(' · '),
                                style: TextStyle(
                                    color: colors.textSecondary,
                                    fontSize: 13)),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right, color: colors.textSecondary),
                    ],
                  ),
                ),
              ),
          ]),
          const SizedBox(height: 12),
          Text('Tap a brand to rename it or edit its fuel grades.',
              style: TextStyle(color: colors.textSecondary, fontSize: 13)),
        ],
      ),
    );
  }
}

/// One brand: its name and its fuel grades. Renames reach every fill-up;
/// deletes only stop offering the name.
class BrandEditScreen extends StatefulWidget {
  final String brand;

  const BrandEditScreen({super.key, required this.brand});

  @override
  State<BrandEditScreen> createState() => _BrandEditScreenState();
}

class _BrandEditScreenState extends State<BrandEditScreen> {
  late String _brand = widget.brand;
  List<String> _grades = const [];
  int _brandCount = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final map = await loadBrandGrades();
    if (!mounted) return;
    setState(() {
      _grades = map[_brand] ?? const [];
      _brandCount = map.length;
    });
  }

  void _snack(String s) => showSettingsSnack(context, s);

  String _updated(int n) =>
      'Renamed. Updated $n existing ${n == 1 ? 'fill-up' : 'fill-ups'}.';

  Future<void> _rename() async {
    final name = await showAddFuelTypeDialog(context,
        title: 'Rename Pump Brand', initial: _brand, hint: 'e.g. Reliance');
    if (name == null || name.trim().isEmpty || name.trim() == _brand) return;
    final n = await renameBrand(_brand, name);
    if (!mounted) return;
    if (n < 0) {
      _snack('"${name.trim()}" already exists.');
      return;
    }
    _snack(_updated(n));
    setState(() => _brand = name.trim());
    await _load();
  }

  Future<void> _changeLogo() async {
    final name = await pickSquarePicture('brand');
    if (name == null) return;
    await setBrandLogo(_brand, name);
  }

  Future<void> _delete() async {
    final ok = await confirmListDelete(
        context,
        _brand,
        'Existing fill-ups and pumps keep this brand on their record; it just '
        "won't be offered for new fill-ups.");
    if (!ok) return;
    await deleteBrand(_brand);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _addGrade() async {
    final name = await showAddFuelTypeDialog(context);
    if (name == null || name.trim().isEmpty) return;
    if (!await addGrade(_brand, name) && mounted) {
      _snack('"${name.trim()}" already exists.');
    }
    await _load();
  }

  Future<void> _renameGrade(String from) async {
    final name = await showAddFuelTypeDialog(context,
        title: 'Rename fuel grade', initial: from);
    if (name == null || name.trim().isEmpty || name.trim() == from) return;
    final n = await renameGrade(_brand, from, name);
    if (mounted) _snack(n < 0 ? '"${name.trim()}" already exists.' : _updated(n));
    await _load();
  }

  Future<void> _deleteGrade(String grade) async {
    final ok = await confirmListDelete(
        context,
        grade,
        'Existing fill-ups keep this grade on their record; it just '
        "won't be offered for new fill-ups.");
    if (!ok) return;
    await deleteGrade(_brand, grade);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(_brand)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          ValueListenableBuilder<Map<String, String>>(
            valueListenable: brandLogos,
            builder: (context, logos, _) => settingsGroup([
              SettingsRow(
                icon: Icons.image_outlined,
                label: logos.containsKey(_brand) ? 'Change logo' : 'Use your own logo',
                trailing: BrandLogo(brandName: _brand, size: 28),
                onTap: _changeLogo,
              ),
              if (logos.containsKey(_brand))
                SettingsRow(
                  icon: Icons.undo,
                  label: 'Remove your logo',
                  onTap: () => setBrandLogo(_brand, null),
                ),
              SettingsRow(
                icon: Icons.edit_outlined,
                label: 'Rename brand',
                onTap: _rename,
              ),
            ]),
          ),
          const SizedBox(height: 24),
          sectionHeader('Fuel grades'),
          const SizedBox(height: 12),
          editableListCard(
            items: _grades,
            accent: colors.primary,
            addLabel: 'Add fuel grade',
            onAdd: _addGrade,
            onRename: _renameGrade,
            onDelete: _deleteGrade,
          ),
          const SizedBox(height: 24),
          if (_brandCount > 1)
            OutlinedButton(
              onPressed: _delete,
              style: OutlinedButton.styleFrom(
                foregroundColor: colors.danger,
                side: BorderSide(color: colors.danger.withValues(alpha: 0.35)),
                minimumSize: const Size.fromHeight(48),
              ),
              child: const Text('Delete brand'),
            ),
        ],
      ),
    );
  }
}
