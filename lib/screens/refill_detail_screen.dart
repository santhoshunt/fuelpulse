import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat, NumberFormat;

import '../db/database_helper.dart';
import '../models/fuel_log.dart';
import '../models/pump.dart';
import '../models/vehicle.dart';
import '../theme/app_colors.dart';
import '../utils/cost_calculator.dart';
import '../utils/efficiency_calculator.dart';
import '../utils/mileage_bands.dart';
import '../utils/page_routes.dart';
import '../utils/tank_level_calculator.dart';
import '../widgets/brand_logo.dart';
import 'entry_form_screen.dart';
import '../utils/undo_delete.dart';

final _grouped = NumberFormat('#,##,##0', 'en_IN');
final _money = NumberFormat('#,##,##0.00', 'en_IN');

/// One fill-up in full: what was bought, how far it went, the tank after
/// it, and notes. Edit opens the form; Delete confirms and closes.
class RefillDetailScreen extends StatefulWidget {
  final String logId;

  const RefillDetailScreen({super.key, required this.logId});

  @override
  State<RefillDetailScreen> createState() => _RefillDetailScreenState();
}

class _RefillDetailScreenState extends State<RefillDetailScreen> {
  final _db = DatabaseHelper();
  FuelLog? _log;
  Pump? _pump;
  Vehicle? _vehicle;
  FuelLog? _previous;
  FuelLog? _next;
  EfficiencyResult? _eff;
  double? _tankLevel;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final log = await _db.getLogById(widget.logId);
    if (log == null) {
      // Deleted elsewhere, or by the form opened from here.
      if (mounted) Navigator.pop(context);
      return;
    }
    final vehicle = await _db.getVehicle(log.vehicleId);
    final pumps = await _db.getPumps();
    final chrono = await _db.getAllLogsChrono(log.vehicleId);
    final eff = calculateEfficiency(chrono);
    final levels =
        calculateTankLevels(chrono, vehicle?.tankCapacity ?? 0, eff);
    final i = chrono.indexWhere((l) => l.id == log.id);
    if (!mounted) return;
    setState(() {
      _log = log;
      _pump = pumps.where((p) => p.id == log.pumpId).firstOrNull;
      _vehicle = vehicle;
      _previous = i > 0 ? chrono[i - 1] : null;
      _next = i >= 0 && i < chrono.length - 1 ? chrono[i + 1] : null;
      _eff = eff[log.id];
      _tankLevel = levels[log.id];
      _loading = false;
    });
  }

  Future<void> _edit() async {
    await Navigator.push(
        context, SmoothPageRoute(page: EntryFormScreen(logId: widget.logId)));
    await _load();
  }

  /// Deletes at once and closes the page; Undo shows on the list behind it.
  Future<void> _delete() async {
    final log = _log!;
    final navigator = Navigator.of(context);
    await deleteFillUpWithUndo(context, log);
    navigator.pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Fill-up'),
        centerTitle: true,
        actions: [
          if (_log != null)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: OutlinedButton(onPressed: _edit, child: const Text('Edit')),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: _content(colors),
            ),
    );
  }

  List<Widget> _content(AppColors colors) {
    final log = _log!;
    final at = DateTime.tryParse(log.timestamp);
    final price =
        log.pricePerLitre ?? computePricePerLitre(log.totalCost, log.liters);
    final total =
        log.totalCost ?? computeTotalCost(log.pricePerLitre, log.liters);
    final kmL = _eff?.value;
    final cap = _vehicle?.tankCapacity ?? 0;
    // Graded on mileage and, with a price, cost per km.
    final grade = kmL == null
        ? null
        : gradeOf(_vehicle ?? const Vehicle(id: '', name: '', createdAt: ''),
                kmL, price)
            .grade;
    final brightness = Theme.of(context).brightness;

    return [
      Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              BrandLogo(brandName: log.pumpBrand, size: 52),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(log.pumpBrand.isEmpty ? 'Unknown' : log.pumpBrand,
                        style: TextStyle(
                            color: colors.textPrimary,
                            fontSize: 20,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(
                        [
                          if (_pump?.name.isNotEmpty ?? false) _pump!.name,
                          at == null
                              ? log.timestamp
                              : DateFormat('d MMM y, h:mm a').format(at),
                        ].join(' · '),
                        style: TextStyle(
                            color: colors.textSecondary, fontSize: 14)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                      !log.fullTank
                          ? 'Partial'
                          : kmL == null
                              ? '—'
                              : kmL.toStringAsFixed(1),
                      style: TextStyle(
                          color: kmL == null || !log.fullTank
                              ? colors.textSecondary
                              : bandColor(grade!, brightness),
                          fontSize: log.fullTank ? 34 : 18,
                          fontWeight: FontWeight.w700,
                          height: 1)),
                  if (log.fullTank) ...[
                    const SizedBox(height: 2),
                    Text(
                        kmL == null
                            ? ((_eff?.isPending ?? false) ? 'pending' : 'km/L')
                            : 'km/L · ${MileageBands.names[grade!]}',
                        style: TextStyle(
                            color: colors.textSecondary, fontSize: 12)),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
      _section('Fuel', colors),
      _group(colors, [
        if (_pump?.name.isNotEmpty ?? false) ('Petrol pump', _pump!.name),
        ('Fuel grade', log.fuelType),
        ('Litres', '${log.liters.toStringAsFixed(2)} L'),
        if (price != null)
          ('Price per litre', '₹${price.toStringAsFixed(2)}'),
        if (total != null) ('Total paid', '₹${_money.format(total)}'),
        ('Tank', log.fullTank ? 'Filled to the top' : 'Topped up'),
      ]),
      _section('Distance', colors),
      _group(colors, [
        ('Odometer', '${_grouped.format(log.odometer)} km'),
        (
          'Driven before this fill-up',
          _previous == null
              ? 'First fill-up'
              : '${_grouped.format(log.odometer - _previous!.odometer)} km '
                  'since ${_day(_previous!)}'
        ),
        (
          'Driven on this fill-up',
          _next == null
              ? 'Shown after the next fill-up'
              : '${_grouped.format(_next!.odometer - log.odometer)} km '
                  'to ${_day(_next!)}'
        ),
      ]),
      _section('Mileage', colors),
      _group(colors, [
        if (!log.fullTank)
          ('Mileage', 'Counts towards the next full tank')
        else ...[
          (
            'Mileage',
            kmL == null
                ? 'Shown after the next full tank'
                : '${kmL.toStringAsFixed(1)} km/L'
          ),
          if (_eff?.segmentDistance != null)
            (
              'Measured over',
              '${_grouped.format(_eff!.segmentDistance!.round())} km, '
                  'full tank to full tank'
            ),
          if (price != null && kmL != null && kmL > 0)
            ('Fuel cost per km', '₹${(price / kmL).toStringAsFixed(2)}'),
        ],
      ]),
      if (_tankLevel != null && cap > 0) ...[
        _section('Tank after this fill-up', colors),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                        child: Text('Estimated level',
                            style: TextStyle(
                                color: colors.textPrimary, fontSize: 16))),
                    Text(
                        '${_tankLevel!.toStringAsFixed(1)} of '
                        '${cap == cap.roundToDouble() ? cap.toStringAsFixed(0) : cap.toStringAsFixed(1)} L',
                        style: TextStyle(
                            color: colors.textSecondary, fontSize: 16)),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: (_tankLevel! / cap).clamp(0.0, 1.0),
                    minHeight: 8,
                    color: colors.secondary,
                    backgroundColor: colors.cardBorder,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
      if (log.notes.isNotEmpty) ...[
        _section('Notes', colors),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(log.notes,
                style: TextStyle(color: colors.textSecondary, fontSize: 16)),
          ),
        ),
      ],
      const SizedBox(height: 20),
      OutlinedButton(
        onPressed: _delete,
        style: OutlinedButton.styleFrom(
          foregroundColor: colors.danger,
          side: BorderSide(color: colors.danger.withValues(alpha: 0.35)),
          minimumSize: const Size.fromHeight(48),
        ),
        child: const Text('Delete fill-up'),
      ),
    ];
  }

  String _day(FuelLog l) {
    final at = DateTime.tryParse(l.timestamp);
    return at == null ? '' : DateFormat('d MMM').format(at);
  }

  Widget _section(String title, AppColors colors) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
        child: Text(title,
            style: TextStyle(
                color: colors.textSecondary,
                fontSize: 15,
                fontWeight: FontWeight.w500)),
      );

  Widget _group(AppColors colors, List<(String, String)> rows) {
    return Card(
      margin: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0)
              Divider(
                  height: 1,
                  indent: 16,
                  endIndent: 16,
                  color: colors.cardBorder),
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 50),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                        child: Text(rows[i].$1,
                            style: TextStyle(
                                color: colors.textPrimary, fontSize: 16))),
                    const SizedBox(width: 12),
                    Text(rows[i].$2,
                        style: TextStyle(
                            color: colors.textSecondary, fontSize: 16)),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
