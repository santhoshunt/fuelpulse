import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show NumberFormat;

import '../db/database_helper.dart';
import '../models/check.dart';
import '../services/service_reminders.dart';
import '../theme/app_colors.dart';
import 'settings/settings_widgets.dart' show confirmListDelete;

final _grouped = NumberFormat('#,##,##0', 'en_IN');

/// Checks you do yourself on a schedule, for Garage → Service: each with
/// when it's due and a Done button that resets it.
class ChecksCard extends StatefulWidget {
  final String vehicleId;

  /// The latest odometer, for km-based checks and for Done.
  final int? odometer;

  const ChecksCard({super.key, required this.vehicleId, this.odometer});

  @override
  State<ChecksCard> createState() => _ChecksCardState();
}

class _ChecksCardState extends State<ChecksCard> {
  final _db = DatabaseHelper();
  List<Check> _checks = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(ChecksCard old) {
    super.didUpdateWidget(old);
    if (old.vehicleId != widget.vehicleId || old.odometer != widget.odometer) {
      _load();
    }
  }

  Future<void> _load() async {
    final checks = await _db.getChecks(widget.vehicleId);
    if (mounted) setState(() => _checks = checks);
  }

  Future<void> _done(Check c) async {
    await _db.saveCheck(c.copyWith(
      lastDoneAt: DateTime.now().toIso8601String(),
      lastDoneKm: widget.odometer ?? c.lastDoneKm,
    ));
    await ServiceReminders.instance.rescheduleAll();
    await _load();
  }

  Future<void> _edit([Check? c]) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => _CheckDialog(
          vehicleId: widget.vehicleId, check: c, odometer: widget.odometer),
    );
    if (changed == true) {
      await ServiceReminders.instance.rescheduleAll(ask: true);
      await _load();
    }
  }

  /// "every 14 days · due today", "every 500 km · 220 km left".
  String _status(Check c) {
    final now = DateTime.now();
    final parts = <String>[];
    final days = c.daysLeft(now);
    if (days != null) {
      parts.add('every ${c.everyDays} days');
      parts.add(days < 0
          ? '${-days} ${days == -1 ? 'day' : 'days'} overdue'
          : days == 0
              ? 'due today'
              : 'in $days ${days == 1 ? 'day' : 'days'}');
    }
    final km = c.kmLeft(widget.odometer);
    if (c.everyKm != null) {
      parts.add('every ${_grouped.format(c.everyKm)} km');
      if (km != null) {
        parts.add(km <= 0 ? 'due now' : '${_grouped.format(km)} km left');
      }
    }
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final now = DateTime.now();
    final muted = TextStyle(color: colors.textSecondary, fontSize: 12);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('CHECKS',
                        style: TextStyle(
                            color: colors.textSecondary,
                            fontSize: 11,
                            letterSpacing: 1.2,
                            fontWeight: FontWeight.w600)),
                  ),
                  IconButton(
                    tooltip: 'Add check',
                    icon: Icon(Icons.add, color: colors.primary),
                    onPressed: () => _edit(),
                  ),
                ],
              ),
              if (_checks.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(right: 8, bottom: 8),
                  child: Text(
                      'Things you check yourself, like tyre pressure every 2 '
                      'weeks or chain lube every 500 km. Tap + to add one.',
                      style: muted),
                ),
              for (final c in _checks)
                InkWell(
                  onTap: () => _edit(c),
                  borderRadius: BorderRadius.circular(10),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Icon(Icons.task_alt,
                            color: c.isDue(now, widget.odometer)
                                ? colors.danger
                                : colors.primary),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(c.name,
                                  style: TextStyle(
                                      color: colors.textPrimary,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600)),
                              Text(_status(c), style: muted),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        c.isDue(now, widget.odometer)
                            ? FilledButton(
                                onPressed: () => _done(c),
                                child: const Text('Done'))
                            : OutlinedButton(
                                onPressed: () => _done(c),
                                child: const Text('Done')),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Add or edit one check. Pops true when something changed.
class _CheckDialog extends StatefulWidget {
  final String vehicleId;
  final Check? check;
  final int? odometer;

  const _CheckDialog({required this.vehicleId, this.check, this.odometer});

  @override
  State<_CheckDialog> createState() => _CheckDialogState();
}

class _CheckDialogState extends State<_CheckDialog> {
  late final _name = TextEditingController(text: widget.check?.name ?? '');
  late final _days =
      TextEditingController(text: widget.check?.everyDays?.toString() ?? '');
  late final _km =
      TextEditingController(text: widget.check?.everyKm?.toString() ?? '');
  String? _error;

  static const _presets = [
    ('Tyre pressure', 14, null),
    ('Chain lube', null, 500),
    ('Coolant level', 30, null),
    ('Engine oil level', 30, null),
  ];

  @override
  void dispose() {
    _name.dispose();
    _days.dispose();
    _km.dispose();
    super.dispose();
  }

  int? _num(TextEditingController c) {
    final v = int.tryParse(c.text.trim());
    return v != null && v > 0 ? v : null;
  }

  Future<void> _save() async {
    final days = _num(_days), km = _num(_km);
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Enter a name');
      return;
    }
    if (days == null && km == null) {
      setState(() => _error = 'Enter days, km or both');
      return;
    }
    final c = widget.check;
    await DatabaseHelper().saveCheck(c == null
        ? Check(
            id: Check.generateId(),
            vehicleId: widget.vehicleId,
            name: _name.text.trim(),
            everyDays: days,
            everyKm: km,
            lastDoneAt: DateTime.now().toIso8601String(),
            lastDoneKm: widget.odometer ?? 0,
          )
        : c.copyWith(
            name: _name.text.trim(),
            everyDays: days,
            clearEveryDays: days == null,
            everyKm: km,
            clearEveryKm: km == null,
          ));
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _delete() async {
    final c = widget.check!;
    if (!await confirmListDelete(context, c.name, 'This cannot be undone.')) {
      return;
    }
    await DatabaseHelper().deleteCheck(c.id);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final adding = widget.check == null;
    return AlertDialog(
      title: Text(adding ? 'Add check' : 'Edit check'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (adding)
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final (name, days, km) in _presets)
                    ActionChip(
                      label: Text(name),
                      onPressed: () => setState(() {
                        _name.text = name;
                        _days.text = days?.toString() ?? '';
                        _km.text = km?.toString() ?? '';
                      }),
                    ),
                ],
              ),
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(labelText: 'Name', errorText: _error),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _days,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: 'Every', suffixText: 'days'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _km,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: 'Or every', suffixText: 'km'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        if (!adding)
          TextButton(
            onPressed: _delete,
            style: TextButton.styleFrom(
                foregroundColor: AppColors.of(context).danger),
            child: const Text('Delete'),
          ),
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        ElevatedButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
