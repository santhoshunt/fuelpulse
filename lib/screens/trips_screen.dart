import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat, NumberFormat;

import '../db/database_helper.dart';
import '../models/fuel_log.dart';
import '../models/trip.dart';
import '../models/vehicle.dart';
import '../theme/app_colors.dart';
import '../utils/mileage_bands.dart' show bandColor;
import '../utils/page_routes.dart';
import '../utils/trip_calculator.dart';
import '../utils/vehicle_manager.dart';
import 'papers_screen.dart' show statusTag;
import 'service_screen.dart' show latestOdometer;
import 'trip_screen.dart';
import 'trip_sheets.dart';

final _grouped = NumberFormat('#,##,##0', 'en_IN');

/// The badge for a trip's fuel figure.
Widget fuelQualityTag(BuildContext context, FuelQuality q) {
  final colors = AppColors.of(context);
  return switch (q) {
    FuelQuality.estimate => statusTag('Estimate', colors.warning),
    FuelQuality.measured => statusTag('Measured', colors.primary),
    FuelQuality.exact =>
      statusTag('Exact', bandColor(4, Theme.of(context).brightness)),
  };
}

/// The Trips list in the Garage tab: this year's trip totals, then every
/// trip, newest first.
class TripsScreen extends StatefulWidget {
  final ValueNotifier<int> reload;

  /// Bumped by the Garage + button while this list shows.
  final ValueNotifier<int>? addTaps;

  const TripsScreen({super.key, required this.reload, this.addTaps});

  @override
  State<TripsScreen> createState() => _TripsScreenState();
}

class _TripsScreenState extends State<TripsScreen> {
  final _db = DatabaseHelper();
  Vehicle? _vehicle;
  List<Trip> _trips = const [];
  Map<String, TripFuel?> _fuel = const {};
  int? _odometer;
  double? _average;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    widget.reload.addListener(_load);
    widget.addTaps?.addListener(_add);
    _load();
  }

  /// One trip at a time: + opens the trip on now, else starts one.
  void _add() {
    final active = _trips.where((t) => t.isActive).firstOrNull;
    active == null ? _start() : _open(active);
  }

  @override
  void didUpdateWidget(TripsScreen old) {
    super.didUpdateWidget(old);
    if (old.reload != widget.reload) {
      old.reload.removeListener(_load);
      widget.reload.addListener(_load);
    }
  }

  @override
  void dispose() {
    widget.reload.removeListener(_load);
    widget.addTaps?.removeListener(_add);
    super.dispose();
  }

  Future<void> _load() async {
    final v = await loadActiveVehicle();
    final trips = await _db.getTrips(v.id);
    final List<FuelLog> chrono = await _db.getAllLogsChrono(v.id);
    final odo = await latestOdometer(v.id);
    final avg = averageKmL(chrono);
    if (!mounted) return;
    setState(() {
      _vehicle = v;
      _trips = trips;
      _odometer = odo;
      _average = avg;
      _fuel = {
        for (final t in trips)
          t.id: tripFuel(t, chrono,
              endOdometer: t.endOdometer ?? odo ?? t.startOdometer,
              averageKmL: avg),
      };
      _loading = false;
    });
  }

  Future<void> _start() async {
    final v = _vehicle;
    if (v == null) return;
    final t = await showStartTripSheet(context, v);
    if (t != null) widget.reload.value++;
  }

  Future<void> _open(Trip t) async {
    await Navigator.push(
        context, SmoothPageRoute(page: TripScreen(tripId: t.id)));
    widget.reload.value++;
  }

  int _km(Trip t) =>
      ((t.endOdometer ?? _odometer ?? t.startOdometer) - t.startOdometer)
          .clamp(0, 1 << 30);

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    if (_loading) return const Center(child: CircularProgressIndicator());
    final muted = TextStyle(color: colors.textSecondary, fontSize: 13);
    final strong = TextStyle(
        color: colors.textPrimary, fontSize: 16, fontWeight: FontWeight.w600);
    final year = DateTime.now().year;
    final thisYear = [
      for (final t in _trips)
        if (DateTime.tryParse(t.startAt)?.year == year) t,
    ];
    final km = thisYear.fold<int>(0, (s, t) => s + _km(t));
    final litres =
        thisYear.fold<double>(0, (s, t) => s + (_fuel[t.id]?.litres ?? 0));
    final spend =
        thisYear.fold<double>(0, (s, t) => s + (_fuel[t.id]?.cost ?? 0));
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        if (_trips.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 60),
            child: Column(
              children: [
                Icon(Icons.route_outlined,
                    size: 64,
                    color: colors.textSecondary.withValues(alpha: 0.5)),
                const SizedBox(height: 16),
                Text('No trips yet',
                    style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w500)),
                const SizedBox(height: 6),
                Text(
                    'Start one as you leave, and see the km, fuel and cost '
                    'of just that trip.',
                    textAlign: TextAlign.center,
                    style: muted),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _start,
                  icon: const Icon(Icons.add),
                  label: const Text('Start a trip'),
                ),
              ],
            ),
          )
        else ...[
          const SizedBox(height: 8),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      '$year · ${thisYear.length} '
                      '${thisYear.length == 1 ? 'trip' : 'trips'}'
                          .toUpperCase(),
                      style: TextStyle(
                          color: colors.textSecondary,
                          fontSize: 11,
                          letterSpacing: 1.2,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Distance', style: muted),
                            Text('${_grouped.format(km)} km',
                                style: TextStyle(
                                    color: colors.textPrimary,
                                    fontSize: 22,
                                    fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('Fuel used (estimate)', style: muted),
                          Text('₹${_grouped.format(spend)}',
                              style: TextStyle(
                                  color: colors.textPrimary,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ],
                  ),
                  if (litres > 0)
                    Text(
                        '${(km / litres).toStringAsFixed(1)} km/L on trips'
                        '${_average == null ? '' : ' · ${_average!.toStringAsFixed(1)} overall'}',
                        style: muted),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            margin: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var i = 0; i < _trips.length; i++) ...[
                  if (i > 0)
                    Divider(
                        height: 1,
                        indent: 16,
                        endIndent: 16,
                        color: colors.cardBorder),
                  InkWell(
                    onTap: () => _open(_trips[i]),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(_trips[i].name, style: strong),
                                Text(
                                    [
                                      _trips[i].isActive
                                          ? 'On now'
                                          : DateFormat('d MMM y').format(
                                              DateTime.tryParse(
                                                      _trips[i].startAt) ??
                                                  DateTime.now()),
                                      '${_grouped.format(_km(_trips[i]))} km',
                                    ].join(' · '),
                                    style: muted),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              if (_fuel[_trips[i].id]?.cost != null)
                                Text(
                                    '₹${_grouped.format(_fuel[_trips[i].id]!.cost)}',
                                    style: strong),
                              if (_fuel[_trips[i].id] != null) ...[
                                const SizedBox(height: 4),
                                fuelQualityTag(
                                    context, _fuel[_trips[i].id]!.quality),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}
