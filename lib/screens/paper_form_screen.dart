import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../db/database_helper.dart';
import '../models/attachment.dart';
import '../models/paper.dart';
import '../services/service_reminders.dart';
import '../theme/app_colors.dart';
import '../utils/custom_pictures.dart';
import '../widgets/bills_section.dart';
import '../widgets/option_picker.dart';
import 'settings/settings_widgets.dart';

final _day = DateFormat('yyyy-MM-dd');
final _shown = DateFormat('d MMM y');

/// Add or edit a paper. Saves itself and pops true when something changed.
class PaperFormScreen extends StatefulWidget {
  final String vehicleId;
  final Paper? paper;

  const PaperFormScreen({super.key, required this.vehicleId, this.paper});

  @override
  State<PaperFormScreen> createState() => _PaperFormScreenState();
}

class _PaperFormScreenState extends State<PaperFormScreen> {
  final _db = DatabaseHelper();
  late final Paper? _p = widget.paper;
  late String _kind = _p?.kind ?? 'insurance';
  late final _title = TextEditingController(text: _p?.title ?? '');
  late final _number = TextEditingController(text: _p?.number ?? '');
  late final _notes = TextEditingController(text: _p?.notes ?? '');
  late DateTime? _issued = DateTime.tryParse(_p?.issuedOn ?? '');
  late DateTime? _expires = DateTime.tryParse(_p?.expiresOn ?? '');
  late int _remindDays = _p?.remindDays ?? 7;
  List<Attachment> _photos = const [];
  List<Attachment> _photosBefore = const [];
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    final p = _p;
    if (p != null) {
      _db.getAttachments('paper', p.id).then((a) {
        if (mounted) setState(() => _photos = _photosBefore = a);
      });
    }
  }

  @override
  void dispose() {
    for (final c in [_title, _number, _notes]) {
      c.dispose();
    }
    if (!_saved) discardBills(_photos, _photosBefore);
    super.dispose();
  }

  Future<DateTime?> _pick(DateTime? initial) => showDatePicker(
        context: context,
        initialDate: initial ?? DateTime.now(),
        firstDate: DateTime(1990),
        lastDate: DateTime(2100),
      );

  Future<void> _pickIssued() async {
    final d = await _pick(_issued);
    if (d == null) return;
    setState(() {
      _issued = d;
      // Usual terms: a PUC certificate for a year, insurance for a year
      // ending the day before.
      if (_expires == null && _kind == 'puc') {
        _expires = DateTime(d.year + 1, d.month, d.day);
      } else if (_expires == null && _kind == 'insurance') {
        _expires = DateTime(d.year + 1, d.month, d.day - 1);
      }
    });
  }

  Future<void> _pickRemind() async {
    final r = await showOptionPicker<int>(
      context: context,
      title: 'Remind me',
      options: [
        for (final d in const [1, 7, 15, 30])
          PickerOption(value: d, label: d == 1 ? '1 day before' : '$d days before'),
      ],
      selected: _remindDays,
    );
    if (r is PickerPicked<int>) setState(() => _remindDays = r.value);
  }

  Future<void> _save() async {
    final paper = Paper(
      id: _p?.id ?? Paper.generateId(),
      vehicleId: _p?.vehicleId ?? widget.vehicleId,
      kind: _kind,
      title: _title.text.trim(),
      number: _number.text.trim(),
      issuedOn: _issued == null ? null : _day.format(_issued!),
      expiresOn: _expires == null ? null : _day.format(_expires!),
      remindDays: _remindDays,
      notes: _notes.text.trim(),
    );
    await _db.savePaper(paper);
    await saveBills(paper.id, _photos, _photosBefore);
    _saved = true;
    await ServiceReminders.instance.rescheduleAll(ask: paper.expiresOn != null);
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _delete() async {
    final ok = await confirmListDelete(context, _p!.displayName,
        'Its photos are deleted too. This cannot be undone.');
    if (!ok) return;
    await deletePictureFiles(await _db.deletePaper(_p.id));
    await ServiceReminders.instance.rescheduleAll();
    if (mounted) Navigator.pop(context, true);
  }

  Widget _dateField(String label, DateTime? value, VoidCallback onTap,
          VoidCallback onClear, AppColors colors) =>
      PickerField(
        label: label,
        icon: Icons.event_outlined,
        onTap: onTap,
        child: Row(
          children: [
            Expanded(
              child: Text(value == null ? 'Not set' : _shown.format(value),
                  style: TextStyle(
                      color: value == null
                          ? colors.textSecondary
                          : colors.textPrimary,
                      fontSize: 16)),
            ),
            if (value != null)
              GestureDetector(
                onTap: onClear,
                child: Icon(Icons.close, size: 18, color: colors.textSecondary),
              ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(_p == null ? 'Add paper' : 'Edit paper')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          sectionHeader('Kind'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final e in kPaperKinds.entries)
                ChoiceChip(
                  label: Text(e.value),
                  selected: _kind == e.key,
                  onSelected: (_) => setState(() => _kind = e.key),
                ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _title,
            decoration: const InputDecoration(
                labelText: 'Name (optional)', hintText: 'Acko, Bajaj Allianz'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _number,
            decoration: const InputDecoration(labelText: 'Number (optional)'),
          ),
          const SizedBox(height: 24),
          sectionHeader('Dates'),
          const SizedBox(height: 12),
          _dateField('Issued', _issued, _pickIssued,
              () => setState(() => _issued = null), colors),
          const SizedBox(height: 12),
          _dateField('Expires', _expires, () async {
            final d = await _pick(_expires);
            if (d != null) setState(() => _expires = d);
          }, () => setState(() => _expires = null), colors),
          const SizedBox(height: 12),
          PickerField(
            label: 'Remind me',
            icon: Icons.notifications_outlined,
            onTap: _pickRemind,
            child: Text(
                _remindDays == 1 ? '1 day before' : '$_remindDays days before',
                style: TextStyle(color: colors.textPrimary, fontSize: 16)),
          ),
          const SizedBox(height: 24),
          sectionHeader('Notes'),
          const SizedBox(height: 12),
          TextField(
            controller: _notes,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Notes (optional)'),
          ),
          const SizedBox(height: 24),
          sectionHeader('Photos (optional)'),
          const SizedBox(height: 12),
          BillsSection(
            ownerType: 'paper',
            items: _photos,
            onChanged: (l) => setState(() => _photos = l),
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
              child: const Text('Delete paper'),
            ),
          ],
        ],
      ),
    );
  }
}
