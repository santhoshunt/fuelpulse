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

class EditEntryScreen extends StatefulWidget {
  final String logId;

  const EditEntryScreen({super.key, required this.logId});

  @override
  State<EditEntryScreen> createState() => _EditEntryScreenState();
}

class _EditEntryScreenState extends State<EditEntryScreen> {
  final _db = DatabaseHelper();
  final _formKey = GlobalKey<FormState>();

  bool _isKmMode = false;
  FuelLog? _original;
  int? _prevOdometer;

  final _odoController = TextEditingController();
  final _litersController = TextEditingController();
  final _notesController = TextEditingController();
  final _priceController = TextEditingController();
  final _costController = TextEditingController();

  List<String> _pumpBrands = List.of(kDefaultPumpBrands);
  String _selectedBrand = 'Shell';
  bool _fullTank = true;
  bool _saving = false;
  bool _loading = true;

  List<String> _fuelTypes = [kDefaultFuelType];
  String _selectedFuelType = kDefaultFuelType;

  // Guards against listener ping-pong while one cost field updates the other.
  bool _syncingCost = false;
  // Which cost field the user typed last — litres edits recompute the OTHER
  // one. Defaults to 'total' here: the receipt total is what people verify.
  String _lastCostEdited = 'total';

  @override
  void initState() {
    super.initState();
    _loadData();
    _priceController.addListener(_onPriceChanged);
    _costController.addListener(_onCostChanged);
    _litersController.addListener(_onLitersChangedForCost);
  }

  Future<void> _loadData() async {
    final log = await _db.getLogById(widget.logId);
    if (log == null) {
      if (mounted) Navigator.pop(context);
      return;
    }

    // Find previous log for KM mode calculation
    final chrono = await _db.getAllLogsChrono();
    final idx = chrono.indexWhere((l) => l.id == log.id);
    int? prevOdo;
    if (idx > 0) prevOdo = chrono[idx - 1].odometer;

    final types = await loadFuelTypes();
    // Tolerate a type that was deleted/renamed away — the log keeps its
    // string, so inject it locally for display.
    if (!types.contains(log.fuelType)) types.insert(0, log.fuelType);

    final brands = await loadPumpBrands();
    if (!brands.contains(log.pumpBrand)) brands.insert(0, log.pumpBrand);

    setState(() {
      _original = log;
      _prevOdometer = prevOdo;
      // Prefill without triggering the cost-linking listeners.
      _syncingCost = true;
      _odoController.text = log.odometer.toString();
      _litersController.text = log.liters.toString();
      _priceController.text = log.pricePerLitre?.toString() ?? '';
      _costController.text = log.totalCost?.toString() ?? '';
      _syncingCost = false;
      _notesController.text = log.notes;
      _fullTank = log.fullTank;
      _fuelTypes = types;
      _selectedFuelType = log.fuelType;
      _pumpBrands = brands;
      _selectedBrand = log.pumpBrand;
      _loading = false;
    });
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
      // Keep an orphaned type (deleted/renamed away) displayable.
      if (!types.contains(_selectedFuelType)) {
        types.insert(0, _selectedFuelType);
      }
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
      // Keep an orphaned brand (deleted/renamed away) displayable.
      if (!brands.contains(_selectedBrand)) {
        brands.insert(0, _selectedBrand);
      }
      _pumpBrands = brands;
      if (match.isNotEmpty) _selectedBrand = match.first;
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_saving || _original == null) return;

    // Confirmation dialog
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Save Changes'),
        content: const Text('Save changes to this entry?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save')),
        ],
      ),
    );
    if (confirm != true) return;

    int odometer;
    if (_isKmMode && _prevOdometer != null) {
      final km = int.tryParse(_odoController.text.trim()) ?? 0;
      odometer = _prevOdometer! + km;
    } else {
      odometer = int.tryParse(_odoController.text.trim()) ?? 0;
    }

    final liters = double.tryParse(_litersController.text.trim()) ?? 0;

    setState(() => _saving = true);

    final newTotal = double.tryParse(_costController.text.trim());
    final newPrice = double.tryParse(_priceController.text.trim());

    final updated = _original!.copyWith(
      odometer: odometer,
      liters: liters,
      pumpBrand: _selectedBrand,
      fullTank: _fullTank,
      notes: _notesController.text.trim(),
      fuelType: _selectedFuelType,
      totalCost: newTotal,
      clearTotalCost: newTotal == null,
      pricePerLitre: newPrice,
      clearPricePerLitre: newPrice == null,
    );

    await _db.updateLog(updated);
    if (mounted) Navigator.pop(context, true);
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _switchMode(bool km) {
    if (_original == null) return;
    setState(() {
      _isKmMode = km;
      if (km && _prevOdometer != null) {
        // Convert current odometer to km driven
        final currentOdo =
            int.tryParse(_odoController.text.trim()) ?? _original!.odometer;
        _odoController.text = (currentOdo - _prevOdometer!).toString();
      } else if (!km && _prevOdometer != null) {
        // Convert km driven back to odometer
        final kmDriven = int.tryParse(_odoController.text.trim()) ?? 0;
        _odoController.text = (_prevOdometer! + kmDriven).toString();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Edit Fill-up')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Fill-up'),
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
                kmModeEnabled: _prevOdometer != null,
                onChanged: _switchMode,
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
                  if (v == null || v.trim().isEmpty) return 'Required';
                  if (int.tryParse(v.trim()) == null) return 'Invalid number';
                  return null;
                },
              ),
              if (_isKmMode && _prevOdometer != null) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 6, left: 4),
                  child: Text(
                    'Previous odometer: $_prevOdometer km',
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
                  color: Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(14),
                  border:
                      Border.all(color: Colors.white.withValues(alpha: 0.08)),
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
                      : const Text('Save Changes',
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
