import 'package:flutter/material.dart';
import '../db/database_helper.dart';
import '../models/fuel_log.dart';
import '../utils/constants.dart';
import '../widgets/mode_switch.dart';

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
  final _customBrandController = TextEditingController();

  String _selectedBrand = 'Shell';
  bool _isOtherBrand = false;
  bool _fullTank = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadLastEntry();
  }

  Future<void> _loadLastEntry() async {
    try {
      final count = await _db.getLogCount();
      final last = await _db.getLastLog();
      setState(() {
        _kmModeEnabled = count > 0;
        _lastLog = last;
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
    _customBrandController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_saving) return;

    final brand =
        _isOtherBrand ? _customBrandController.text.trim() : _selectedBrand;
    if (brand.isEmpty) {
      _showSnack('Please enter a brand name.');
      return;
    }

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
        pumpBrand: brand,
        fullTank: _fullTank,
        notes: _notesController.text.trim(),
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

              // Brand dropdown
              DropdownButtonFormField<String>(
                initialValue: _selectedBrand,
                decoration: const InputDecoration(
                  labelText: 'Pump Brand',
                  prefixIcon: Icon(Icons.ev_station),
                ),
                dropdownColor: const Color(0xFF1A1A1A),
                items: kBrandDropdownItems.map((b) {
                  final config =
                      b == 'Other' ? kOtherBrand : getBrandConfig(b);
                  return DropdownMenuItem(
                    value: b,
                    child: Row(
                      children: [
                        Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            color: config.background,
                            borderRadius: BorderRadius.circular(5),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            config.abbreviation,
                            style: TextStyle(
                              color: config.textColor,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(b),
                      ],
                    ),
                  );
                }).toList(),
                onChanged: (v) {
                  setState(() {
                    _selectedBrand = v ?? 'Shell';
                    _isOtherBrand = v == 'Other';
                  });
                },
              ),
              if (_isOtherBrand) ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: _customBrandController,
                  decoration: const InputDecoration(
                    labelText: 'Custom Brand Name',
                    prefixIcon: Icon(Icons.edit),
                  ),
                  validator: (v) {
                    if (_isOtherBrand && (v == null || v.trim().isEmpty)) {
                      return 'Enter brand name';
                    }
                    return null;
                  },
                ),
              ],
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
