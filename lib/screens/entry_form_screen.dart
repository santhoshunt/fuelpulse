import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import '../db/database_helper.dart';
import '../models/attachment.dart';
import '../models/fuel_log.dart';
import '../models/pump.dart';
import '../models/trip.dart';
import '../models/vehicle.dart';
import '../services/photo_scan.dart';
import '../services/service_reminders.dart';
import '../services/update_installer.dart';
import '../theme/app_colors.dart';
import '../utils/constants.dart';
import '../utils/cost_calculator.dart';
import '../utils/brand_grades.dart';
import '../widgets/add_fuel_type_dialog.dart';
import '../widgets/bills_section.dart';
import '../widgets/brand_logo.dart';
import '../widgets/mode_switch.dart';
import '../widgets/option_picker.dart';
import 'pumps_screen.dart';
import 'scan_photos_screen.dart';
import 'trip_sheets.dart';

/// Add or edit a fill-up. One form serves both so the fields, cost sync and
/// pickers stay identical between the two flows.
class EntryFormScreen extends StatefulWidget {
  /// Null opens the form to add a new fill-up; an id opens that log for editing.
  final String? logId;

  /// The vehicle a new fill-up is added to. Required when adding; editing
  /// uses the log's own vehicle.
  final String? vehicleId;

  /// Photo reads to fill a new fill-up with, from [ScanPhotosScreen].
  final ScanOutcome? prefill;

  const EntryFormScreen({super.key, this.logId, this.vehicleId, this.prefill})
      : assert(logId != null || vehicleId != null,
            'Adding a fill-up needs the vehicle it belongs to');

  @override
  State<EntryFormScreen> createState() => _EntryFormScreenState();
}

class _EntryFormScreenState extends State<EntryFormScreen> {
  final _db = DatabaseHelper();
  final _formKey = GlobalKey<FormState>();

  bool get _isEdit => widget.logId != null;

  bool _isKmMode = false;
  FuelLog? _original;

  /// Named in the title, so a fill-up is never logged to the wrong vehicle
  /// unnoticed.
  Vehicle? _vehicle;

  /// Odometer that KM mode counts from: the latest log when adding, the log
  /// just before this one when editing. Null disables KM mode.
  int? _baseOdometer;

  /// The vehicle's logs oldest first, without the one being edited: the
  /// neighbours a changed date is checked against.
  List<FuelLog> _others = const [];

  /// When the fill-up happened. Defaults to now when adding.
  DateTime _when = DateTime.now();

  /// Set once the date is changed by hand, so an edit that leaves it alone
  /// writes the stored timestamp back unchanged.
  bool _whenTouched = false;

  /// Odometer of the next fill-up after [_when], for the warning when a
  /// backdated fill-up reads higher than what came after it.
  int? _nextOdometer;

  final _odoController = TextEditingController();
  final _litersController = TextEditingController();
  final _notesController = TextEditingController();
  final _priceController = TextEditingController();
  final _costController = TextEditingController();

  List<Pump> _pumps = const [];

  /// The pump chosen; null when a brand without a pump was picked (its
  /// pump is created on save) or an edited log's pump was deleted.
  Pump? _pump;
  String _selectedBrand = 'Shell';
  Map<String, List<String>> _grades = const {};
  bool _fullTank = true;
  bool _saving = false;
  List<Attachment> _bills = const [];
  List<Attachment> _billsBefore = const [];

  /// Set once saved, so closing the form keeps the receipts it added.
  bool _saved = false;

  /// The trip this fill-up can belong to: the vehicle's trip on now, or
  /// when editing, the trip the fill-up is already on.
  Trip? _trip;
  bool _onTrip = true;
  bool _tripEndsHere = false;

  /// The price text the chosen pump filled in, and the date of the fill-up
  /// it came from. A price typed or scanned since differs, and stays.
  String? _pumpPrice;
  DateTime? _pumpPriceAt;
  late bool _loading = _isEdit;

  String _selectedFuelType = kDefaultFuelType;

  /// The brand's grades, plus the selected one when an edited log has a
  /// grade no longer offered, so it still shows.
  List<String> get _gradeChoices {
    final g = List.of(_grades[_selectedBrand] ?? const [kDefaultFuelType]);
    if (!g.contains(_selectedFuelType)) g.insert(0, _selectedFuelType);
    return g;
  }

  // Guards against listener ping-pong while one cost field updates the other.
  bool _syncingCost = false;
  // Which cost field the user typed last — litres edits recompute the OTHER
  // one. Defaults to 'total' when editing: the receipt total is what people
  // verify.
  late String _lastCostEdited = _isEdit ? 'total' : 'price';

  // Photo pre-fill: what the last scan read, and the notes it left.
  final List<ScanResult> _scans = [];
  final List<String> _scanNotes = [];
  int _scanFilled = 0;
  bool _whenFromPhoto = false;
  bool _suggestionUsed = false;
  // Marks the fields a photo filled until the user edits them.
  bool _odoFromPhoto = false;
  bool _fuelFromPhoto = false;

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      _loadForEdit();
    } else {
      _loadForAdd();
    }
    _priceController.addListener(_onPriceChanged);
    _costController.addListener(_onCostChanged);
    _litersController.addListener(_onLitersChangedForCost);
  }

  Future<void> _loadForAdd() async {
    try {
      final vehicle = await _db.getVehicle(widget.vehicleId!);
      final last = await _db.getLastLog(widget.vehicleId!);
      final chrono = await _db.getAllLogsChrono(widget.vehicleId!);
      final grades = await loadBrandGrades();
      final pumps = await _db.getPumps();
      final trip = await _db.activeTrip(widget.vehicleId!);
      if (!mounted) return;
      setState(() {
        _trip = trip;
        _vehicle = vehicle;
        _baseOdometer = last?.odometer;
        _others = chrono;
        _grades = grades;
        _pumps = pumps;
        // The starred pump, else the first, else the first brand.
        final pump = pumps.where((p) => p.isFavourite).firstOrNull ??
            pumps.firstOrNull;
        _choose(pump,
            brand: grades.containsKey(_selectedBrand)
                ? _selectedBrand
                : grades.keys.firstOrNull ?? _selectedBrand);
      });
      // Before the scan, so a scanned price wins.
      await _applyPumpPrice();
      // After the base odometer is known: a TRIP read needs it.
      final prefill = widget.prefill;
      if (prefill != null && !prefill.isEmpty) _applyOutcome(prefill);
    } catch (e) {
      debugPrint('Error loading last entry: $e');
    }
  }

  Future<void> _loadForEdit() async {
    final log = await _db.getLogById(widget.logId!);
    if (log == null) {
      if (mounted) Navigator.pop(context);
      return;
    }

    // Find previous log for KM mode calculation
    final chrono = await _db.getAllLogsChrono(log.vehicleId);
    final idx = chrono.indexWhere((l) => l.id == log.id);
    int? prevOdo;
    if (idx > 0) prevOdo = chrono[idx - 1].odometer;

    final grades = await loadBrandGrades();
    final pumps = await _db.getPumps();

    final vehicle = await _db.getVehicle(log.vehicleId);
    final bills = await _db.getAttachments('fuel', log.id);
    final trip = log.tripId != null
        ? await _db.getTrip(log.tripId!)
        : await _db.activeTrip(log.vehicleId);
    if (!mounted) return;

    setState(() {
      _original = log;
      _vehicle = vehicle;
      _bills = _billsBefore = bills;
      _trip = trip;
      _onTrip = log.tripId != null;
      _baseOdometer = prevOdo;
      _others = [...chrono]..removeWhere((l) => l.id == log.id);
      _when = DateTime.tryParse(log.timestamp) ?? DateTime.now();
      // Prefill without triggering the cost-linking listeners.
      _syncingCost = true;
      _odoController.text = log.odometer.toString();
      _litersController.text = log.liters.toString();
      _priceController.text = log.pricePerLitre?.toString() ?? '';
      _costController.text = log.totalCost?.toString() ?? '';
      _syncingCost = false;
      _notesController.text = log.notes;
      _fullTank = log.fullTank;
      // A brand or grade no longer offered still shows: the log keeps its
      // own strings.
      _grades = grades;
      _pumps = pumps;
      _pump = pumps.where((p) => p.id == log.pumpId).firstOrNull;
      _selectedBrand = log.pumpBrand;
      _selectedFuelType = log.fuelType;
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
    if (!_saved) discardBills(_bills, _billsBefore);
    super.dispose();
  }

  Future<void> _openScan() async {
    final outcome = await Navigator.push<ScanOutcome>(
      context,
      MaterialPageRoute(
          builder: (_) => ScanPhotosScreen(lastOdometer: _baseOdometer)),
    );
    if (outcome != null && !outcome.isEmpty && mounted) {
      _applyOutcome(outcome);
    }
  }

  /// Copies every read of a scan into the form and sums up what it did.
  void _applyOutcome(ScanOutcome o) {
    final photoTime = o.photoTime;
    if (photoTime != null) _setWhen(photoTime);
    setState(() {
      _scans
        ..clear()
        ..addAll([o.odometer, o.pump].whereType<ScanResult>());
      _scanNotes.clear();
      _suggestionUsed = false;
      _whenFromPhoto = photoTime != null;
      for (final r in _scans) {
        final note = _applyScan(r);
        if (note != null) _scanNotes.add(note);
      }
      final p = o.pump?.pump;
      _scanFilled = (_odoFromPhoto ? 1 : 0) +
          (_fuelFromPhoto ? 3 : (p != null && p.rateOnly ? 1 : 0)) +
          (photoTime != null ? 1 : 0);
      if (p != null && p.found && p.corrections == 0) {
        _scanNotes.insert(
            0,
            'Pump numbers agree: ${p.litres!.toStringAsFixed(2)} L × '
            '₹${p.rate!.toStringAsFixed(2)} = ₹${p.amount!.toStringAsFixed(2)}.');
      }
    });
  }
  /// Copies a scan into the form. Returns a message when nothing could be
  /// filled. Called inside setState.
  String? _applyScan(ScanResult r) {
    if (r.kind == ScanKind.odometer) {
      final o = r.odometer!;
      if (o.value == null) {
        return '${r.summary}. Enter it by hand.';
      }
      if (o.isTrip) {
        if (_baseOdometer == null) {
          return '${o.label} shows distance since the last fill-up, '
              'but this vehicle has no earlier fill-up. Enter the odometer.';
        }
        _isKmMode = true;
      } else {
        _isKmMode = false;
      }
      _odoController.text = '${o.value}';
      _odoFromPhoto = true;
      if (o.isTrip) {
        return 'The photo showed ${o.label}, which counts distance since the '
            'last refill, so the form switched to KM Travelled. Odometer '
            'becomes $_baseOdometer + ${o.value} = '
            '${_baseOdometer! + o.value!} km.';
      }
      return null;
    }
    final p = r.pump!;
    if (p.rateOnly) {
      // Through the normal listener, so a litres value already typed
      // recomputes the total.
      _priceController.text = p.rate!.toStringAsFixed(2);
      if (pumpSuggestion(p) != null) {
        return 'Only the rate was read for sure: ₹${p.rate!.toStringAsFixed(2)}/L. '
            'Check this, under the price, works out the litres.';
      }
      return 'Only the rate was read: ₹${p.rate!.toStringAsFixed(2)}/L. '
          'Enter litres or the total and the other fills in.';
    }
    if (!p.found) {
      return pumpSuggestion(p) == null
          ? "The pump numbers couldn't be read. Enter them by hand."
          : "The pump numbers didn't agree, so nothing was filled.";
    }
    // Fill all three without the cost listeners recomputing each other.
    _syncingCost = true;
    _litersController.text = p.litres!.toStringAsFixed(2);
    _priceController.text = p.rate!.toStringAsFixed(2);
    _costController.text = p.amount!.toStringAsFixed(2);
    _syncingCost = false;
    _lastCostEdited = 'total';
    _fuelFromPhoto = true;
    if (p.corrections > 0) {
      return 'Fixed ${p.corrections} misread '
          '${p.corrections == 1 ? 'digit' : 'digits'} so litres × rate '
          'matches the amount. Check them against the pump before saving.';
    }
    return null;
  }

  Future<void> _shareScanReport(ScanResult r) async {
    String version;
    try {
      version = await ChannelUpdateInstaller.instance.currentVersion();
    } catch (_) {
      version = 'unknown';
    }
    await r.share(version);
  }

  /// Opens the scan screen; shown when adding, on phones only.
  Widget _buildScanCard(AppColors colors) {
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _openScan,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: colors.primaryTint,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.photo_camera_outlined, color: colors.primary),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Scan photos to fill',
                        style: TextStyle(
                            color: colors.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w600)),
                    Text('Odometer and pump display',
                        style: TextStyle(
                            color: colors.textSecondary, fontSize: 13)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: colors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }

  /// What the last scan filled, with a Report button per photo.
  Widget _buildScanSummary(AppColors colors) {
    final photos = _scans.length;
    final ok = _scanFilled > 0;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.primaryTint,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
              ok
                  ? 'Filled $_scanFilled ${_scanFilled == 1 ? 'field' : 'fields'} '
                      'from $photos ${photos == 1 ? 'photo' : 'photos'}'
                  : 'Nothing could be filled from the '
                      '${photos == 1 ? 'photo' : 'photos'}',
              style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w600)),
          for (final n in _scanNotes) ...[
            const SizedBox(height: 4),
            Text(n, style: TextStyle(color: colors.textSecondary, fontSize: 13)),
          ],
          if (ok) ...[
            const SizedBox(height: 4),
            Text('Check the marked fields, then save.',
                style: TextStyle(color: colors.textSecondary, fontSize: 13)),
          ],
          Wrap(
            children: [
              for (final s in _scans)
                TextButton(
                  onPressed: () => _shareScanReport(s),
                  child: Text(s.kind == ScanKind.odometer
                      ? 'Report odometer read'
                      : 'Report pump read'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// When the pump numbers didn't agree: amount ÷ rate, offered as litres.
  Widget? _buildPumpCheck(AppColors colors) {
    if (_suggestionUsed) return null;
    final pump = _scans.where((s) => s.kind == ScanKind.pump).firstOrNull;
    final s = pump == null ? null : pumpSuggestion(pump.pump!);
    if (s == null) return null;
    final litres = s.litres.toStringAsFixed(2);
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(color: colors.warning.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Check this',
              style: TextStyle(
                  color: colors.warning,
                  fontSize: 14,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(
              "The pump numbers didn't agree. If the amount and rate are "
              'right, ₹${s.amount.toStringAsFixed(2)} ÷ '
              '₹${s.rate.toStringAsFixed(2)} = $litres L.',
              style: TextStyle(color: colors.textSecondary, fontSize: 13)),
          const SizedBox(height: 8),
          FilledButton.tonal(
            onPressed: () => setState(() {
              _syncingCost = true;
              _litersController.text = litres;
              _priceController.text = s.rate.toStringAsFixed(2);
              _costController.text = s.amount.toStringAsFixed(2);
              _syncingCost = false;
              _lastCostEdited = 'total';
              _fuelFromPhoto = true;
              _suggestionUsed = true;
            }),
            child: Text('Use $litres L'),
          ),
        ],
      ),
    );
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

  /// Selects [pump], or [brand] when there is no pump. Keeps the grade if
  /// the new brand sells it, else takes the brand's first grade.
  void _choose(Pump? pump, {String? brand}) {
    _pump = pump;
    _selectedBrand = pump?.brand ?? brand ?? _selectedBrand;
    final grades = _grades[_selectedBrand];
    if (grades != null &&
        grades.isNotEmpty &&
        !grades.contains(_selectedFuelType)) {
      _selectedFuelType = grades.first;
    }
  }

  /// Saved pumps first, then each brand that has no pump yet: picking one
  /// of those saves the fill-up with that brand and its pump is created.
  Future<void> _pickPump() async {
    final withPump = _pumps.map((p) => p.brand.toLowerCase()).toSet();
    final bare = [
      for (final b in _grades.keys)
        if (!withPump.contains(b.toLowerCase())) b,
      if (_pump == null &&
          !_grades.containsKey(_selectedBrand) &&
          !withPump.contains(_selectedBrand.toLowerCase()))
        _selectedBrand,
    ];
    final result = await showOptionPicker<String>(
      context: context,
      title: 'Petrol pump',
      options: [
        for (final p in _pumps)
          PickerOption(
            value: 'p:${p.id}',
            label: p.label,
            leading: BrandLogo(brandName: p.brand, size: 28),
          ),
        for (final b in bare)
          PickerOption(
            value: 'b:$b',
            label: b,
            leading: BrandLogo(brandName: b, size: 28),
          ),
      ],
      selected: _pump != null ? 'p:${_pump!.id}' : 'b:$_selectedBrand',
      actionLabel: 'Add petrol pump',
    );
    if (!mounted || result == null) return;
    if (result is PickerPicked<String>) {
      final v = result.value;
      setState(() => v.startsWith('p:')
          ? _choose(_pumps.firstWhere((p) => 'p:${p.id}' == v))
          : _choose(null, brand: v.substring(2)));
      await _applyPumpPrice();
      return;
    }
    // Footer action: add a pump, then select it.
    final added = await showPumpEditor(context);
    final pumps = await _db.getPumps();
    if (!mounted) return;
    setState(() {
      _pumps = pumps;
      if (added != null) _choose(added);
    });
    await _applyPumpPrice();
  }

  /// Adding only: fills the price from the last priced fill-up at the
  /// chosen pump, while the field is empty or still holds what the previous
  /// pump put there. Through the normal listener, so the total follows.
  Future<void> _applyPumpPrice() async {
    if (_isEdit) return;
    final text = _priceController.text.trim();
    if (text.isNotEmpty && text != _pumpPrice) return;
    final pump = _pump;
    final log = pump == null ? null : await _db.lastPricedLogAt(pump.id);
    final price = log == null
        ? null
        : log.pricePerLitre ?? computePricePerLitre(log.totalCost, log.liters);
    if (!mounted) return;
    setState(() {
      if (price == null) {
        if (text.isNotEmpty) _priceController.text = '';
        _pumpPrice = null;
        _pumpPriceAt = null;
      } else {
        _pumpPrice = price.toStringAsFixed(2);
        _pumpPriceAt = DateTime.tryParse(log!.timestamp);
        _priceController.text = _pumpPrice!;
      }
    });
  }

  /// Adds a grade to the selected brand and selects it.
  Future<void> _addGrade() async {
    final name = await showAddFuelTypeDialog(context,
        title: 'Add fuel grade · $_selectedBrand');
    if (name == null || name.trim().isEmpty) return;
    if (!_grades.containsKey(_selectedBrand)) await addBrand(_selectedBrand);
    final added = await addGrade(_selectedBrand, name);
    final grades = await loadBrandGrades();
    if (!mounted) return;
    final match = (grades[_selectedBrand] ?? const <String>[])
        .where((g) => g.toLowerCase() == name.trim().toLowerCase());
    if (!added && match.isNotEmpty) _showSnack('"${match.first}" already exists.');
    setState(() {
      _grades = grades;
      if (match.isNotEmpty) _selectedFuelType = match.first;
    });
  }
  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_saving) return;
    if (_isEdit && _original == null) return;

    if (_isEdit) {
      final confirm = await _showSaveConfirmation();
      if (!confirm) return;
    }

    int odometer;
    if (_isKmMode && _baseOdometer != null) {
      final km = int.tryParse(_odoController.text.trim()) ?? 0;
      odometer = _baseOdometer! + km;
    } else {
      odometer = int.tryParse(_odoController.text.trim()) ?? 0;
    }

    final liters = double.tryParse(_litersController.text.trim()) ?? 0;

    // Backward odometer warning
    if (!_isEdit &&
        !_isKmMode &&
        _baseOdometer != null &&
        odometer < _baseOdometer!) {
      final proceed = await _showBackwardOdoWarning();
      if (!proceed) return;
    }
    // A backdated fill-up can't read more than the one that came after it.
    if (!_isEdit && _nextOdometer != null && odometer > _nextOdometer!) {
      final proceed = await _showOdoWarning(
          'New odometer is more than the next reading ($_nextOdometer km). '
          'Save anyway?');
      if (!proceed) return;
    }

    setState(() => _saving = true);

    final newTotal = double.tryParse(_costController.text.trim());
    final newPrice = double.tryParse(_priceController.text.trim());

    final logId = _original?.id ?? FuelLog.generateId();
    final trip = _trip;
    final tripId = trip != null && _onTrip ? trip.id : null;
    try {
      if (_isEdit) {
        final updated = _original!.copyWith(
          odometer: odometer,
          liters: liters,
          pumpBrand: _selectedBrand,
          // With the brand, so a changed pump never leaves the old id.
          pumpId: _pump?.id,
          clearPumpId: _pump == null,
          fullTank: _fullTank,
          notes: _notesController.text.trim(),
          fuelType: _selectedFuelType,
          // Untouched, the stored string goes back as it was: logs sort by
          // it, and a CSV import may have written another format.
          timestamp:
              _whenTouched ? _when.toIso8601String() : _original!.timestamp,
          totalCost: newTotal,
          clearTotalCost: newTotal == null,
          pricePerLitre: newPrice,
          clearPricePerLitre: newPrice == null,
          tripId: tripId,
          clearTripId: tripId == null,
        );
        await _db.updateLog(updated);
      } else {
        final log = FuelLog(
          vehicleId: widget.vehicleId!,
          id: logId,
          timestamp: _when.toIso8601String(),
          odometer: odometer,
          liters: liters,
          pumpBrand: _selectedBrand,
          pumpId: _pump?.id,
          fullTank: _fullTank,
          notes: _notesController.text.trim(),
          fuelType: _selectedFuelType,
          totalCost: newTotal,
          pricePerLitre: newPrice,
          tripId: tripId,
        );
        await _db.insertLog(log);
      }
      await saveBills(logId, _bills, _billsBefore);
      _saved = true;
      if (trip != null && trip.isActive && tripId != null && _tripEndsHere) {
        await endTrip(trip, odometer,
            _isEdit && !_whenTouched
                ? DateTime.tryParse(_original!.timestamp) ?? _when
                : _when);
      } else if (trip != null && trip.isActive) {
        await refreshTripNotification(trip.vehicleId);
      }
      await ServiceReminders.instance
          .checkKmDue(_original?.vehicleId ?? widget.vehicleId!, odometer);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      debugPrint('Error saving entry: $e');
      if (mounted) {
        setState(() => _saving = false);
        _showSnack('Failed to save: $e');
      }
    }
  }

  Future<bool> _showSaveConfirmation() async {
    return await showDialog<bool>(
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
        ) ??
        false;
  }

  Future<bool> _showBackwardOdoWarning() => _showOdoWarning(
      'New odometer is less than last reading. Save anyway?');

  Future<bool> _showOdoWarning(String message) async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Odometer Warning'),
            content: Text(message),
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

  Future<void> _pickWhen() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _when,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
        context: context, initialTime: TimeOfDay.fromDateTime(_when));
    if (!mounted) return;
    final t = time ?? TimeOfDay.fromDateTime(_when);
    _whenFromPhoto = false;
    _setWhen(DateTime(date.year, date.month, date.day, t.hour, t.minute));
  }

  /// Moves the fill-up to [when] and re-reads its neighbours by date: KM
  /// mode then counts from the fill-up just before it.
  void _setWhen(DateTime when) {
    FuelLog? prev;
    FuelLog? next;
    for (final l in _others) {
      final at = DateTime.tryParse(l.timestamp);
      if (at == null) continue;
      if (!at.isAfter(when)) {
        prev = l;
      } else {
        next ??= l;
      }
    }
    setState(() {
      _when = when;
      _whenTouched = true;
      _baseOdometer = prev?.odometer;
      _nextOdometer = next?.odometer;
      if (_baseOdometer == null) _isKmMode = false;
    });
  }

  void _switchMode(bool km) {
    // ModeSwitch reports taps on the tab that is already selected; converting
    // then would add or subtract the base odometer a second time.
    if (km == _isKmMode) return;
    setState(() {
      _isKmMode = km;
      // Convert only a value the user actually entered; an empty field
      // stays empty.
      final current = int.tryParse(_odoController.text.trim());
      if (_baseOdometer == null || current == null) return;
      if (km) {
        // Convert current odometer to km driven
        _odoController.text = (current - _baseOdometer!).toString();
      } else {
        // Convert km driven back to odometer
        _odoController.text = (_baseOdometer! + current).toString();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final action = _isEdit ? 'Edit Fill-up' : 'Add Fill-up';
    final title = _vehicle == null ? action : '$action · ${_vehicle!.name}';

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text(title)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final odo = int.tryParse(_odoController.text.trim());
    final note = TextStyle(color: colors.textSecondary, fontSize: 12);

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (photoScanSupported && !_isEdit) _buildScanCard(colors),
              if (_scans.isNotEmpty) ...[
                const SizedBox(height: 12),
                _buildScanSummary(colors),
              ],

              _section('When', colors),
              PickerField(
                label: 'Date and time',
                icon: Icons.event_outlined,
                onTap: _pickWhen,
                child: Text(
                  DateFormat('d MMM y, h:mm a').format(_when),
                  style: TextStyle(color: colors.textPrimary, fontSize: 16),
                ),
              ),
              if (_whenFromPhoto)
                Padding(
                  padding: const EdgeInsets.only(top: 6, left: 4),
                  child: Text('Photo time, check it', style: note),
                ),

              _section('Reading', colors),
              ModeSwitch(
                isKmMode: _isKmMode,
                kmModeEnabled: _baseOdometer != null,
                onChanged: _switchMode,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _odoController,
                keyboardType: TextInputType.number,
                onChanged: (_) => setState(() => _odoFromPhoto = false),
                decoration: InputDecoration(
                  labelText: _isKmMode ? 'KM Driven' : 'Odometer (km)',
                  prefixIcon: const Icon(Icons.speed),
                  suffixText: 'km',
                  helperText: _odoFromPhoto ? 'From photo, check it' : null,
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return _isKmMode
                        ? 'Enter distance driven'
                        : 'Enter odometer reading';
                  }
                  final n = int.tryParse(v.trim());
                  if (n == null) return 'Invalid number';
                  // A negative distance would save an odometer below the
                  // last reading, skipping the backward-odometer warning.
                  if (_isKmMode && n < 0) return "Distance can't be negative";
                  return null;
                },
              ),
              if (_isKmMode && _baseOdometer != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6, left: 4),
                  child: Text(
                    _isEdit
                        ? 'Previous odometer: $_baseOdometer km'
                        : 'Last odometer: $_baseOdometer km',
                    style: note,
                  ),
                )
              else if (!_isKmMode &&
                  _baseOdometer != null &&
                  odo != null &&
                  odo >= _baseOdometer!)
                Padding(
                  padding: const EdgeInsets.only(top: 6, left: 4),
                  child: Text(
                    'Last reading $_baseOdometer km, so '
                    '${odo - _baseOdometer!} km since the last refill.',
                    style: note,
                  ),
                ),

              _section('Fuel', colors),
              PickerField(
                label: 'Petrol pump',
                icon: Icons.ev_station,
                onTap: _pickPump,
                child: Row(
                  children: [
                    BrandLogo(brandName: _selectedBrand, size: 26),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _pump?.label ?? _selectedBrand,
                        style:
                            TextStyle(color: colors.textPrimary, fontSize: 16),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 6),
                child: Text('Fuel grade', style: note),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final g in _gradeChoices)
                    ChoiceChip(
                      label: Text(g),
                      selected: g == _selectedFuelType,
                      onSelected: (_) =>
                          setState(() => _selectedFuelType = g),
                    ),
                  ActionChip(
                    avatar: const Icon(Icons.add, size: 18),
                    label: const Text('Grade'),
                    tooltip: 'Add fuel grade',
                    onPressed: _addGrade,
                  ),
                ],
              ),
              const SizedBox(height: 12),              TextFormField(
                controller: _litersController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) {
                  if (_fuelFromPhoto) setState(() => _fuelFromPhoto = false);
                },
                decoration: InputDecoration(
                  labelText: 'Liters',
                  prefixIcon: const Icon(Icons.local_gas_station),
                  suffixText: 'L',
                  helperText: _fuelFromPhoto
                      ? 'Litres, price and total from photo, check them'
                      : null,
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Enter liters';
                  final val = double.tryParse(v.trim());
                  if (val == null || val <= 0) return 'Must be > 0';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              // Cost (optional): the two fields keep each other in sync.
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
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _priceController,
                builder: (context, value, _) =>
                    _pumpPrice == null || value.text != _pumpPrice
                        ? const SizedBox.shrink()
                        : Padding(
                            padding: const EdgeInsets.only(top: 6, left: 4),
                            child: Text(
                                _pumpPriceAt == null
                                    ? 'Price from your last fill-up here. '
                                        'Change it if it moved.'
                                    : 'Price from your '
                                        '${DateFormat('d MMM').format(_pumpPriceAt!)} '
                                        'fill-up here. Change it if it moved.',
                                style: TextStyle(
                                    color: colors.textSecondary, fontSize: 12)),
                          ),
              ),
              ?_buildPumpCheck(colors),
              const SizedBox(height: 12),
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Row(
                    children: [
                      Icon(Icons.local_gas_station_outlined,
                          color: colors.textSecondary, size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text('Full Tank',
                            style: TextStyle(
                                color: colors.textPrimary, fontSize: 15)),
                      ),
                      Switch(
                        value: _fullTank,
                        onChanged: (v) => setState(() => _fullTank = v),
                      ),
                    ],
                  ),
                ),
              ),

              if (_trip != null) ...[
                const SizedBox(height: 12),
                Card(
                  margin: EdgeInsets.zero,
                  child: Column(
                    children: [
                      SwitchListTile(
                        secondary: Icon(Icons.route, color: colors.secondary),
                        title: Text('Part of ${_trip!.name}'),
                        value: _onTrip,
                        onChanged: (v) => setState(() {
                          _onTrip = v;
                          if (!v) _tripEndsHere = false;
                        }),
                      ),
                      if (_trip!.isActive && _onTrip)
                        SwitchListTile(
                          secondary:
                              Icon(Icons.flag_outlined, color: colors.secondary),
                          title: const Text('The trip ends here'),
                          subtitle: const Text(
                              "Ends it at this fill-up's odometer and time."),
                          value: _tripEndsHere,
                          onChanged: (v) => setState(() => _tripEndsHere = v),
                        ),
                    ],
                  ),
                ),
              ],

              _section('Receipts (optional)', colors),
              BillsSection(
                ownerType: 'fuel',
                items: _bills,
                onChanged: (l) => setState(() => _bills = l),
              ),

              _section('Notes', colors),
              TextFormField(
                controller: _notesController,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Notes (optional)',
                  prefixIcon: Icon(Icons.note_outlined),
                ),
              ),
              const SizedBox(height: 28),

              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(_isEdit ? 'Save Changes' : 'Save Entry',
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _section(String title, AppColors colors) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
        child: Text(title,
            style: TextStyle(
                color: colors.textSecondary,
                fontSize: 15,
                fontWeight: FontWeight.w500)),
      );
}