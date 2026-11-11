import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat, NumberFormat;
import 'package:shared_preferences/shared_preferences.dart';

import '../db/database_helper.dart';
import '../models/check.dart';
import '../services/service_reminders.dart';
import '../theme/app_colors.dart';
import '../utils/undo_delete.dart';

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
    dataRestored.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    dataRestored.removeListener(_load);
    super.dispose();
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

  /// Where Done keeps the time and km it replaced, so the tick can undo it
  /// until the next Done.
  static String _undoKey(String id) => 'fuel_check_undo_$id';

  Future<void> _done(Check c) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_undoKey(c.id),
        jsonEncode({'at': c.lastDoneAt, 'km': c.lastDoneKm}));
    await _db.saveCheck(c.copyWith(
      lastDoneAt: DateTime.now().toIso8601String(),
      lastDoneKm: widget.odometer ?? c.lastDoneKm,
    ));
    await ServiceReminders.instance.rescheduleAll();
    await _load();
  }

  /// The tick's choices: mark the check done again now (early, before it
  /// is due), or undo the last Done when there is one to undo.
  Future<void> _tickMenu(Check c) async {
    final canUndo = (await SharedPreferences.getInstance())
            .getString(_undoKey(c.id)) !=
        null;
    final at = DateTime.tryParse(c.lastDoneAt);
    final when = at == null ? '' : DateFormat('d MMM').format(at);
    if (!mounted) return;
    final undo = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text(when.isEmpty ? c.name : '${c.name} · done $when',
                  style: Theme.of(ctx).textTheme.titleMedium),
            ),
            ListTile(
              leading: const Icon(Icons.task_alt),
              title: const Text('Done again now'),
              onTap: () => Navigator.pop(ctx, false),
            ),
            if (canUndo)
              ListTile(
                leading: const Icon(Icons.undo),
                title: Text(when.isEmpty ? 'Undo the last Done' : 'Undo the $when Done'),
                onTap: () => Navigator.pop(ctx, true),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (undo == null) return;
    undo ? await _undo(c) : await _done(c);
  }

  /// Puts back the time and km from before the last Done.
  Future<void> _undo(Check c) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_undoKey(c.id));
    if (raw == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('${c.name} is up to date. Nothing to undo.')));
      }
      return;
    }
    final m = jsonDecode(raw) as Map<String, dynamic>;
    await _db.saveCheck(c.copyWith(
      lastDoneAt: m['at'] as String,
      lastDoneKm: (m['km'] as num).toInt(),
    ));
    await prefs.remove(_undoKey(c.id));
    await ServiceReminders.instance.rescheduleAll();
    await _load();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${c.name} marked not done')));
    }
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
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Text('CHECKS',
                          style: TextStyle(
                              color: colors.textSecondary,
                              fontSize: 11,
                              letterSpacing: 1.2,
                              fontWeight: FontWeight.w600)),
                    ),
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
                  padding: const EdgeInsets.only(left: 8, right: 8, bottom: 8),
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
                        // A circle when due, a tick once done: tap the
                        // circle to mark it done, the tick to undo.
                        c.isDue(now, widget.odometer)
                            ? IconButton(
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints.tightFor(
                                    width: 40, height: 40),
                                tooltip: 'Mark ${c.name} done',
                                icon: Icon(Icons.radio_button_unchecked,
                                    color: colors.textSecondary),
                                onPressed: () => _done(c),
                              )
                            : IconButton(
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints.tightFor(
                                    width: 40, height: 40),
                                tooltip: '${c.name}: done again or undo',
                                icon: Icon(Icons.task_alt,
                                    color: colors.primary),
                                onPressed: () => _tickMenu(c),
                              ),
                        const SizedBox(width: 2),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(c.name,
                                  style: TextStyle(
                                      color: colors.textPrimary,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600)),
                              Text(_status(c),
                                  style: c.isDue(now, widget.odometer)
                                      ? muted.copyWith(color: colors.danger)
                                      : muted),
                            ],
                          ),
                        ),
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
    final navigator = Navigator.of(context);
    await deleteWithUndo(
      context,
      message: '${c.name} deleted',
      rows: {
        'checks': ('id = ?', [c.id]),
      },
      delete: () async {
        await DatabaseHelper().deleteCheck(c.id);
        return const [];
      },
      changed: ServiceReminders.instance.rescheduleAll,
    );
    navigator.pop(true);
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
                        labelText: 'Days',
                        suffixText: 'days',
                        helperText: 'Every so many days'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _km,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: 'Km',
                        suffixText: 'km',
                        helperText: 'Or every so many km'),
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
