import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat, NumberFormat;

import '../db/database_helper.dart';
import '../models/fuel_log.dart';
import '../models/vehicle.dart';
import '../theme/app_colors.dart';
import '../utils/cost_calculator.dart';
import '../utils/efficiency_calculator.dart';
import '../utils/mileage_bands.dart';
import '../utils/page_routes.dart';
import '../utils/vehicle_manager.dart';
import '../widgets/brand_logo.dart';
import '../widgets/vehicle_picker.dart';
import 'entry_form_screen.dart';

final _grouped = NumberFormat('#,##,##0', 'en_IN');

/// The Fuel tab: every fill-up of the active vehicle, newest first, under
/// month headers. Brand comes first on each row; km/L is coloured by the
/// vehicle's mileage band.
class FuelListScreen extends StatefulWidget {
  final ValueNotifier<int> reload;

  const FuelListScreen({super.key, required this.reload});

  @override
  State<FuelListScreen> createState() => _FuelListScreenState();
}

class _FuelListScreenState extends State<FuelListScreen> {
  final _db = DatabaseHelper();
  Vehicle? _vehicle;
  List<FuelLog> _logs = const [];
  Map<String, EfficiencyResult> _eff = const {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    widget.reload.addListener(_load);
    _load();
  }

  @override
  void didUpdateWidget(FuelListScreen old) {
    super.didUpdateWidget(old);
    if (old.reload != widget.reload) {
      old.reload.removeListener(_load);
      widget.reload.addListener(_load);
    }
  }

  @override
  void dispose() {
    widget.reload.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final vehicle = await loadActiveVehicle();
      final logs = await _db.getAllLogs(vehicle.id);
      final chrono = await _db.getAllLogsChrono(vehicle.id);
      if (!mounted) return;
      setState(() {
        _vehicle = vehicle;
        _logs = logs;
        _eff = calculateEfficiency(chrono);
        _loading = false;
      });
    } catch (e) {
      debugPrint('Error loading data: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickVehicle() async {
    final current = _vehicle;
    if (current == null) return;
    final vehicles = await _db.getVehicles();
    if (!mounted) return;
    final picked = await showVehiclePicker(context,
        vehicles: vehicles, selectedId: current.id);
    if (picked == null) return;
    await setActiveVehicle(picked.id);
    widget.reload.value++;
  }

  Future<bool> _confirmDelete(FuelLog log) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Entry'),
        content: Text(
            'Delete the fill-up on ${log.odometer} km? This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.of(ctx).danger,
                foregroundColor: Colors.white),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<void> _delete(FuelLog log) async {
    await _db.deleteLog(log.id);
    widget.reload.value++;
  }

  Future<void> _open(Widget page) async {
    await Navigator.push(context, SmoothPageRoute(page: page));
    widget.reload.value++;
  }

  void _add() {
    final v = _vehicle;
    if (v != null) _open(EntryFormScreen(vehicleId: v.id));
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  _header(colors),
                  if (_logs.isEmpty) _empty(colors) else ..._months(colors),
                ],
              ),
      ),
    );
  }

  Widget _header(AppColors colors) {
    Widget round(IconData icon, String tip, VoidCallback onTap) => Padding(
          padding: const EdgeInsets.only(left: 10),
          child: Material(
            color: colors.card,
            shape: CircleBorder(side: BorderSide(color: colors.cardBorder)),
            child: IconButton(
              tooltip: tip,
              icon: Icon(icon, color: colors.primary),
              onPressed: onTap,
            ),
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            // The form opens with its photo scan card at the top.
            round(Icons.photo_camera_outlined, 'Scan photos to add a refill',
                _add),
            round(Icons.add, 'Add refill', _add),
          ],
        ),
        Text('Fuel',
            style: TextStyle(
                color: colors.textPrimary,
                fontSize: 34,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5)),
        if (_vehicle != null)
          InkWell(
            onTap: _pickVehicle,
            borderRadius: BorderRadius.circular(6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_vehicle!.name,
                    style: TextStyle(
                        color: colors.primary,
                        fontSize: 15,
                        fontWeight: FontWeight.w600)),
                Icon(Icons.arrow_drop_down, color: colors.primary),
              ],
            ),
          ),
      ],
    );
  }

  Widget _empty(AppColors colors) {
    return Padding(
      padding: const EdgeInsets.only(top: 96),
      child: Column(
        children: [
          Icon(Icons.local_gas_station_outlined,
              size: 72, color: colors.textSecondary.withValues(alpha: 0.5)),
          const SizedBox(height: 16),
          Text('No fill-ups yet',
              style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 6),
          Text('Tap + to add your first entry.',
              style: TextStyle(color: colors.textSecondary, fontSize: 14)),
        ],
      ),
    );
  }

  List<Widget> _months(AppColors colors) {
    final bands = defaultBandsFor(_vehicle?.type ?? VehicleType.car);
    final groups = <String, List<FuelLog>>{};
    for (final log in _logs) {
      final at = DateTime.tryParse(log.timestamp);
      final key = at == null ? 'Unknown date' : DateFormat('MMMM y').format(at);
      groups.putIfAbsent(key, () => []).add(log);
    }
    return [
      for (final g in groups.entries) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
          child: Text(g.key,
              style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: 15,
                  fontWeight: FontWeight.w500)),
        ),
        Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var i = 0; i < g.value.length; i++) ...[
                if (i > 0)
                  Divider(
                      height: 1,
                      indent: 14,
                      endIndent: 14,
                      color: colors.cardBorder),
                _row(g.value[i], bands, colors),
              ],
            ],
          ),
        ),
      ],
    ];
  }

  Widget _row(FuelLog log, MileageBands bands, AppColors colors) {
    final at = DateTime.tryParse(log.timestamp);
    final total = log.totalCost ?? computeTotalCost(log.pricePerLitre, log.liters);
    final price =
        log.pricePerLitre ?? computePricePerLitre(log.totalCost, log.liters);
    final money = [
      if (price != null) '₹${price.toStringAsFixed(2)}/L',
      if (total != null) '₹${_grouped.format(total)}',
    ].join(' · ');
    final sub = TextStyle(color: colors.textSecondary, fontSize: 13);

    return Dismissible(
      key: ValueKey(log.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: colors.danger,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      confirmDismiss: (_) => _confirmDelete(log),
      onDismissed: (_) => _delete(log),
      child: InkWell(
        onTap: () => _open(EntryFormScreen(logId: log.id)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              SizedBox(
                width: 52,
                child: Column(
                  children: [
                    BrandLogo(brandName: log.pumpBrand, size: 40),
                    const SizedBox(height: 3),
                    Text(log.fuelType,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: colors.textSecondary, fontSize: 11)),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(log.pumpBrand.isEmpty ? 'Unknown' : log.pumpBrand,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: colors.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(
                        [
                          if (at != null) DateFormat('d MMM').format(at),
                          '${_grouped.format(log.odometer)} km',
                          '${log.liters.toStringAsFixed(2)} L',
                        ].join(' · '),
                        style: sub),
                    if (money.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(money, style: sub),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _mileage(log, bands, colors),
            ],
          ),
        ),
      ),
    );
  }

  Widget _mileage(FuelLog log, MileageBands bands, AppColors colors) {
    if (!log.fullTank) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          border: Border.all(color: colors.cardBorder),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text('Partial',
            style: TextStyle(
                color: colors.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w600)),
      );
    }
    final e = _eff[log.id];
    final v = e?.value;
    final brightness = Theme.of(context).brightness;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(v == null ? '—' : v.toStringAsFixed(1),
            style: TextStyle(
                color: v == null
                    ? colors.textSecondary
                    : bandColor(bands.bandIndex(v), brightness),
                fontSize: 24,
                fontWeight: FontWeight.w700)),
        // Known once the next full tank shows how far this fuel went.
        Text(v == null && (e?.isPending ?? false) ? 'pending' : 'km/L',
            style: TextStyle(color: colors.textSecondary, fontSize: 12)),
      ],
    );
  }
}
