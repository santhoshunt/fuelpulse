import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat, NumberFormat;

import '../db/database_helper.dart';
import '../models/part.dart';
import '../services/service_reminders.dart';
import '../theme/app_colors.dart';
import '../utils/page_routes.dart';
import '../widgets/option_picker.dart';
import 'service_screen.dart' show latestOdometer;
import 'settings/settings_widgets.dart';

final _day = DateFormat('yyyy-MM-dd');
final _shown = DateFormat('d MMM y');
final _grouped = NumberFormat('#,##,##0', 'en_IN');

/// A vehicle's tyres and battery with how much of each one's life is used,
/// for the vehicle's edit page. Parts save on their own, apart from the
/// vehicle's Save.
class PartsSection extends StatefulWidget {
  final String vehicleId;

  const PartsSection({super.key, required this.vehicleId});

  @override
  State<PartsSection> createState() => _PartsSectionState();
}

class _PartsSectionState extends State<PartsSection> {
  List<Part> _parts = const [];
  int? _odometer;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final parts = await DatabaseHelper().getParts(widget.vehicleId);
    final odo = await latestOdometer(widget.vehicleId);
    if (mounted) {
      setState(() {
        _parts = parts;
        _odometer = odo;
      });
    }
  }

  Future<void> _open([Part? p]) async {
    final changed = await Navigator.push<bool>(
        context,
        SmoothPageRoute(
            page: PartFormScreen(
                vehicleId: widget.vehicleId, part: p, odometer: _odometer)));
    if (changed == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final muted = TextStyle(color: colors.textSecondary, fontSize: 12);
    final now = DateTime.now();
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (final p in _parts) ...[
            InkWell(
              onTap: () => _open(p),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Builder(builder: (context) {
                  final wear = p.wear(_odometer ?? p.fittedOdometer, now);
                  final used = (_odometer ?? p.fittedOdometer) - p.fittedOdometer;
                  final color = wear == null
                      ? colors.primarySoft
                      : wear >= 0.9
                          ? colors.danger
                          : wear >= 0.7
                              ? colors.warning
                              : colors.primary;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Icon(
                              p.kind == 'battery'
                                  ? Icons.battery_charging_full
                                  : Icons.tire_repair,
                              color: colors.primary,
                              size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(p.label,
                                style: TextStyle(
                                    color: colors.textPrimary,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600)),
                          ),
                          if (p.brand.isNotEmpty) Text(p.brand, style: muted),
                        ],
                      ),
                      if (wear != null) ...[
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            value: wear.clamp(0.0, 1.0),
                            minHeight: 6,
                            color: color,
                            backgroundColor: colors.cardBorder,
                          ),
                        ),
                      ],
                      const SizedBox(height: 4),
                      Text(
                          [
                            if (p.lifeKm != null)
                              '${_grouped.format(used)} of ${_grouped.format(p.lifeKm)} km',
                            'fitted ${_shown.format(DateTime.parse(p.fittedAt))}',
                            if (wear != null && wear >= 0.9) 'change soon',
                          ].join(' · '),
                          style: muted),
                    ],
                  );
                }),
              ),
            ),
            Divider(height: 1, indent: 16, endIndent: 16, color: colors.cardBorder),
          ],
          ListTile(
            leading: Icon(Icons.add, color: colors.primary),
            title: Text('Add tyre or battery',
                style: TextStyle(color: colors.primary)),
            onTap: () => _open(),
          ),
        ],
      ),
    );
  }
}

/// Add or edit a part. Saves itself and pops true when something changed.
class PartFormScreen extends StatefulWidget {
  final String vehicleId;
  final Part? part;

  /// Prefills the odometer at fitting for a new part.
  final int? odometer;

  const PartFormScreen(
      {super.key, required this.vehicleId, this.part, this.odometer});

  @override
  State<PartFormScreen> createState() => _PartFormScreenState();
}

class _PartFormScreenState extends State<PartFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final Part? _p = widget.part;
  late String _kind = _p?.kind ?? 'tyre';
  late final _label = TextEditingController(text: _p?.label ?? 'Front tyre');
  late final _brand = TextEditingController(text: _p?.brand ?? '');
  late final _odo = TextEditingController(
      text: (_p?.fittedOdometer ?? widget.odometer)?.toString() ?? '');
  late final _lifeKm = TextEditingController(
      text: _p == null ? '20000' : _p.lifeKm?.toString() ?? '');
  late final _lifeMonths = TextEditingController(
      text: _p == null ? '48' : _p.lifeMonths?.toString() ?? '');
  late final _notes = TextEditingController(text: _p?.notes ?? '');
  late DateTime _fitted = DateTime.tryParse(_p?.fittedAt ?? '') ?? DateTime.now();
  late DateTime? _warranty = DateTime.tryParse(_p?.warrantyUntil ?? '');

  @override
  void dispose() {
    for (final c in [_label, _brand, _odo, _lifeKm, _lifeMonths, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Typical lives, filled when the kind changes on a new part.
  void _setKind(String kind) {
    setState(() {
      _kind = kind;
      if (_p != null) return;
      if (kind == 'battery') {
        _label.text = 'Battery';
        _lifeKm.text = '';
        _lifeMonths.text = '36';
      } else if (kind == 'tyre') {
        _label.text = 'Front tyre';
        _lifeKm.text = '20000';
        _lifeMonths.text = '48';
      } else {
        _label.text = '';
        _lifeKm.text = '';
        _lifeMonths.text = '';
      }
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    int? num(TextEditingController c) {
      final v = int.tryParse(c.text.trim());
      return v != null && v > 0 ? v : null;
    }

    final part = Part(
      id: _p?.id ?? Part.generateId(),
      vehicleId: _p?.vehicleId ?? widget.vehicleId,
      kind: _kind,
      label: _label.text.trim(),
      brand: _brand.text.trim(),
      fittedAt: _day.format(_fitted),
      fittedOdometer: int.parse(_odo.text.trim()),
      lifeKm: num(_lifeKm),
      lifeMonths: num(_lifeMonths),
      warrantyUntil: _warranty == null ? null : _day.format(_warranty!),
      notes: _notes.text.trim(),
    );
    await DatabaseHelper().savePart(part);
    await ServiceReminders.instance.rescheduleAll(ask: part.lifeMonths != null);
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _delete() async {
    final ok = await confirmListDelete(
        context, _p!.label, 'Its history is not kept. This cannot be undone.');
    if (!ok) return;
    await DatabaseHelper().deletePart(_p.id);
    await ServiceReminders.instance.rescheduleAll();
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final note = TextStyle(color: colors.textSecondary, fontSize: 12);
    String? positive(String? v) {
      final s = v?.trim() ?? '';
      if (s.isEmpty) return null;
      final n = int.tryParse(s);
      return n == null || n <= 0 ? 'Enter a whole number' : null;
    }

    return Scaffold(
      appBar: AppBar(title: Text(_p == null ? 'Add part' : 'Edit part')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            sectionHeader('Part'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final e in kPartKinds.entries)
                  ChoiceChip(
                    label: Text(e.value),
                    selected: _kind == e.key,
                    onSelected: (_) => _setKind(e.key),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _label,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                  labelText: 'Label', hintText: 'Front tyre, Rear tyre'),
              validator: (v) =>
                  (v?.trim() ?? '').isEmpty ? 'Enter a label' : null,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _brand,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                  labelText: 'Brand (optional)', hintText: 'MRF, Exide'),
            ),
            const SizedBox(height: 24),
            sectionHeader('Fitted'),
            const SizedBox(height: 12),
            PickerField(
              label: 'Fitted on',
              icon: Icons.event_outlined,
              onTap: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: _fitted,
                  firstDate: DateTime(2000),
                  lastDate: DateTime.now(),
                );
                if (d != null) setState(() => _fitted = d);
              },
              child: Text(_shown.format(_fitted),
                  style: TextStyle(color: colors.textPrimary, fontSize: 16)),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _odo,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                  labelText: 'Odometer at fitting', suffixText: 'km'),
              validator: (v) => int.tryParse(v?.trim() ?? '') == null
                  ? 'Enter the odometer reading'
                  : null,
            ),
            const SizedBox(height: 24),
            sectionHeader('Life'),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _lifeKm,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: 'Good for', suffixText: 'km'),
                    validator: positive,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _lifeMonths,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: 'Or for', suffixText: 'months'),
                    validator: positive,
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 4),
              child: Text(
                  'Whichever runs out first. Change these to the maker\'s '
                  'figures; you get a reminder near the end.',
                  style: note),
            ),
            const SizedBox(height: 12),
            PickerField(
              label: 'Warranty until (optional)',
              icon: Icons.verified_outlined,
              onTap: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: _warranty ?? DateTime.now(),
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2100),
                );
                if (d != null) setState(() => _warranty = d);
              },
              child: Text(
                  _warranty == null ? 'Not set' : _shown.format(_warranty!),
                  style: TextStyle(
                      color: _warranty == null
                          ? colors.textSecondary
                          : colors.textPrimary,
                      fontSize: 16)),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notes,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Notes (optional)'),
            ),
            const SizedBox(height: 28),
            SizedBox(
              height: 52,
              child: ElevatedButton(onPressed: _save, child: const Text('Save')),
            ),
            if (_p != null) ...[
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _delete,
                style: OutlinedButton.styleFrom(
                  foregroundColor: colors.danger,
                  side: BorderSide(color: colors.danger.withValues(alpha: 0.35)),
                  minimumSize: const Size.fromHeight(48),
                ),
                child: const Text('Delete part'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
