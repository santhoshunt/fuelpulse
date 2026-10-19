import 'package:flutter/material.dart';
import '../../utils/constants.dart';
import '../../utils/fuel_type_manager.dart' as ftm;
import '../../utils/pump_brand_manager.dart' as pbm;
import '../../widgets/add_fuel_type_dialog.dart';
import '../../widgets/brand_badge.dart';
import 'settings_widgets.dart';

/// Fuel Types and Pump Brands: the two shared name lists offered in the
/// fill-up form.
class ListsSection extends StatefulWidget {
  const ListsSection({super.key});

  @override
  State<ListsSection> createState() => _ListsSectionState();
}

class _ListsSectionState extends State<ListsSection> {
  List<String> _fuelTypes = [kDefaultFuelType];
  List<String> _pumpBrands = List.of(kDefaultPumpBrands);

  @override
  void initState() {
    super.initState();
    _loadFuelTypes();
    _loadPumpBrands();
  }

  void _showSnack(String msg) => showSettingsSnack(context, msg);

  Future<void> _loadFuelTypes() async {
    final types = await ftm.loadFuelTypes();
    if (mounted) setState(() => _fuelTypes = types);
  }

  Future<void> _loadPumpBrands() async {
    final brands = await pbm.loadPumpBrands();
    if (mounted) setState(() => _pumpBrands = brands);
  }

  Future<void> _addFuelType() async {
    final name = await showAddFuelTypeDialog(context);
    if (name == null || name.trim().isEmpty) return;
    final added = await ftm.addFuelType(name);
    if (!added && mounted) {
      _showSnack('"${name.trim()}" already exists.');
    }
    await _loadFuelTypes();
  }

  Future<void> _renameFuelType(String from) async {
    final name = await showAddFuelTypeDialog(context,
        title: 'Rename Fuel Type', initial: from);
    if (name == null || name.trim().isEmpty || name.trim() == from) return;
    final updated = await ftm.renameFuelType(from, name);
    if (mounted) {
      if (updated < 0) {
        _showSnack('"${name.trim()}" already exists.');
      } else {
        _showSnack('Renamed. Updated $updated existing '
            '${updated == 1 ? 'entry' : 'entries'}.');
      }
    }
    await _loadFuelTypes();
  }

  Future<void> _deleteFuelType(String name) async {
    final confirm = await confirmListDelete(
        context,
        name,
        'Existing entries keep this label on their record; it just '
        "won't be offered for new fill-ups.");
    if (!confirm) return;
    await ftm.deleteFuelType(name);
    await _loadFuelTypes();
  }

  Future<void> _addPumpBrand() async {
    final name = await showAddFuelTypeDialog(context,
        title: 'Add Pump Brand', hint: 'e.g. Reliance');
    if (name == null || name.trim().isEmpty) return;
    final added = await pbm.addPumpBrand(name);
    if (!added && mounted) {
      _showSnack('"${name.trim()}" already exists.');
    }
    await _loadPumpBrands();
  }

  Future<void> _renamePumpBrand(String from) async {
    final name = await showAddFuelTypeDialog(context,
        title: 'Rename Pump Brand', initial: from, hint: 'e.g. Reliance');
    if (name == null || name.trim().isEmpty || name.trim() == from) return;
    final updated = await pbm.renamePumpBrand(from, name);
    if (mounted) {
      if (updated < 0) {
        _showSnack('"${name.trim()}" already exists.');
      } else {
        _showSnack('Renamed. Updated $updated existing '
            '${updated == 1 ? 'entry' : 'entries'}.');
      }
    }
    await _loadPumpBrands();
  }

  Future<void> _deletePumpBrand(String name) async {
    final confirm = await confirmListDelete(
        context,
        name,
        'Existing entries keep this brand on their record; it just '
        "won't be offered for new fill-ups.");
    if (!confirm) return;
    await pbm.deletePumpBrand(name);
    await _loadPumpBrands();
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Fuel Types ───────────────────────────────
        sectionHeader('Fuel Types'),
        const SizedBox(height: 4),
        const Text(
          'Offered in the fill-up form. Renaming updates existing '
          'entries; deleting only removes it from the list.',
          style: TextStyle(color: kTextMuted, fontSize: 12),
        ),
        const SizedBox(height: 12),
        editableListCard(
          items: _fuelTypes,
          accent: accent,
          addLabel: 'Add fuel type',
          onAdd: _addFuelType,
          onRename: _renameFuelType,
          onDelete: _deleteFuelType,
        ),
        const SizedBox(height: 32),

        // ── Pump Brands ──────────────────────────────
        sectionHeader('Pump Brands'),
        const SizedBox(height: 4),
        const Text(
          'Offered in the fill-up form. Renaming updates existing '
          'entries; deleting only removes it from the list.',
          style: TextStyle(color: kTextMuted, fontSize: 12),
        ),
        const SizedBox(height: 12),
        editableListCard(
          items: _pumpBrands,
          accent: accent,
          addLabel: 'Add pump brand',
          onAdd: _addPumpBrand,
          onRename: _renamePumpBrand,
          onDelete: _deletePumpBrand,
          leadingBuilder: (name) =>
              BrandBadge(brandName: name, showLabel: false, size: 22),
        ),
      ],
    );
  }
}
