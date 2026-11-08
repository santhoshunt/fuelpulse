import 'package:flutter/material.dart';

import '../db/database_helper.dart';
import '../models/pump.dart';
import '../theme/app_colors.dart';
import '../utils/brand_grades.dart';
import '../utils/page_routes.dart';
import '../widgets/brand_logo.dart';
import 'brands_screen.dart';
import 'settings/settings_widgets.dart';

/// The petrol pumps you fill up at, brand first, with how often each was
/// used. The starred one is pre-selected in the refill form.
class PumpsScreen extends StatefulWidget {
  const PumpsScreen({super.key});

  @override
  State<PumpsScreen> createState() => _PumpsScreenState();
}

class _PumpsScreenState extends State<PumpsScreen> {
  final _db = DatabaseHelper();
  List<Pump> _pumps = const [];
  Map<String, int> _uses = const {};
  int _brandCount = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final pumps = await _db.getPumps();
    final uses = await _db.pumpUseCounts();
    final brands = await loadBrandGrades();
    if (!mounted) return;
    setState(() {
      _pumps = pumps;
      _uses = uses;
      _brandCount = brands.length;
    });
  }

  Future<void> _edit([Pump? pump]) async {
    await showPumpEditor(context, pump: pump);
    await _load();
  }

  Future<void> _star(Pump p) async {
    await _db.savePump(p.copyWith(isFavourite: !p.isFavourite));
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Petrol pumps'),
        actions: [
          IconButton(
            tooltip: 'Add petrol pump',
            icon: const Icon(Icons.add),
            onPressed: () => _edit(),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          settingsGroup([
            SettingsRow(
              icon: Icons.local_offer_outlined,
              label: 'Brands and fuel grades',
              trailing: Text('$_brandCount',
                  style: TextStyle(color: colors.textSecondary, fontSize: 15)),
              onTap: () async {
                await Navigator.push(context,
                    SmoothPageRoute(page: const BrandsScreen()));
                await _load();
              },
            ),
          ]),
          const SizedBox(height: 20),
          if (_pumps.isEmpty)
            Text(
                'No pumps yet. Add the ones you use, or pick a brand in the '
                'refill form and its pump is added for you.',
                style: TextStyle(color: colors.textSecondary, fontSize: 14))
          else
            settingsGroup([
              for (final p in _pumps)
                InkWell(
                  onTap: () => _edit(p),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 4, 10),
                    child: Row(
                      children: [
                        BrandLogo(brandName: p.brand, size: 40),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(p.brand,
                                  style: TextStyle(
                                      color: colors.textPrimary,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600)),
                              Text(
                                  [
                                    if (p.name.isNotEmpty) p.name,
                                    _refills(_uses[p.id] ?? 0),
                                  ].join(' · '),
                                  style: TextStyle(
                                      color: colors.textSecondary,
                                      fontSize: 13)),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: p.isFavourite ? 'Unstar' : 'Star',
                          icon: Icon(
                              p.isFavourite ? Icons.star : Icons.star_border,
                              color: p.isFavourite
                                  ? colors.secondary
                                  : colors.textSecondary),
                          onPressed: () => _star(p),
                        ),
                      ],
                    ),
                  ),
                ),
            ]),
          const SizedBox(height: 12),
          Text('The starred pump is pre-selected when you add a refill.',
              style: TextStyle(color: colors.textSecondary, fontSize: 13)),
        ],
      ),
    );
  }

  static String _refills(int n) => n == 1 ? '1 refill' : '$n refills';
}

/// Adds or edits a pump in a bottom sheet. Returns the saved pump, or null
/// when cancelled or deleted.
Future<Pump?> showPumpEditor(BuildContext context, {Pump? pump}) async {
  final brands = (await loadBrandGrades()).keys.toList();
  if (pump != null && !brands.contains(pump.brand)) brands.insert(0, pump.brand);
  if (!context.mounted) return null;
  return showModalBottomSheet<Pump>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => _PumpEditor(pump: pump, brands: brands),
  );
}

class _PumpEditor extends StatefulWidget {
  final Pump? pump;
  final List<String> brands;

  const _PumpEditor({required this.pump, required this.brands});

  @override
  State<_PumpEditor> createState() => _PumpEditorState();
}

class _PumpEditorState extends State<_PumpEditor> {
  late final _name = TextEditingController(text: widget.pump?.name ?? '');
  late String _brand = widget.pump?.brand ?? widget.brands.first;
  late bool _favourite = widget.pump?.isFavourite ?? false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final old = widget.pump;
    final p = old == null
        ? Pump(
            id: Pump.generateId(),
            name: _name.text.trim(),
            brand: _brand,
            isFavourite: _favourite,
            createdAt: DateTime.now().toIso8601String(),
          )
        : old.copyWith(
            name: _name.text.trim(), brand: _brand, isFavourite: _favourite);
    await DatabaseHelper().savePump(p);
    if (mounted) Navigator.pop(context, p);
  }

  Future<void> _delete() async {
    await DatabaseHelper().deletePump(widget.pump!.id);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 20, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.pump == null ? 'Add petrol pump' : 'Edit petrol pump',
              style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _brand,
            decoration: const InputDecoration(labelText: 'Brand'),
            items: [
              for (final b in widget.brands)
                DropdownMenuItem(
                  value: b,
                  child: Row(
                    children: [
                      BrandLogo(brandName: b, size: 26),
                      const SizedBox(width: 10),
                      Text(b),
                    ],
                  ),
                ),
            ],
            onChanged: (b) => setState(() => _brand = b ?? _brand),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
                labelText: 'Station or area (optional)',
                hintText: 'e.g. MG Road'),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Pre-select in the refill form'),
            value: _favourite,
            onChanged: (v) => setState(() => _favourite = v),
          ),
          const SizedBox(height: 8),
          FilledButton(onPressed: _save, child: const Text('Save pump')),
          if (widget.pump != null)
            TextButton(
              onPressed: _delete,
              style: TextButton.styleFrom(foregroundColor: colors.danger),
              child: const Text('Delete pump'),
            ),
        ],
      ),
    );
  }
}
