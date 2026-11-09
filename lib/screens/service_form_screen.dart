import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat, NumberFormat;

import '../db/database_helper.dart';
import '../models/attachment.dart';
import '../models/service_record.dart';
import '../models/service_type.dart';
import '../models/workshop.dart';
import '../services/service_reminders.dart';
import '../theme/app_colors.dart';
import '../widgets/bills_section.dart';
import '../utils/custom_pictures.dart';
import '../widgets/option_picker.dart';
import 'service_types_screen.dart';
import 'settings/settings_widgets.dart';
import 'workshops_screen.dart';

final _grouped = NumberFormat('#,##,##0', 'en_IN');
final _dueDate = DateFormat('yyyy-MM-dd');

/// Add or edit one service visit, and schedule the next. Saves itself and
/// pops true when something changed.
class ServiceFormScreen extends StatefulWidget {
  final String vehicleId;
  final ServiceRecord? record;

  /// Pre-ticked types for a new record ("Mark done" on a schedule).
  final List<String> presetTypeIds;

  /// Pre-filled odometer for a new record: the latest known reading.
  final int? odometer;

  const ServiceFormScreen({
    super.key,
    required this.vehicleId,
    this.record,
    this.presetTypeIds = const [],
    this.odometer,
  });

  @override
  State<ServiceFormScreen> createState() => _ServiceFormScreenState();
}

class _ServiceFormScreenState extends State<ServiceFormScreen> {
  final _db = DatabaseHelper();
  final _formKey = GlobalKey<FormState>();
  late final ServiceRecord? _r = widget.record;
  late DateTime _when = DateTime.tryParse(_r?.timestamp ?? '') ?? DateTime.now();
  late final _odo = TextEditingController(
      text: (_r?.odometer ?? widget.odometer)?.toString() ?? '');
  late final _cost =
      TextEditingController(text: _r?.cost?.toStringAsFixed(0) ?? '');
  late final _notes = TextEditingController(text: _r?.notes ?? '');
  final _everyKm = TextEditingController();
  final _everyMonths = TextEditingController();
  late final Set<String> _types = {...?_r?.typeIds, ...widget.presetTypeIds};
  String? _workshopId;
  List<Workshop> _workshops = const [];
  List<ServiceType> _allTypes = const [];
  List<Attachment> _bills = const [];
  List<Attachment> _billsBefore = const [];

  /// Set once saved, so closing the form keeps the bills it added.
  bool _saved = false;
  late bool _schedule = _r == null || _r.nextDueKm != null || _r.nextDueDate != null;

  /// Set once the intervals are typed by hand: type changes then leave them.
  bool _intervalsTouched = false;

  @override
  void initState() {
    super.initState();
    _workshopId = _r?.workshopId;
    final r = _r;
    if (r != null) {
      _intervalsTouched = true;
      if (r.nextDueKm != null) _everyKm.text = '${r.nextDueKm! - r.odometer}';
      final due = r.nextDueDate == null ? null : DateTime.tryParse(r.nextDueDate!);
      if (due != null) {
        _everyMonths.text =
            '${(due.year - _when.year) * 12 + due.month - _when.month}';
      }
    }
    _odo.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    for (final c in [_odo, _cost, _notes, _everyKm, _everyMonths]) {
      c.dispose();
    }
    if (!_saved) discardBills(_bills, _billsBefore);
    super.dispose();
  }

  Future<void> _load() async {
    final ws = await _db.getWorkshops();
    final types = await _db.getServiceTypes();
    final bills = _r == null
        ? const <Attachment>[]
        : await _db.getAttachments('service', _r.id);
    if (!mounted) return;
    setState(() {
      _workshops = ws;
      _allTypes = types;
      _bills = _billsBefore = bills;
      _prefillIntervals();
    });
  }

  /// The shortest interval among the ticked types.
  void _prefillIntervals() {
    if (_intervalsTouched) return;
    final picked = _allTypes.where((t) => _types.contains(t.id));
    final km = picked.map((t) => t.intervalKm).whereType<int>();
    final mo = picked.map((t) => t.intervalMonths).whereType<int>();
    _everyKm.text = km.isEmpty ? '' : '${km.reduce((a, b) => a < b ? a : b)}';
    _everyMonths.text =
        mo.isEmpty ? '' : '${mo.reduce((a, b) => a < b ? a : b)}';
  }

  int? get _nextKm {
    final odo = int.tryParse(_odo.text.trim());
    final every = int.tryParse(_everyKm.text.trim());
    return odo != null && every != null && every > 0 ? odo + every : null;
  }

  DateTime? get _nextDate {
    final m = int.tryParse(_everyMonths.text.trim());
    return m != null && m > 0
        ? DateTime(_when.year, _when.month + m, _when.day)
        : null;
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _when,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (d != null) setState(() => _when = DateTime(d.year, d.month, d.day, _when.hour, _when.minute));
  }

  Future<void> _pickWorkshop() async {
    final result = await showOptionPicker<String>(
      context: context,
      title: 'Workshop',
      options: [
        const PickerOption(value: '', label: 'None'),
        for (final w in _workshops)
          PickerOption(
              value: w.id,
              label: w.area.isEmpty ? w.name : '${w.name} · ${w.area}'),
      ],
      selected: _workshopId ?? '',
      actionLabel: 'Add workshop',
    );
    if (!mounted || result == null) return;
    if (result is PickerPicked<String>) {
      setState(() => _workshopId = result.value.isEmpty ? null : result.value);
      return;
    }
    final w = await showWorkshopEditor(context);
    final ws = await _db.getWorkshops();
    if (!mounted) return;
    setState(() {
      _workshops = ws;
      if (w != null) _workshopId = w.id;
    });
  }

  Future<void> _newType() async {
    final t = await showServiceTypeEditor(context,
        nextSortOrder: _allTypes.length);
    final types = await _db.getServiceTypes();
    if (!mounted) return;
    setState(() {
      _allTypes = types;
      if (t != null) _types.add(t.id);
      _prefillIntervals();
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_types.isEmpty) {
      showSettingsSnack(context, 'Pick at least one kind of work.');
      return;
    }
    final cost = double.tryParse(_cost.text.trim());
    final odo = int.parse(_odo.text.trim());
    final nextKm = _schedule ? _nextKm : null;
    final nextDate = _schedule ? _nextDate : null;
    final record = ServiceRecord(
      id: _r?.id ?? ServiceRecord.generateId(),
      vehicleId: _r?.vehicleId ?? widget.vehicleId,
      timestamp: _when.toIso8601String(),
      odometer: odo,
      workshopId: _workshopId,
      // Keep the order types are listed in.
      typeIds: [
        for (final t in _allTypes)
          if (_types.contains(t.id)) t.id,
        ..._types.where((id) => !_allTypes.any((t) => t.id == id)),
      ],
      cost: cost,
      notes: _notes.text.trim(),
      nextDueKm: nextKm,
      nextDueDate: nextDate == null ? null : _dueDate.format(nextDate),
    );
    if (_r == null) {
      await _db.insertService(record);
    } else {
      await _db.updateService(record);
    }
    await saveBills(record.id, _bills, _billsBefore);
    _saved = true;
    // The first schedule, by km or date, asks for the notification
    // permission: a km reminder needs it as much as a dated one.
    await ServiceReminders.instance.rescheduleAll(
        ask: record.nextDueKm != null || record.nextDueDate != null);
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete service?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.of(ctx).danger,
                foregroundColor: Colors.white),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await deletePictureFiles(await _db.deleteService(_r!.id));
    await ServiceReminders.instance.rescheduleAll();
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final note = TextStyle(color: colors.textSecondary, fontSize: 12);
    final workshop = _workshops.where((w) => w.id == _workshopId).firstOrNull;
    final nextKm = _nextKm;
    final nextDate = _nextDate;
    final due = [
      if (nextKm != null) '${_grouped.format(nextKm)} km',
      if (nextDate != null) DateFormat('d MMM y').format(nextDate),
    ];
    return Scaffold(
      appBar: AppBar(title: Text(_r == null ? 'Add service' : 'Edit service')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            sectionHeader('Visit'),
            const SizedBox(height: 12),
            PickerField(
              label: 'Date',
              icon: Icons.event_outlined,
              onTap: _pickDate,
              child: Text(DateFormat('d MMM y').format(_when),
                  style: TextStyle(color: colors.textPrimary, fontSize: 16)),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _odo,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                  labelText: 'Odometer (km)', prefixIcon: Icon(Icons.speed)),
              validator: (v) => int.tryParse(v?.trim() ?? '') == null
                  ? 'Enter odometer reading'
                  : null,
            ),
            const SizedBox(height: 12),
            PickerField(
              label: 'Workshop',
              icon: Icons.store_outlined,
              onTap: _pickWorkshop,
              child: Text(workshop?.name ?? 'None',
                  style: TextStyle(color: colors.textPrimary, fontSize: 16)),
            ),
            const SizedBox(height: 24),
            sectionHeader('Work done'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final t in _allTypes)
                  FilterChip(
                    label: Text(t.name),
                    selected: _types.contains(t.id),
                    onSelected: (on) => setState(() {
                      on ? _types.add(t.id) : _types.remove(t.id);
                      _prefillIntervals();
                    }),
                  ),
                ActionChip(
                  avatar: const Icon(Icons.add, size: 18),
                  label: const Text('New type'),
                  onPressed: _newType,
                ),
              ],
            ),
            const SizedBox(height: 24),
            sectionHeader('Cost'),
            const SizedBox(height: 12),
            TextFormField(
              controller: _cost,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                  labelText: 'Total (₹)',
                  prefixIcon: Icon(Icons.currency_rupee)),
              validator: (v) {
                final s = v?.trim() ?? '';
                if (s.isEmpty) return null;
                final n = double.tryParse(s);
                return n == null || n < 0 ? 'Invalid' : null;
              },
            ),
            const SizedBox(height: 24),
            sectionHeader('Bills (optional)'),
            const SizedBox(height: 12),
            BillsSection(
              ownerType: 'service',
              items: _bills,
              onChanged: (l) => setState(() => _bills = l),
            ),
            const SizedBox(height: 24),
            sectionHeader('Next service'),
            const SizedBox(height: 4),
            SwitchListTile(
              contentPadding: const EdgeInsets.only(left: 4),
              title: const Text('Schedule the next one'),
              value: _schedule,
              onChanged: (v) => setState(() => _schedule = v),
            ),
            if (_schedule) ...[
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _everyKm,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Every (km)'),
                      onChanged: (_) => setState(() => _intervalsTouched = true),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _everyMonths,
                      keyboardType: TextInputType.number,
                      decoration:
                          const InputDecoration(labelText: 'Or every (months)'),
                      onChanged: (_) => setState(() => _intervalsTouched = true),
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(top: 6, left: 4),
                child: Text(
                    due.isEmpty
                        ? 'Enter km, months or both.'
                        : 'Next due at ${due.join(' or ')}'
                            '${due.length > 1 ? ', whichever comes first' : ''}.',
                    style: note),
              ),
            ],
            const SizedBox(height: 24),
            sectionHeader('Notes'),
            const SizedBox(height: 12),
            TextField(
              controller: _notes,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Notes (optional)'),
            ),
            const SizedBox(height: 28),
            SizedBox(
              height: 52,
              child: ElevatedButton(
                  onPressed: _save, child: const Text('Save service')),
            ),
            if (_r != null) ...[
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _delete,
                style: OutlinedButton.styleFrom(
                  foregroundColor: colors.danger,
                  side:
                      BorderSide(color: colors.danger.withValues(alpha: 0.35)),
                  minimumSize: const Size.fromHeight(48),
                ),
                child: const Text('Delete service'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
