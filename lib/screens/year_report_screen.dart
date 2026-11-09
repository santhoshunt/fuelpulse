import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:intl/intl.dart' show NumberFormat;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../db/database_helper.dart';
import '../models/fuel_log.dart';
import '../models/service_record.dart';
import '../models/trip.dart';
import '../models/vehicle.dart';
import '../theme/app_colors.dart';
import '../utils/cost_calculator.dart';
import '../utils/efficiency_calculator.dart';
import '../utils/period_filter.dart';
import '../utils/trend_calculator.dart';
import '../utils/vehicle_manager.dart';

final _grouped = NumberFormat('#,##,##0', 'en_IN');

/// One year of the active vehicle on one card, shared as an image.
class YearReportScreen extends StatefulWidget {
  /// Fixes "now" in tests.
  final DateTime? now;

  const YearReportScreen({super.key, this.now});

  @override
  State<YearReportScreen> createState() => _YearReportScreenState();
}

class _YearReportScreenState extends State<YearReportScreen> {
  final _card = GlobalKey();
  Vehicle? _vehicle;
  List<FuelLog> _chrono = const [];
  List<ServiceRecord> _services = const [];
  List<Trip> _trips = const [];
  List<int> _years = const [];
  late int _year = (widget.now ?? DateTime.now()).year;
  bool _sharing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = DatabaseHelper();
    final v = await loadActiveVehicle();
    final chrono = await db.getAllLogsChrono(v.id);
    final services = await db.getServices(v.id);
    final trips = await db.getTrips(v.id);
    final years = {
      for (final l in chrono) DateTime.tryParse(l.timestamp)?.year,
      for (final s in services) DateTime.tryParse(s.timestamp)?.year,
      _year,
    }.whereType<int>().toList()
      ..sort();
    if (!mounted) return;
    setState(() {
      _vehicle = v;
      _chrono = chrono;
      _services = services;
      _trips = trips;
      _years = years;
      if (!years.contains(_year)) _year = years.last;
    });
  }

  bool _inYear(String ts) => DateTime.tryParse(ts)?.year == _year;

  Future<void> _share() async {
    setState(() => _sharing = true);
    try {
      final boundary =
          _card.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File(
          '${(await getTemporaryDirectory()).path}/my_hness_$_year.png');
      await file.writeAsBytes(png!.buffer.asUint8List(), flush: true);
      await SharePlus.instance.share(ShareParams(files: [XFile(file.path)]));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("Couldn't share: $e")));
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final v = _vehicle;
    if (v == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final logs = [for (final l in _chrono) if (_inYear(l.timestamp)) l];
    final services = [for (final s in _services) if (_inYear(s.timestamp)) s];
    final trips = [for (final t in _trips) if (_inYear(t.startAt)) t];

    // Km: from the last reading before the year (else its first) to its
    // highest.
    final readings = [
      for (final l in logs) l.odometer,
      for (final s in services) s.odometer,
    ];
    final before = [
      for (final l in _chrono)
        if ((DateTime.tryParse(l.timestamp)?.year ?? _year) < _year) l.odometer,
    ];
    final km = readings.isEmpty
        ? 0
        : readings.reduce(math.max) -
            (before.isEmpty ? readings.reduce(math.min) : before.reduce(math.max));
    final fuelSpend = logs.fold<double>(
        0,
        (s, l) =>
            s + (l.totalCost ?? computeTotalCost(l.pricePerLitre, l.liters) ?? 0));
    final litres = logs.fold<double>(0, (s, l) => s + l.liters);
    final serviceSpend = services.fold<double>(0, (s, r) => s + (r.cost ?? 0));
    final window = logsInRange(_chrono, DateTime(_year),
        DateTime(_year, 12, 31, 23, 59, 59));
    final overall = calculateBrandEfficiency(window);
    final kmL = overall.totalLiters > 0 ? overall.overallEfficiency : null;
    final best = calculateSegmentTrend(_chrono)
        .where((p) => p.closedAt.year == _year)
        .map((p) => p.kmPerLitre)
        .fold<double?>(null, (m, x) => m == null || x > m ? x : m);
    final tripKm = trips.fold<int>(
        0,
        (s, t) =>
            s + math.max(0, (t.endOdometer ?? t.startOdometer) - t.startOdometer));

    const light = Color(0xFFDCE6F5);
    const white = Color(0xFFFFFFFF);
    Widget line(String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            children: [
              Expanded(
                  child: Text(label,
                      style: const TextStyle(color: light, fontSize: 15))),
              Text(value,
                  style: const TextStyle(
                      color: white, fontSize: 15, fontWeight: FontWeight.w600)),
            ],
          ),
        );
    final i = _years.indexOf(_year);
    return Scaffold(
      appBar: AppBar(title: const Text('Year report')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                tooltip: 'Earlier year',
                onPressed: i > 0 ? () => setState(() => _year = _years[i - 1]) : null,
                icon: const Icon(Icons.chevron_left),
              ),
              Text('$_year',
                  style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w600)),
              IconButton(
                tooltip: 'Later year',
                onPressed: i >= 0 && i < _years.length - 1
                    ? () => setState(() => _year = _years[i + 1])
                    : null,
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          const SizedBox(height: 8),
          RepaintBoundary(
            key: _card,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [colors.gaugeStart, colors.gaugeEnd],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("MY H'NESS · $_year",
                      style: const TextStyle(
                          color: light, fontSize: 12, letterSpacing: 1.4)),
                  Text(v.name,
                      style: const TextStyle(color: light, fontSize: 14)),
                  const SizedBox(height: 10),
                  Text('${_grouped.format(km)} km',
                      style: const TextStyle(
                          color: white,
                          fontSize: 38,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.5)),
                  const SizedBox(height: 10),
                  line('Fuel',
                      '₹${_grouped.format(fuelSpend)} · ${litres.toStringAsFixed(0)} L'),
                  line('Service',
                      '₹${_grouped.format(serviceSpend)} · ${services.length} ${services.length == 1 ? 'visit' : 'visits'}'),
                  if (kmL != null)
                    line(
                        'Mileage',
                        '${kmL.toStringAsFixed(1)} km/L'
                            '${best == null ? '' : ' · best ${best.toStringAsFixed(1)}'}'),
                  line('Trips',
                      '${trips.length} · ${_grouped.format(tripKm)} km'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 50,
            child: ElevatedButton.icon(
              onPressed: _sharing ? null : _share,
              icon: const Icon(Icons.ios_share),
              label: const Text('Share image'),
            ),
          ),
        ],
      ),
    );
  }
}
