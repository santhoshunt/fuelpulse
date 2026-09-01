import 'package:flutter/material.dart';
import '../db/database_helper.dart';
import '../models/fuel_log.dart';
import '../utils/constants.dart';
import '../utils/cost_calculator.dart';
import '../utils/fuel_type_manager.dart';
import '../utils/pump_brand_manager.dart';
import '../widgets/add_fuel_type_dialog.dart';
import '../widgets/brand_badge.dart';
import '../widgets/mode_switch.dart';
import '../widgets/option_picker.dart';

class AddEntryScreen extends StatefulWidget {
  const AddEntryScreen({super.key});

  @override
  State<AddEntryScreen> createState() => _AddEntryScreenState();
}

class _AddEntryScreenState extends State<AddEntryScreen> {
  final _db = DatabaseHelper();
  final _formKey = GlobalKey<FormState>();

  bool _isKmMode = false;
  bool _kmModeEnabled = false;
  FuelLog? _lastLog;

  final _odoController = TextEditingController();
  final _litersController = TextEditingController();
  final _notesController = TextEditingController();
  final _priceController = TextEditingController();
  final _costController = TextEditingController();

  List<String> _pumpBrands = List.of(kDefaultPumpBrands);
  String _selectedBrand = 'Shell';
  bool _fullTank = true;
  bool _saving = false;

  List<String> _fuelTypes = [kDefaultFuelType];
  String _selectedFuelType = kDefaultFuelType;

  // Guards against listener ping-pong while one cost field updates the other.
  bool _syncingCost = false;
  // Which cost field the user typed last — litres edits recompute the OTHER one.
  String _lastCostEdited = 'price';

  @override
  void initState() {
    super.initState();
    _loadLastEntry();
    _priceController.addListener(_onPriceChanged);
    _costController.addListener(_onCostChanged);
    _litersController.addListener(_onLitersChangedForCost);
  }

  Future<void> _loadLastEntry() async {
    try {
      final count = await _db.getLogCount();
      final last = await _db.getLastLog();
      final types = await loadFuelTypes();
      final brands = await loadPumpBrands();
      setState(() {
        _kmModeEnabled = count > 0;
        _lastLog = last;
        _fuelTypes = types;
        if (!types.contains(_selectedFuelType)) {
          _selectedFuelType = types.first;
        }
        _pumpBrands = brands;
        if (!brands.contains(_selectedBrand)) {
          _selectedBrand = brands.first;
        }
      });
    } catch (e) {
      debugPrint('Error loading last entry: $e');
    }
  }

  @override
  void dispose() {
    _odoController.dispose();
    _litersController.dispose();
    _notesController.dispose();
    _priceController.dispose();
    _costController.dispose();
    super.dispose();
  }

  void _onPriceChanged() {
    if (_syncingCost) return;
    _lastCostEdited = 'price';
    _syncingCost = true;
    if (_priceController.text.trim().isEmpty) {
      // A derived total must not outlive the price it came from.
      _costController.text = '';
    } else {
      final total = computeTotalCost(
        double.tryParse(_priceController.text.trim()),
        double.tryParse(_litersController.text.trim()),
      );
      if (total != null) _costController.text = total.toStringAsFixed(2);
    }
    _syncingCost = false;
  }

  void _onCostChanged() {
    if (_syncingCost) return;
    _lastCostEdited = 'total';
    _syncingCost = true;
    if (_costController.text.trim().isEmpty) {
      _priceController.text = '';
    } else {
      final price = computePricePerLitre(
        double.tryParse(_costController.text.trim()),
        double.tryParse(_litersController.text.trim()),
      );
      if (price != null) _priceController.text = price.toStringAsFixed(2);
    }
    _syncingCost = false;
  }

  void _onLitersChangedForCost() {
    if (_syncingCost) return;
    final liters = double.tryParse(_litersController.text.trim());
    if (liters == null || liters <= 0) return;
    _syncingCost = true;
    if (_lastCostEdited == 'price') {
      final total = computeTotalCost(
          double.tryParse(_priceController.text.trim()), liters);
      if (total != null) _costController.text = total.toStringAsFixed(2);
    } else {
      final price = computePricePerLitre(
          double.tryParse(_costController.text.trim()), liters);
      if (price != null) _priceController.text = price.toStringAsFixed(2);
    }
    _syncingCost = false;
  }

  String? _validateOptionalMoney(String? v) {
    if (v == null || v.trim().isEmpty) return null;
    final val = double.tryParse(v.trim());
    if (val == null || val < 0) return 'Invalid';
    return null;
  }

  Future<void> _pickFuelType() async {
    final result = await showOptionPicker<String>(
      context: context,
      title: 'Fuel Type',
      options: _fuelTypes
          .map((t) => PickerOption(value: t, label: t))
          .toList(),
      selected: _selectedFuelType,
      actionLabel: 'Add fuel type',
    );
    if (!mounted || result == null) return;
    if (result is PickerPicked<String>) {
      setState(() => _selectedFuelType = result.value);
      return;
    }
    // Footer action: add a new type, then select it.
    final name = await showAddFuelTypeDialog(context);
    if (name == null || name.trim().isEmpty) return;
    final added = await addFuelType(name);
    final types = await loadFuelTypes();
    final match =
        types.where((t) => t.toLowerCase() == name.trim().toLowerCase());
    if (!added && match.isNotEmpty && mounted) {
      _showSnack('"${match.first}" already exists.');
    }
    if (!mounted) return;
    setState(() {
      _fuelTypes = types;
      if (match.isNotEmpty) _selectedFuelType = match.first;
    });
  }

  Future<void> _pickBrand() async {
    final result = await showOptionPicker<String>(
      context: context,
      title: 'Pump Brand',
      options: _pumpBrands
          .map((b) => PickerOption(
                value: b,
                label: b,
                leading: BrandBadge(brandName: b, showLabel: false, size: 24),
              ))
          .toList(),
      selected: _selectedBrand,
      actionLabel: 'Add pump brand',
    );
    if (!mounted || result == null) return;
    if (result is PickerPicked<String>) {
      setState(() => _selectedBrand = result.value);
      return;
    }
    // Footer action: add a new brand, then select it.
    final name = await showAddFuelTypeDialog(context,
        title: 'Add Pump Brand', hint: 'e.g. Reliance');
    if (name == null || name.trim().isEmpty) return;
    final added = await addPumpBrand(name);
    final brands = await loadPumpBrands();
    final match =
        brands.where((b) => b.toLowerCase() == name.trim().toLowerCase());
    if (!added && match.isNotEmpty && mounted) {
      _showSnack('"${match.first}" already exists.');
    }
    if (!mounted) return;
    setState(() {
      _pumpBrands = brands;
      if (match.isNotEmpty) _selectedBrand = match.first;
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_saving) return;

    int odometer;
    if (_isKmMode) {
      final km = int.tryParse(_odoController.text.trim()) ?? 0;
      odometer = (_lastLog?.odometer ?? 0) + km;
    } else {
      odometer = int.tryParse(_odoController.text.trim()) ?? 0;
    }

    final liters = double.tryParse(_litersController.text.trim()) ?? 0;

    // Backward odometer warning
    if (!_isKmMode && _lastLog != null && odometer < _lastLog!.odometer) {
      final proceed = await _showBackwardOdoWarning();
      if (!proceed) return;
    }

    setState(() => _saving = true);

    try {
      final log = FuelLog(
        id: FuelLog.generateId(),
        timestamp: DateTime.now().toIso8601String(),
        odometer: odometer,
        liters: liters,
        pumpBrand: _selectedBrand,
        fullTank: _fullTank,
        notes: _notesController.text.trim(),
        fuelType: _selectedFuelType,
        totalCost: double.tryParse(_costController.text.trim()),
        pricePerLitre: double.tryParse(_priceController.text.trim()),
      );

      await _db.insertLog(log);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      debugPrint('Error saving entry: $e');
      if (mounted) {
        setState(() => _saving = false);
        _showSnack('Failed to save: $e');
      }
    }
  }

  Future<bool> _showBackwardOdoWarning() async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Odometer Warning'),
            content: const Text(
                'New odometer is less than last reading. Save anyway?'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel')),
              ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Save Anyway')),
            ],
          ),
        ) ??
        false;
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Fill-up'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Mode switch
              ModeSwitch(
                isKmMode: _isKmMode,
                kmModeEnabled: _kmModeEnabled,
                onChanged: (km) => setState(() => _isKmMode = km),
              ),
              const SizedBox(height: 20),

              // Odometer / KM input
              TextFormField(
                controller: _odoController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: _isKmMode ? 'KM Driven' : 'Odometer (km)',
                  prefixIcon: const Icon(Icons.speed),
                  suffixText: 'km',
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return _isKmMode
                        ? 'Enter distance driven'
                        : 'Enter odometer reading';
                  }
                  if (int.tryParse(v.trim()) == null) return 'Invalid number';
                  return null;
                },
              ),
              if (_isKmMode && _lastLog != null) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 6, left: 4),
                  child: Text(
                    'Last odometer: ${_lastLog!.odometer} km',
                    style:
                        const TextStyle(color: kTextMuted, fontSize: 12),
                  ),
                ),
              ],
              const SizedBox(height: 16),

              // Liters
              TextFormField(
                controller: _litersController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Liters',
                  prefixIcon: Icon(Icons.local_gas_station),
                  suffixText: 'L',
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Enter liters';
                  final val = double.tryParse(v.trim());
                  if (val == null || val <= 0) return 'Must be > 0';
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Cost (optional) — the two fields keep each other in sync
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _priceController,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Price (₹/L)',
                        prefixIcon: Icon(Icons.sell_outlined),
                      ),
                      validator: _validateOptionalMoney,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _costController,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Total (₹)',
                        prefixIcon: Icon(Icons.currency_rupee),
                      ),
                      validator: _validateOptionalMoney,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Fuel type picker
              PickerField(
                label: 'Fuel Type',
                icon: Icons.local_fire_department_outlined,
                onTap: _pickFuelType,
                child: Text(
                  _selectedFuelType,
                  style: const TextStyle(color: kTextPrimary, fontSize: 16),
                ),
              ),
              const SizedBox(height: 16),

              // Brand picker
              PickerField(
                label: 'Pump Brand',
                icon: Icons.ev_station,
                onTap: _pickBrand,
                child: Row(
                  children: [
                    BrandBadge(
                        brandName: _selectedBrand,
                        showLabel: false,
                        size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _selectedBrand,
                        style: const TextStyle(
                            color: kTextPrimary, fontSize: 16),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Notes
              TextFormField(
                controller: _notesController,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Notes (optional)',
                  prefixIcon: Icon(Icons.note_outlined),
                ),
              ),
              const SizedBox(height: 16),

              // Full tank switch
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.white.withValues(alpha: 0.06),
                      Colors.white.withValues(alpha: 0.02),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(14),
                  border:
                      Border.all(color: Colors.white.withValues(alpha: 0.1)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.local_gas_station_outlined,
                        color: kTextSecondary, size: 20),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Full Tank',
                        style:
                            TextStyle(color: kTextPrimary, fontSize: 15),
                      ),
                    ),
                    Switch(
                      value: _fullTank,
                      onChanged: (v) => setState(() => _fullTank = v),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),

              // Save button
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    elevation: 6,
                    shadowColor: accent.withValues(alpha: 0.4),
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Save Entry',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
