import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat, NumberFormat;
import 'package:shared_preferences/shared_preferences.dart';

import '../db/database_helper.dart';
import '../models/fuel_log.dart';
import '../models/service_type.dart';
import '../models/trip.dart';
import '../models/vehicle.dart';
import '../theme/app_colors.dart';
import '../utils/constants.dart';
import '../utils/cost_calculator.dart';
import '../utils/efficiency_calculator.dart';
import '../utils/odometer_reading.dart';
import '../utils/page_routes.dart';
import '../utils/service_schedule.dart';
import '../utils/tank_level_calculator.dart';
import '../utils/trend_calculator.dart';
import '../utils/trip_calculator.dart';
import '../utils/vehicle_manager.dart';
import '../utils/gauge_scale.dart';
import '../widgets/gauge_card.dart';
import '../widgets/trend_chart.dart';
import '../widgets/vehicle_icon.dart';
import '../widgets/vehicle_picker.dart' show showVehiclePicker;
import 'entry_form_screen.dart';
import 'refill_detail_screen.dart';
import 'service_screen.dart' show dueText, latestOdometer, serviceTypeNames;
import 'trip_screen.dart';
import 'trip_sheets.dart';
import 'readings_screen.dart';

/// The Dashboard tab: the active vehicle's gauge card, spend tiles and the
/// mileage of its last 12 full-tank segments.
class DashboardScreen extends StatefulWidget {
  final ValueNotifier<int> reload;

  /// Shows a fill-up in the Fuel tab. Without it, the mileage alert opens
  /// the fill-up's page instead.
  final ValueChanged<String>? onShowFillUp;

  const DashboardScreen({super.key, required this.reload, this.onShowFillUp});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _db = DatabaseHelper();
  Vehicle? _vehicle;
  List<FuelLog> _chrono = const [];
  Map<String, EfficiencyResult> _eff = const {};
  double? _average;
  CostStats? _cost;
  List<SegmentTrendPoint> _trend = const [];

  /// The gauge's custom From and To, or null for Auto.
  (double, double)? _scale;
  double? _tankLevel;
  NextService? _next;
  OdometerReading? _reading;
  Map<String, ServiceType> _types = const {};
  Trip? _trip;
  int? _odometer;
  double? _tripSpend;

  /// The last closed tank, when it came in far enough below average to
  /// flag and wasn't dismissed.
  SegmentTrendPoint? _drop;

  /// Partial fill-ups since the last full one, newest backwards.
  int _partialRun = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    widget.reload.addListener(_load);
    _load();
  }

  @override
  void didUpdateWidget(DashboardScreen old) {
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
    final vehicle = await loadActiveVehicle();
    final chrono = await _db.getAllLogsChrono(vehicle.id);
    final eff = calculateEfficiency(chrono);
    final overall = calculateBrandEfficiency(chrono);
    final cap = vehicle.tankCapacity ?? 0;
    final levels = calculateTankLevels(chrono, cap, eff);
    final services = await _db.getServices(vehicle.id);
    final reading = await loadReading(vehicle.id);
    final types = await _db.getServiceTypes();
    final odo = await latestOdometer(vehicle.id);
    final next = nextServiceFor(services, odo);
    final trip = await _db.activeTrip(vehicle.id);
    final avg = overall.totalLiters > 0 ? overall.overallEfficiency : null;
    final trend = calculateSegmentTrend(chrono);
    final scale = await loadGaugeScale(vehicle.id);
    final prefs = await SharedPreferences.getInstance();
    final pct = prefs.getInt(kMileageAlertKey) ?? kMileageAlertDefault;
    final dismissed = prefs.getString(mileageAlertDismissedKey(vehicle.id));
    final lastTank = trend.lastOrNull;
    final drop = pct > 0 &&
            avg != null &&
            trend.length >= 3 &&
            lastTank != null &&
            lastTank.kmPerLitre < avg * (1 - pct / 100) &&
            dismissed != lastTank.closedAt.toIso8601String()
        ? lastTank
        : null;
    if (!mounted) return;
    setState(() {
      _vehicle = vehicle;
      _chrono = chrono;
      _eff = eff;
      _average = avg;
      _cost = calculateCostStats(chrono);
      _trend = trend;
      _scale = scale;
      _drop = drop;
      _partialRun = chrono.reversed.takeWhile((l) => !l.fullTank).length;
      _trip = trip;
      _odometer = odo;
      _tripSpend = trip == null
          ? null
          : tripFuel(trip, chrono,
                  endOdometer: odo ?? trip.startOdometer, averageKmL: avg)
              ?.cost;
      _tankLevel = chrono.isEmpty ? null : levels[chrono.last.id];
      _next = next;
      _reading = reading;
      _types = {for (final t in types) t.id: t};
      _loading = false;
    });
  }

  Future<void> _pickVehicle() async {
    final current = _vehicle;
    if (current == null) return;
    final vehicles = await _db.getVehicles();
    if (!mounted) return;
    final picked = await showVehiclePicker(
      context,
      vehicles: vehicles,
      selectedId: current.id,
    );
    if (picked == null) return;
    await setActiveVehicle(picked.id);
    // Every tab shows the active vehicle.
    widget.reload.value++;
  }

  /// Today's level from a reading taken after the last refill; without one,
  /// the level right after that refill.
  ({double litres, String caption, String note})? _tank(FuelLog? latest) {
    final after = _tankLevel;
    if (latest == null || after == null) return null;
    final avg = _average;
    final r = _reading;
    final left = tankNow(
        afterRefill: after,
        refillOdometer: latest.odometer,
        reading: r,
        avgKmL: avg);
    if (r != null && avg != null && left != null) {
      return (
        litres: left,
        caption: 'Left now, about',
        note: 'Enough for about ${(left * avg).round()} km, from your '
            '${_rupees.format(r.km)} km reading on '
            '${DateFormat('d MMM').format(r.at)}',
      );
    }
    final at = DateTime.tryParse(latest.timestamp);
    return (
      litres: after,
      caption: at == null
          ? 'In the tank after the last refill'
          : 'In the tank after the ${DateFormat('d MMM').format(at)} refill',
      note: avg == null || avg <= 0
          ? 'Add a reading to estimate what is left now'
          : 'Enough for about ${(after * avg).round()} km from that refill. '
              'Add a reading to estimate what is left now',
    );
  }

  Future<void> _updateReading() async {
    final v = _vehicle;
    if (v == null) return;
    if (await showOdometerDialog(context,
        vehicleId: v.id,
        vehicleName: v.name,
        onChanged: () => widget.reload.value++)) {
      widget.reload.value++;
    }
  }

  Future<void> _openReadings() async {
    final v = _vehicle;
    if (v == null) return;
    await Navigator.push(
        context,
        SmoothPageRoute(
            page: ReadingsScreen(vehicleId: v.id, vehicleName: v.name)));
    widget.reload.value++;
  }

  Future<void> _addFirst() async {
    final v = _vehicle;
    if (v == null) return;
    await Navigator.push(
      context,
      SmoothPageRoute(page: EntryFormScreen(vehicleId: v.id)),
    );
    widget.reload.value++;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                children: _content(AppColors.of(context)),
              ),
      ),
    );
  }

  List<Widget> _content(AppColors colors) {
    final values = _eff.values.map((e) => e.value).whereType<double>().toList();
    double? last;
    for (final log in _chrono.reversed) {
      final v = _eff[log.id]?.value;
      if (v != null) {
        last = v;
        break;
      }
    }
    final latest = _chrono.isEmpty ? null : _chrono.last;
    final tank = _tank(latest);
    final trend = _trend.length > 12
        ? _trend.sublist(_trend.length - 12)
        : _trend;

    return [
      _header(colors),
      if (_trip != null) ...[
        const SizedBox(height: 14),
        _tripCard(_trip!, colors),
      ],
      if (_drop != null) ...[
        const SizedBox(height: 14),
        _dropCard(_drop!, colors),
      ],
      if (_partialRun >= 3) ...[
        const SizedBox(height: 14),
        _fillFullCard(colors),
      ],
      const SizedBox(height: 14),
      GaugeCard(
        scale: _scale,
        onOdometerTap: _openReadings,
        averageKmL: _average,
        worst: values.isEmpty ? null : values.reduce(math.min),
        last: last,
        best: values.isEmpty ? null : values.reduce(math.max),
        odometerKm: _reading?.km ?? latest?.odometer,
        tankLitres: tank?.litres,
        tankCaption: tank?.caption,
        tankNote: tank?.note,
        onUpdateReading: _vehicle == null ? null : _updateReading,
        tankCapacity: _vehicle?.tankCapacity,
        emptyMessage: _chrono.isEmpty ? 'Add your first fill-up' : null,
      ),
      if (_vehicle?.monthlyBudget != null && _cost != null) ...[
        const SizedBox(height: 14),
        _budgetCard(_vehicle!.monthlyBudget!, _cost!.monthSpend, colors),
      ],
      if (_next != null) ...[
        const SizedBox(height: 14),
        _nextService(_next!, colors),
      ],
      if (_chrono.isEmpty) ...[
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: _addFirst,
          icon: const Icon(Icons.add),
          label: const Text('Add your first fill-up'),
        ),
      ] else ...[
        const SizedBox(height: 14),
        _tiles(colors),
        const SizedBox(height: 14),
        TrendChart(
          title: 'Mileage, last 12 refills',
          points: trend
              .map((p) => TrendPoint(p.closedAt, p.kmPerLitre))
              .toList(),
          formatValue: (v) => v.toStringAsFixed(1),
          emptyMessage: 'Appears after 2 completed full-tank segments.',
        ),
      ],
    ];
  }

  Widget _cap(String s, AppColors colors) => Text(s.toUpperCase(),
      style: TextStyle(
          color: colors.textSecondary,
          fontSize: 11,
          letterSpacing: 1.2,
          fontWeight: FontWeight.w600));

  /// The trip on now, with its km and spend so far.
  Widget _tripCard(Trip t, AppColors colors) {
    final since = DateTime.tryParse(t.startAt);
    final km = ((_odometer ?? t.startOdometer) - t.startOdometer).clamp(0, 1 << 30);
    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colors.secondary),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: () async {
                await Navigator.push(context,
                    SmoothPageRoute(page: TripScreen(tripId: t.id)));
                widget.reload.value++;
              },
              child: Row(
                children: [
                  Icon(Icons.route, color: colors.secondary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('On a trip · ${t.name}',
                            style: TextStyle(
                                color: colors.textPrimary,
                                fontSize: 16,
                                fontWeight: FontWeight.w600)),
                        Text(
                            [
                              if (since != null)
                                'Since ${DateFormat('E HH:mm').format(since)}',
                              '${_rupees.format(km)} km so far',
                              if (_tripSpend != null)
                                '₹${_rupees.format(_tripSpend)} spent',
                            ].join(' · '),
                            style: TextStyle(
                                color: colors.textSecondary, fontSize: 13)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      await _updateReading();
                      await refreshTripNotification(t.vehicleId);
                    },
                    icon: const Icon(Icons.speed, size: 18),
                    label: const Text('Odometer'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: () async {
                      final v = _vehicle;
                      if (v == null) return;
                      if (await showEndTripSheet(context, t, v)) {
                        widget.reload.value++;
                      }
                    },
                    child: const Text('End trip'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// The last tank came in well below average: say so, with what to check.
  Widget _dropCard(SegmentTrendPoint p, AppColors colors) {
    final avg = _average!;
    final pct = ((1 - p.kmPerLitre / avg) * 100).round();
    final checks = _vehicle?.type == VehicleType.bike
        ? 'tyre pressure, chain slack and the air filter'
        : 'tyre pressure, wheel alignment and the air filter';
    final closing = _chrono
        .where((l) => DateTime.tryParse(l.timestamp) == p.closedAt)
        .firstOrNull;
    // A rounded card with a warning bar down its left edge. Flutter can't
    // round a border that differs per side, so the bar is its own strip.
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: ColoredBox(
        color: colors.card,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 4, color: colors.warning),
              Expanded(child: _dropBody(p, pct, avg, checks, closing, colors)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dropBody(SegmentTrendPoint p, int pct, double avg, String checks,
      FuelLog? closing, AppColors colors) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 8, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.trending_down, color: colors.warning),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Mileage dropped',
                    style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w600)),
                Text(
                    'Last tank ${p.kmPerLitre.toStringAsFixed(1)} km/L, $pct% '
                    'below your ${avg.toStringAsFixed(1)}. Worth checking '
                    '$checks.',
                    style:
                        TextStyle(color: colors.textSecondary, fontSize: 13)),
                Row(
                  children: [
                    if (closing != null)
                      TextButton(
                        onPressed: () async {
                          final show = widget.onShowFillUp;
                          if (show != null) return show(closing.id);
                          await Navigator.push(
                              context,
                              SmoothPageRoute(
                                  page: RefillDetailScreen(logId: closing.id)));
                          widget.reload.value++;
                        },
                        child: const Text('See the fill-up'),
                      ),
                    const Spacer(),
                    TextButton(
                      onPressed: () async {
                        final v = _vehicle;
                        if (v == null) return;
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.setString(mileageAlertDismissedKey(v.id),
                            p.closedAt.toIso8601String());
                        if (mounted) setState(() => _drop = null);
                      },
                      child: const Text('Dismiss'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// After 3 or more partial fill-ups in a row: mileage can't be measured
  /// until a full tank, so say so before the next visit to the pump.
  Widget _fillFullCard(AppColors colors) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: ColoredBox(
        color: colors.card,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 4, color: colors.warning),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.local_gas_station, color: colors.warning),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Fill up full next time',
                                style: TextStyle(
                                    color: colors.textPrimary,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600)),
                            Text(
                                '$_partialRun partial fill-ups in a row. Mileage '
                                'and trip fuel need a full tank to measure.',
                                style: TextStyle(
                                    color: colors.textSecondary, fontSize: 13)),
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

  /// This month's fuel spend against the vehicle's budget.
  Widget _budgetCard(double budget, double spent, AppColors colors) {
    final now = DateTime.now();
    final daysLeft = DateTime(now.year, now.month + 1, 0).day - now.day + 1;
    final left = budget - spent;
    final over = left < 0;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                    child: _cap(
                        'Fuel budget · ${DateFormat('MMMM').format(now)}',
                        colors)),
                Text('$daysLeft ${daysLeft == 1 ? 'day' : 'days'} left',
                    style:
                        TextStyle(color: colors.textSecondary, fontSize: 12)),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Expanded(
                  child: Text('₹${_rupees.format(spent)}',
                      style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 22,
                          fontWeight: FontWeight.w700)),
                ),
                Text('of ₹${_rupees.format(budget)}',
                    style:
                        TextStyle(color: colors.textSecondary, fontSize: 13)),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: (spent / budget).clamp(0.0, 1.0),
                minHeight: 6,
                color: over
                    ? colors.danger
                    : spent / budget > 0.85
                        ? colors.warning
                        : colors.primary,
                backgroundColor: colors.cardBorder,
              ),
            ),
            const SizedBox(height: 6),
            Text(
                over
                    ? '₹${_rupees.format(-left)} over budget'
                    : '₹${_rupees.format(left)} left · about '
                        '₹${_rupees.format(left / daysLeft)} a day',
                style: TextStyle(
                    color: over ? colors.danger : colors.textSecondary,
                    fontSize: 13)),
          ],
        ),
      ),
    );
  }

  /// The app name, and on the right the active vehicle as a pill that opens
  /// the vehicle picker.
  Widget _header(AppColors colors) {
    final v = _vehicle;
    return Row(
      children: [
        Expanded(
          child: Text("My H'ness",
              style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.4)),
        ),
        if (v != null)
          Material(
            color: colors.card,
            shape: StadiumBorder(side: BorderSide(color: colors.cardBorder)),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: _pickVehicle,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 6, 12, 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    VehicleIcon.of(v, size: 26),
                    const SizedBox(width: 8),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 140),
                      child: Text(v.name,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: colors.primary,
                              fontSize: 15,
                              fontWeight: FontWeight.w600)),
                    ),
                    Icon(Icons.arrow_drop_down, color: colors.primary),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
  Widget _nextService(NextService n, AppColors colors) {
    final r = n.record;
    final at = [
      if (r.nextDueKm != null)
        '${NumberFormat('#,##,##0', 'en_IN').format(r.nextDueKm!)} km',
      if (r.nextDueDate != null)
        DateFormat('d MMM').format(DateTime.parse(r.nextDueDate!)),
    ].join(' or ');
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: colors.primaryTint,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.build_outlined, color: colors.primary),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'NEXT SERVICE',
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 11,
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${serviceTypeNames(r, _types)} at $at',
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: n.progress(),
                      minHeight: 5,
                      color: n.overdue ? colors.danger : colors.primarySoft,
                      backgroundColor: colors.cardBorder,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    dueText(n),
                    style: TextStyle(
                      color: n.overdue ? colors.danger : colors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tiles(AppColors colors) {
    final cost = _cost!;
    final now = DateTime.now();

    // Newest log that has a price, typed or worked out from its total.
    FuelLog? priced;
    double? price;
    for (final log in _chrono.reversed) {
      final p =
          log.pricePerLitre ?? computePricePerLitre(log.totalCost, log.liters);
      if (p != null) {
        priced = log;
        price = p;
        break;
      }
    }
    final pricedAt = priced == null
        ? null
        : DateTime.tryParse(priced.timestamp);

    // avgMonthlySpend is totalSpend over the months that have cost data.
    final avgMonthly = cost.avgMonthlySpend;
    final months = avgMonthly == null || avgMonthly <= 0
        ? 0
        : (cost.totalSpend / avgMonthly).round();

    final tiles = [
      _Tile(
        label: 'Cost / km',
        value: cost.costPerKm == null
            ? '—'
            : '₹${cost.costPerKm!.toStringAsFixed(2)}',
        caption: 'Fuel only',
      ),
      _Tile(
        label: 'This month',
        value: '₹${_rupees.format(cost.monthSpend)}',
        caption: 'Fuel spend, ${DateFormat('MMMM').format(now)}',
      ),
      _Tile(
        label: 'Avg / month',
        value: avgMonthly == null ? '—' : '₹${_rupees.format(avgMonthly)}',
        caption: months == 1 ? 'Over 1 month' : 'Over $months months',
      ),
      _Tile(
        label: 'Fuel price',
        value: price == null ? '—' : '₹${price.toStringAsFixed(2)}',
        unit: price == null ? null : ' /L',
        caption: priced == null
            ? 'No price yet'
            : [
                if (priced.pumpBrand.isNotEmpty) priced.pumpBrand,
                if (pricedAt != null) DateFormat('d MMM').format(pricedAt),
              ].join(', '),
      ),
    ];

    return Column(
      children: [
        for (var row = 0; row < 2; row++) ...[
          if (row > 0) const SizedBox(height: 12),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: tiles[row * 2]),
                const SizedBox(width: 12),
                Expanded(child: tiles[row * 2 + 1]),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Whole rupees with Indian digit grouping: 1,23,456.
final _rupees = NumberFormat('#,##,##0', 'en_IN');

/// One figure on the Dashboard: caption label, value, one-line note.
class _Tile extends StatelessWidget {
  final String label;
  final String value;
  final String? unit;
  final String caption;

  const _Tile({
    required this.label,
    required this.value,
    this.unit,
    required this.caption,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label.toUpperCase(),
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: 11,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text.rich(
              TextSpan(
                text: value,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
                children: [
                  if (unit != null)
                    TextSpan(
                      text: unit,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              caption,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: colors.textSecondary, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
