import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat, NumberFormat;
import 'package:shared_preferences/shared_preferences.dart';

import '../db/database_helper.dart';
import '../models/check.dart';
import '../services/home_widgets.dart';
import '../services/service_reminders.dart';
import '../theme/app_colors.dart';
import '../utils/undo_delete.dart';

final _grouped = NumberFormat('#,##,##0', 'en_IN');

/// "15 Nov" for an ISO time, or the text as it is when it won't parse.
String _dayMonth(String iso) {
  final at = DateTime.tryParse(iso);
  return at == null ? iso : DateFormat('d MMM').format(at);
}

String _dayMonthYear(String iso) {
  final at = DateTime.tryParse(iso);
  return at == null ? iso : DateFormat('d MMM y').format(at);
}

/// After Done: an optional value to keep with it. Pops the trimmed value,
/// or null for Skip.
class _ValueSheet extends StatefulWidget {
  final Check check;

  const _ValueSheet({required this.check});

  @override
  State<_ValueSheet> createState() => _ValueSheetState();
}

class _ValueSheetState extends State<_ValueSheet> {
  final _value = TextEditingController();

  @override
  void dispose() {
    _value.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.check;
    final last = c.history.firstOrNull;
    return Padding(
      // Keeps the field above the keyboard.
      padding: EdgeInsets.fromLTRB(
          24, 0, 24, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('${c.name} done', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          TextField(
            controller: _value,
            autofocus: true,
            textInputAction: TextInputAction.done,
            onSubmitted: (v) => Navigator.pop(context, v.trim()),
            decoration: InputDecoration(
              labelText: 'Value (optional)',
              suffixText: c.unit.isEmpty ? null : c.unit,
              helperText: last == null
                  ? 'Such as a pressure or a level. Kept with this Done.'
                  : 'Last time: ${c.withUnit(last.value)}, ${_dayMonth(last.at)}',
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Skip')),
              const SizedBox(width: 8),
              FilledButton(
                  onPressed: () => Navigator.pop(context, _value.text.trim()),
                  child: const Text('Save')),
            ],
          ),
        ],
      ),
    );
  }
}

/// Checks you do yourself on a schedule, for Garage → Service: each with
/// when it's due and a Done button that resets it.
class ChecksCard extends StatefulWidget {
  final String vehicleId;

  /// The latest odometer, for km-based checks and for Done.
  final int? odometer;

  /// Reloads the card when it fires: on a return to the app, which picks up
  /// a Done tapped on the Next check widget.
  final Listenable? reload;

  const ChecksCard(
      {super.key, required this.vehicleId, this.odometer, this.reload});

  @override
  State<ChecksCard> createState() => _ChecksCardState();
}

/// Where Done keeps the time and km it replaced, so the tick can undo it
/// until the next Done.
String _undoKey(String id) => 'fuel_check_undo_$id';

/// The check last marked done on the Next check widget, until the app has
/// offered Undo for it.
const kCheckWidgetDoneKey = 'fuel_check_widget_done';

/// Marks [c] done now at [odometer], keeping what it replaced so the tick
/// can undo it, and returns the check as saved. For Done in the app and on
/// the Next check widget, which runs with the app closed.
Future<Check> markCheckDone(Check c, int? odometer) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(
      _undoKey(c.id), jsonEncode({'at': c.lastDoneAt, 'km': c.lastDoneKm}));
  final done = c.copyWith(
    lastDoneAt: DateTime.now().toIso8601String(),
    lastDoneKm: odometer ?? c.lastDoneKm,
  );
  await DatabaseHelper().saveCheck(done);
  await ServiceReminders.instance.rescheduleAll();
  await HomeWidgets.refresh(chart: false);
  return done;
}

class _ChecksCardState extends State<ChecksCard> {
  final _db = DatabaseHelper();
  List<Check> _checks = const [];

  @override
  void initState() {
    super.initState();
    dataRestored.addListener(_load);
    widget.reload?.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    dataRestored.removeListener(_load);
    widget.reload?.removeListener(_load);
    super.dispose();
  }

  @override
  void didUpdateWidget(ChecksCard old) {
    super.didUpdateWidget(old);
    if (old.reload != widget.reload) {
      old.reload?.removeListener(_load);
      widget.reload?.addListener(_load);
    }
    if (old.vehicleId != widget.vehicleId || old.odometer != widget.odometer) {
      _load();
    }
  }

  Future<void> _load() async {
    final checks = await _db.getChecks(widget.vehicleId);
    if (!mounted) return;
    setState(() => _checks = checks);
    // A Done tapped on the Next check widget while the app was closed:
    // say so once, with Undo.
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString(kCheckWidgetDoneKey);
    final c = checks.where((c) => c.id == id).firstOrNull;
    if (c == null || !mounted) return;
    await prefs.remove(kCheckWidgetDoneKey);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('${c.name} marked done on the home screen widget'),
      persist: false,
      duration: const Duration(seconds: 6),
      action: SnackBarAction(label: 'Undo', onPressed: () => _undo(c)),
    ));
  }

  /// Marks [c] done at once, then offers to note a value with it.
  Future<void> _done(Check c) async {
    final done = await markCheckDone(c, widget.odometer);
    await _load();
    if (!mounted) return;
    final value = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ValueSheet(check: done),
    );
    if (value == null || value.isEmpty) return;
    await _db.saveCheck(done.copyWith(history: [
      (at: done.lastDoneAt, value: value),
      ...done.history,
    ].take(Check.keepValues).toList()));
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
      // The value noted with the Done being undone goes too.
      history: [for (final v in c.history) if (v.at != c.lastDoneAt) v],
    ));
    await prefs.remove(_undoKey(c.id));
    await ServiceReminders.instance.rescheduleAll();
    await HomeWidgets.refresh(chart: false);
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
      await HomeWidgets.refresh(chart: false);
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
                              if (c.history.isNotEmpty)
                                Text(
                                    'Last: ${c.withUnit(c.history.first.value)}, '
                                    '${_dayMonth(c.history.first.at)}',
                                    style: muted),
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
  late final _unit = TextEditingController(text: widget.check?.unit ?? '');
  String? _error;

  static const _presets = [
    ('Tyre pressure', 14, null, 'psi'),
    ('Chain lube', null, 500, ''),
    ('Coolant level', 30, null, ''),
    ('Engine oil level', 30, null, ''),
  ];

  @override
  void dispose() {
    _name.dispose();
    _days.dispose();
    _km.dispose();
    _unit.dispose();
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
            unit: _unit.text.trim(),
          )
        : c.copyWith(
            name: _name.text.trim(),
            everyDays: days,
            clearEveryDays: days == null,
            everyKm: km,
            clearEveryKm: km == null,
            unit: _unit.text.trim(),
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
      changed: () async {
        await ServiceReminders.instance.rescheduleAll();
        await HomeWidgets.refresh(chart: false);
      },
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
                  for (final (name, days, km, unit) in _presets)
                    ActionChip(
                      label: Text(name),
                      onPressed: () => setState(() {
                        _name.text = name;
                        _days.text = days?.toString() ?? '';
                        _km.text = km?.toString() ?? '';
                        _unit.text = unit;
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
            const SizedBox(height: 8),
            TextField(
              controller: _unit,
              decoration: const InputDecoration(
                  labelText: 'Unit (optional)',
                  helperText: 'For the value noted on Done, such as psi'),
            ),
            if (widget.check?.history.isNotEmpty ?? false) ...[
              const SizedBox(height: 16),
              Text('Past values',
                  style: TextStyle(
                      color: AppColors.of(context).textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
              for (final v in widget.check!.history)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    children: [
                      Expanded(child: Text(_dayMonthYear(v.at))),
                      Text(widget.check!.withUnit(v.value)),
                    ],
                  ),
                ),
            ],
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
