import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat, NumberFormat;

import '../db/database_helper.dart';
import '../models/fuel_log.dart';
import '../models/trip.dart';
import '../models/vehicle.dart';
import '../services/photo_scan.dart';
import '../services/service_reminders.dart';
import '../theme/app_colors.dart';
import '../utils/mileage_bands.dart' show bandColor;
import '../utils/odometer_reading.dart';
import '../widgets/option_picker.dart';
import 'scan_photos_screen.dart' show photoScanSupported;
import 'service_screen.dart' show latestOdometer;

final _grouped = NumberFormat('#,##,##0', 'en_IN');

/// Refreshes the ongoing trip notification with the km so far, when
/// [vehicleId] has a trip on.
Future<void> refreshTripNotification(String vehicleId) async {
  final db = DatabaseHelper();
  final t = await db.activeTrip(vehicleId);
  if (t == null) return;
  final v = await db.getVehicle(vehicleId);
  final odo = await latestOdometer(vehicleId) ?? t.startOdometer;
  await ServiceReminders.instance
      .showTrip(t, v?.name ?? '', (odo - t.startOdometer).clamp(0, 1 << 30));
}

/// Ends [t] at [odometer] and [at]: fill-ups after [at] leave the trip, the
/// notification goes, and a reading above the latest one is kept.
Future<Trip> endTrip(Trip t, int odometer, DateTime at) async {
  final db = DatabaseHelper();
  final ended = t.copyWith(endAt: at.toIso8601String(), endOdometer: odometer);
  await db.saveTrip(ended);
  await db.untagAfter(t.id, ended.endAt!);
  await ServiceReminders.instance.cancelTrip(t.id);
  final latest = await latestOdometer(t.vehicleId);
  if (latest == null || odometer > latest) await saveReading(t.vehicleId, odometer);
  return ended;
}

/// Asks for a trip's name and start odometer, and starts it. Returns the
/// trip, or null when cancelled.
Future<Trip?> showStartTripSheet(BuildContext context, Vehicle v) async {
  final db = DatabaseHelper();
  final odo = await latestOdometer(v.id);
  final last = await db.getLastLog(v.id);
  if (!context.mounted) return null;
  return showModalBottomSheet<Trip>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _StartSheet(vehicle: v, odometer: odo, last: last),
  );
}

class _StartSheet extends StatefulWidget {
  final Vehicle vehicle;
  final int? odometer;
  final FuelLog? last;

  const _StartSheet({required this.vehicle, this.odometer, this.last});

  @override
  State<_StartSheet> createState() => _StartSheetState();
}

class _StartSheetState extends State<_StartSheet> {
  late final _name = TextEditingController(
      text: 'Trip on ${DateFormat('d MMM').format(DateTime.now())}');
  late final _odo =
      TextEditingController(text: widget.odometer?.toString() ?? '');
  bool _fromFill = false;
  String? _error;

  /// The last fill-up, when it was a full tank today: the trip can start on
  /// it, which lets its fuel come out exact.
  FuelLog? get _fullToday {
    final l = widget.last;
    final at = DateTime.tryParse(l?.timestamp ?? '');
    final now = DateTime.now();
    if (l == null || !l.fullTank || at == null) return null;
    return at.year == now.year && at.month == now.month && at.day == now.day
        ? l
        : null;
  }

  @override
  void dispose() {
    _name.dispose();
    _odo.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    final v = await scanOdometer(widget.odometer);
    if (!mounted) return;
    if (v == null) {
      setState(() => _error = "Couldn't read the odometer; type it in");
    } else {
      setState(() {
        _odo.text = '$v';
        _error = null;
        _fromFill = false;
      });
    }
  }

  Future<void> _start() async {
    final km = int.tryParse(_odo.text.trim());
    if (km == null || km < 0) {
      setState(() => _error = 'Enter the odometer reading');
      return;
    }
    final fill = _fromFill ? _fullToday : null;
    final db = DatabaseHelper();
    final t = Trip(
      id: Trip.generateId(),
      vehicleId: widget.vehicle.id,
      name: _name.text.trim().isEmpty ? 'Trip' : _name.text.trim(),
      startAt: fill?.timestamp ?? DateTime.now().toIso8601String(),
      startOdometer: fill?.odometer ?? km,
    );
    await db.saveTrip(t);
    if (fill != null) await db.updateLog(fill.copyWith(tripId: t.id));
    final latest = widget.odometer;
    if (fill == null && (latest == null || km > latest)) {
      await saveReading(widget.vehicle.id, km);
    }
    await ServiceReminders.instance.askPermission();
    await ServiceReminders.instance.showTrip(t, widget.vehicle.name, 0);
    if (mounted) Navigator.pop(context, t);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final full = _fullToday;
    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 0, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Start a trip',
              style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 14),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Name'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _odo,
            enabled: !_fromFill,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Odometer now',
              suffixText: 'km',
              prefixIcon: const Icon(Icons.speed),
              errorText: _error,
              suffixIcon: photoScanSupported && !_fromFill
                  ? IconButton(
                      tooltip: 'Read it from a photo',
                      icon: Icon(Icons.photo_camera_outlined,
                          color: colors.primary),
                      onPressed: _scan,
                    )
                  : null,
            ),
          ),
          if (full != null)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _fromFill,
              onChanged: (v) => setState(() {
                _fromFill = v ?? false;
                if (_fromFill) _odo.text = '${full.odometer}';
              }),
              title: const Text('I just filled the tank full'),
              subtitle: Text(
                  'Starts at that fill-up, ${_grouped.format(full.odometer)} km, '
                  'so the trip\'s fuel can come out exact.'),
            ),
          const SizedBox(height: 12),
          SizedBox(
            height: 50,
            child: ElevatedButton(onPressed: _start, child: const Text('Start')),
          ),
        ],
      ),
    );
  }
}

/// Asks where [t] ended (odometer and time), with the trip's last fill-up
/// and "now" as one-tap suggestions, and ends it. True when it ended.
Future<bool> showEndTripSheet(BuildContext context, Trip t, Vehicle v) async {
  final db = DatabaseHelper();
  final fills = await db.getTripLogs(t.id);
  final chrono = await db.getAllLogsChrono(v.id);
  final odo = await latestOdometer(v.id);
  if (!context.mounted) return false;
  final ended = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _EndSheet(
        trip: t, fills: fills, chrono: chrono, odometer: odo, vehicle: v),
  );
  return ended ?? false;
}

class _EndSheet extends StatefulWidget {
  final Trip trip;
  final List<FuelLog> fills;
  final List<FuelLog> chrono;
  final int? odometer;
  final Vehicle vehicle;

  const _EndSheet({
    required this.trip,
    required this.fills,
    required this.chrono,
    required this.odometer,
    required this.vehicle,
  });

  @override
  State<_EndSheet> createState() => _EndSheetState();
}

class _EndSheetState extends State<_EndSheet> {
  late final FuelLog? _lastFill = widget.fills.lastOrNull;
  late final _odo = TextEditingController(
      text: '${_lastFill?.odometer ?? widget.odometer ?? widget.trip.startOdometer}');
  late DateTime _at = _lastFill == null
      ? DateTime.now()
      : DateTime.tryParse(_lastFill.timestamp) ?? DateTime.now();
  String? _error;

  @override
  void initState() {
    super.initState();
    _odo.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _odo.dispose();
    super.dispose();
  }

  String _when(DateTime d) {
    final now = DateTime.now();
    final today = d.year == now.year && d.month == now.month && d.day == now.day;
    return DateFormat(today ? 'HH:mm' : 'E d MMM, HH:mm').format(d);
  }

  Future<void> _pickWhen() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _at,
      firstDate: DateTime.tryParse(widget.trip.startAt) ?? DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (d == null || !mounted) return;
    final tm = await showTimePicker(
        context: context, initialTime: TimeOfDay.fromDateTime(_at));
    if (!mounted) return;
    setState(() => _at = DateTime(
        d.year, d.month, d.day, tm?.hour ?? _at.hour, tm?.minute ?? _at.minute));
  }

  Future<void> _end() async {
    final km = int.tryParse(_odo.text.trim());
    final t = widget.trip;
    final started = DateTime.tryParse(t.startAt);
    final highest = [
      for (final l in widget.fills)
        if (!(DateTime.tryParse(l.timestamp)?.isAfter(_at) ?? false)) l.odometer,
    ].fold<int?>(null, (m, k) => m == null || k > m ? k : m);
    String? error;
    if (km == null) {
      error = 'Enter the odometer reading';
    } else if (km < t.startOdometer) {
      error = 'Lower than the start (${_grouped.format(t.startOdometer)} km)';
    } else if (highest != null && km < highest) {
      error = 'Lower than the fill-up at ${_grouped.format(highest)} km on this trip';
    } else if (started != null && _at.isBefore(started)) {
      error = 'Ends before it started';
    }
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    await endTrip(t, km!, _at);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final green = bandColor(4, Theme.of(context).brightness);
    final km = int.tryParse(_odo.text.trim());
    bool fullAt(int? k) =>
        k != null && widget.chrono.any((l) => l.fullTank && l.odometer == k);
    final endsFull = fullAt(km);
    final startsFull = fullAt(widget.trip.startOdometer);
    final last = _lastFill;
    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 0, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('End ${widget.trip.name}',
              style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              if (last != null)
                ActionChip(
                  avatar: Icon(Icons.local_gas_station_outlined,
                      size: 18, color: colors.primary),
                  label: Text(
                      '${_when(DateTime.tryParse(last.timestamp) ?? DateTime.now())} '
                      'fill-up · ${_grouped.format(last.odometer)}'),
                  onPressed: () => setState(() {
                    _odo.text = '${last.odometer}';
                    _at = DateTime.tryParse(last.timestamp) ?? _at;
                    _error = null;
                  }),
                ),
              if (widget.odometer != null)
                ActionChip(
                  avatar:
                      Icon(Icons.schedule, size: 18, color: colors.primary),
                  label: Text('Now · ${_grouped.format(widget.odometer)}'),
                  onPressed: () => setState(() {
                    _odo.text = '${widget.odometer}';
                    _at = DateTime.now();
                    _error = null;
                  }),
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _odo,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Ended at odometer',
              suffixText: 'km',
              prefixIcon: const Icon(Icons.speed),
              errorText: _error,
              suffixIcon: photoScanSupported
                  ? IconButton(
                      tooltip: 'Read it from a photo',
                      icon: Icon(Icons.photo_camera_outlined,
                          color: colors.primary),
                      onPressed: () async {
                        final v = await scanOdometer(widget.odometer);
                        if (v != null && mounted) {
                          setState(() => _odo.text = '$v');
                        }
                      },
                    )
                  : null,
            ),
          ),
          const SizedBox(height: 12),
          PickerField(
            label: 'Ended on',
            icon: Icons.event_outlined,
            onTap: _pickWhen,
            child: Text(DateFormat('E d MMM y, HH:mm').format(_at),
                style: TextStyle(color: colors.textPrimary, fontSize: 16)),
          ),
          if (endsFull) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.verified_outlined, size: 18, color: green),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                      startsFull
                          ? "Ends on a full fill-up, so this trip's fuel will be exact."
                          : "Ends on a full fill-up, so this trip's fuel is "
                              'measured from your fill-ups.',
                      style: TextStyle(color: colors.textSecondary, fontSize: 13)),
                ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            height: 50,
            child: ElevatedButton(onPressed: _end, child: const Text('End trip')),
          ),
        ],
      ),
    );
  }
}
