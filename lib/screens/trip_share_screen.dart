import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:intl/intl.dart' show DateFormat, NumberFormat;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../db/database_helper.dart';
import '../models/fuel_log.dart';
import '../models/trip.dart';
import '../models/vehicle.dart';
import '../theme/app_colors.dart';
import '../utils/trip_calculator.dart';
import '../widgets/trip_strip.dart';
import 'service_screen.dart' show latestOdometer;

final _grouped = NumberFormat('#,##,##0', 'en_IN');

/// One trip on the year report's blue card, with the trip line across it,
/// shared as an image.
class TripShareScreen extends StatefulWidget {
  final String tripId;

  const TripShareScreen({super.key, required this.tripId});

  @override
  State<TripShareScreen> createState() => _TripShareScreenState();
}

class _TripShareScreenState extends State<TripShareScreen> {
  final _card = GlobalKey();
  Trip? _trip;
  Vehicle? _vehicle;
  List<FuelLog> _fills = const [];
  TripFuel? _fuel;
  int _end = 0;
  bool _sharing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = DatabaseHelper();
    final t = await db.getTrip(widget.tripId);
    if (t == null) {
      if (mounted) Navigator.pop(context);
      return;
    }
    final v = await db.getVehicle(t.vehicleId);
    final chrono = await db.getAllLogsChrono(t.vehicleId);
    final end = t.endOdometer ?? await latestOdometer(t.vehicleId) ?? t.startOdometer;
    final fills = await db.getTripLogs(t.id);
    if (!mounted) return;
    setState(() {
      _trip = t;
      _vehicle = v;
      _fills = fills;
      _end = end;
      _fuel = tripFuel(t, chrono, endOdometer: end, averageKmL: averageKmL(chrono));
    });
  }

  Future<void> _share() async {
    setState(() => _sharing = true);
    try {
      final boundary =
          _card.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('${(await getTemporaryDirectory()).path}/trip_${_trip!.id}.png');
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
    final t = _trip;
    if (t == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final f = _fuel;
    final km = (_end - t.startOdometer).clamp(0, 1 << 30);
    final start = DateTime.tryParse(t.startAt);
    final end = DateTime.tryParse(t.endAt ?? '');
    const light = Color(0xFFDCE6F5);
    const white = Color(0xFFFFFFFF);
    Widget line(String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
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
    final dates = [
      if (start != null) DateFormat('d MMM').format(start),
      if (end != null) DateFormat('d MMM y').format(end),
    ].join(' to ');
    return Scaffold(
      appBar: AppBar(title: const Text('Share trip')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
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
                  const Text("MY H'NESS · TRIP",
                      style: TextStyle(color: light, fontSize: 12, letterSpacing: 1.4)),
                  Text(t.name,
                      style: const TextStyle(
                          color: white, fontSize: 18, fontWeight: FontWeight.w700)),
                  Text(
                      [if (dates.isNotEmpty) dates, ?_vehicle?.name].join(' · '),
                      style: const TextStyle(color: light, fontSize: 13)),
                  const SizedBox(height: 12),
                  TripStrip(
                    startKm: t.startOdometer,
                    endKm: _end,
                    fillUpKms: [
                      for (final l in _fills)
                        if (l.odometer > t.startOdometer && l.odometer < _end)
                          l.odometer,
                    ],
                    lineColor: const Color(0xFFE0913A),
                    fillColor: white,
                    startColor: const Color(0xFF5FD08F),
                    endColor: const Color(0xFFF2867F),
                    labelColor: light,
                  ),
                  Text('${_grouped.format(km)} km',
                      style: const TextStyle(
                          color: white,
                          fontSize: 34,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.5)),
                  const SizedBox(height: 6),
                  if (f != null) ...[
                    line(
                        'Fuel',
                        '${f.litres.toStringAsFixed(1)} L'
                            '${f.cost == null ? '' : ' · ₹${_grouped.format(f.cost)}'}'),
                    if (f.kmPerLitre != null)
                      line('Mileage', '${f.kmPerLitre!.toStringAsFixed(1)} km/L'),
                    if (f.cost != null && km > 0)
                      line('Per km', '₹${(f.cost! / km).toStringAsFixed(2)}'),
                  ],
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
