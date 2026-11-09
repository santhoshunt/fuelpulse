import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat, NumberFormat;

import '../db/database_helper.dart';
import '../models/fuel_log.dart';
import '../models/trip.dart';
import '../models/vehicle.dart';
import '../services/service_reminders.dart';
import '../theme/app_colors.dart';
import '../utils/odometer_reading.dart';
import '../utils/page_routes.dart';
import '../utils/trip_calculator.dart';
import '../widgets/trip_strip.dart';
import 'refill_detail_screen.dart';
import 'service_screen.dart' show latestOdometer;
import 'settings/settings_widgets.dart' show confirmListDelete;
import 'trip_sheets.dart';
import 'trips_screen.dart' show fuelQualityTag;

final _grouped = NumberFormat('#,##,##0', 'en_IN');

/// One trip: where it ran on the odometer, its fuel, cost and mileage, and
/// the fill-ups made on it. A trip still on can be ended here.
class TripScreen extends StatefulWidget {
  final String tripId;

  const TripScreen({super.key, required this.tripId});

  @override
  State<TripScreen> createState() => _TripScreenState();
}

class _TripScreenState extends State<TripScreen> {
  final _db = DatabaseHelper();
  Trip? _trip;
  Vehicle? _vehicle;
  List<FuelLog> _fills = const [];
  TripFuel? _fuel;
  double? _average;
  int _end = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final t = await _db.getTrip(widget.tripId);
    if (t == null) {
      if (mounted) Navigator.pop(context);
      return;
    }
    final v = await _db.getVehicle(t.vehicleId);
    final chrono = await _db.getAllLogsChrono(t.vehicleId);
    final fills = await _db.getTripLogs(t.id);
    final odo = await latestOdometer(t.vehicleId);
    final avg = averageKmL(chrono);
    final end = t.endOdometer ?? odo ?? t.startOdometer;
    if (!mounted) return;
    setState(() {
      _trip = t;
      _vehicle = v;
      _fills = fills;
      _average = avg;
      _end = end;
      _fuel = tripFuel(t, chrono, endOdometer: end, averageKmL: avg);
    });
  }

  Future<void> _rename() async {
    final t = _trip!;
    final c = TextEditingController(text: t.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename trip'),
        content: TextField(controller: c, autofocus: true),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, c.text.trim()),
              child: const Text('Save')),
        ],
      ),
    );
    c.dispose();
    if (name == null || name.isEmpty) return;
    await _db.saveTrip(t.copyWith(name: name));
    if (t.isActive) await refreshTripNotification(t.vehicleId);
    await _load();
  }

  Future<void> _delete() async {
    final t = _trip!;
    final ok = await confirmListDelete(context, t.name,
        'Its fill-ups stay, no longer on a trip. This cannot be undone.');
    if (!ok) return;
    await _db.deleteTrip(t.id);
    await ServiceReminders.instance.cancelTrip(t.id);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _endTrip() async {
    final t = _trip, v = _vehicle;
    if (t == null || v == null) return;
    if (await showEndTripSheet(context, t, v)) await _load();
  }

  Future<void> _reading() async {
    final v = _vehicle;
    if (v == null) return;
    if (await showOdometerDialog(context,
        vehicleId: v.id, vehicleName: v.name)) {
      await refreshTripNotification(v.id);
      await _load();
    }
  }

  void _explain() {
    final f = _fuel;
    if (f == null) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('How the fuel was worked out'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final p in f.pieces)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                    '${_grouped.format(p.toKm - p.fromKm)} km at '
                    '${p.kmPerLitre.toStringAsFixed(1)} km/L = '
                    '${p.litres.toStringAsFixed(1)} L'
                    '${p.closed ? '' : ' (your average)'}'),
              ),
            const SizedBox(height: 6),
            Text(switch (f.quality) {
              FuelQuality.exact =>
                'Exact: the trip started and ended on full fill-ups.',
              FuelQuality.measured =>
                'Measured: each km uses the km/L of the full tank it was '
                    'driven on.',
              FuelQuality.estimate =>
                'Estimate: some km use your average until your next full '
                    'fill-up measures them.',
            }),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final t = _trip;
    if (t == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final f = _fuel;
    final km = (_end - t.startOdometer).clamp(0, 1 << 30);
    final start = DateTime.tryParse(t.startAt);
    final end = DateTime.tryParse(t.endAt ?? '');
    final muted = TextStyle(color: colors.textSecondary, fontSize: 13);
    final strong = TextStyle(
        color: colors.textPrimary, fontSize: 15, fontWeight: FontWeight.w600);
    Widget row(String label, Widget value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Expanded(
                  child: Text(label,
                      style: TextStyle(color: colors.textPrimary, fontSize: 15))),
              value,
            ],
          ),
        );
    return Scaffold(
      appBar: AppBar(
        title: Text(t.name),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) => v == 'rename' ? _rename() : _delete(),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'rename', child: Text('Rename')),
              PopupMenuItem(value: 'delete', child: Text('Delete trip')),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Text(
              [
                if (start != null) DateFormat('E d MMM, HH:mm').format(start),
                end == null
                    ? 'on now'
                    : DateFormat('E d MMM, HH:mm').format(end),
              ].join(' to '),
              style: muted),
          const SizedBox(height: 12),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 14, 12, 4),
              child: TripStrip(
                startKm: t.startOdometer,
                endKm: _end,
                fillUpKms: [
                  for (final l in _fills)
                    if (l.odometer > t.startOdometer && l.odometer < _end)
                      l.odometer,
                ],
              ),
            ),
          ),
          if (t.isActive) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                      onPressed: _reading,
                      child: const Text('Update odometer')),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                      onPressed: _endTrip, child: const Text('End trip')),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                children: [
                  row('Distance', Text('${_grouped.format(km)} km', style: strong)),
                  if (f == null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Text(
                          'Fuel appears after two full-tank fill-ups.',
                          style: muted),
                    )
                  else ...[
                    row(
                      'Fuel',
                      InkWell(
                        onTap: _explain,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            fuelQualityTag(context, f.quality),
                            const SizedBox(width: 8),
                            Text('${f.litres.toStringAsFixed(1)} L',
                                style: strong),
                          ],
                        ),
                      ),
                    ),
                    if (f.cost != null)
                      row('Fuel cost',
                          Text('₹${_grouped.format(f.cost)}', style: strong)),
                    if (f.kmPerLitre != null)
                      row(
                          'Mileage',
                          Text('${f.kmPerLitre!.toStringAsFixed(1)} km/L',
                              style: strong)),
                    if (_average != null)
                      row('Your average',
                          Text('${_average!.toStringAsFixed(1)} km/L',
                              style: muted)),
                    if (f.cost != null && km > 0)
                      row(
                          'Fuel cost per km',
                          Text('₹${(f.cost! / km).toStringAsFixed(2)}',
                              style: strong)),
                  ],
                ],
              ),
            ),
          ),
          if (_fills.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text('On this trip',
                style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 15,
                    fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            Card(
              margin: EdgeInsets.zero,
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (final l in _fills)
                    ListTile(
                      leading: Icon(Icons.local_gas_station_outlined,
                          color: colors.primary),
                      title: Text(
                          '${l.liters.toStringAsFixed(1)} L'
                          '${l.pumpBrand.isEmpty ? '' : ', ${l.pumpBrand}'}'),
                      subtitle: Text(
                          '${DateFormat('E d MMM, HH:mm').format(DateTime.tryParse(l.timestamp) ?? DateTime.now())}'
                          ' · ${_grouped.format(l.odometer)} km'),
                      trailing: l.totalCost == null
                          ? null
                          : Text('₹${_grouped.format(l.totalCost)}',
                              style: strong),
                      onTap: () async {
                        await Navigator.push(
                            context,
                            SmoothPageRoute(
                                page: RefillDetailScreen(logId: l.id)));
                        await _load();
                      },
                    ),
                ],
              ),
            ),
          ],
          if (t.notes.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(t.notes, style: muted),
          ],
        ],
      ),
    );
  }
}
