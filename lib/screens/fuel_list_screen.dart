import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat, NumberFormat;

import '../db/database_helper.dart';
import '../models/fuel_log.dart';
import '../models/pump.dart';
import '../models/vehicle.dart';
import '../theme/app_colors.dart';
import '../utils/cost_calculator.dart';
import '../utils/efficiency_calculator.dart';
import '../utils/page_routes.dart';
import '../utils/vehicle_manager.dart';
import '../widgets/brand_logo.dart';
import '../widgets/grade_sheet.dart';
import '../widgets/vehicle_picker.dart';
import 'entry_form_screen.dart';
import 'refill_detail_screen.dart';
import 'scan_photos_screen.dart';
import '../utils/undo_delete.dart';
import 'dart:async';

final _grouped = NumberFormat('#,##,##0', 'en_IN');

/// The Fuel tab: every fill-up of the active vehicle, newest first, under
/// month headers. Brand comes first on each row; km/L is coloured by the
/// vehicle's mileage band.
class FuelListScreen extends StatefulWidget {
  final ValueNotifier<int> reload;

  /// A fill-up to scroll to and mark; cleared once shown.
  final ValueNotifier<String?>? show;

  const FuelListScreen({super.key, required this.reload, this.show});

  @override
  State<FuelListScreen> createState() => _FuelListScreenState();
}

class _FuelListScreenState extends State<FuelListScreen> {
  final _db = DatabaseHelper();
  Vehicle? _vehicle;
  List<FuelLog> _logs = const [];
  Map<String, EfficiencyResult> _eff = const {};
  bool _loading = true;

  final _scroll = ScrollController();
  final _rowKeys = <String, GlobalKey>{};

  /// The row being marked, and a count that restarts its fade.
  String? _marked;
  int _markRun = 0;

  /// The filters under the title; null shows every fill-up. [_date] is a
  /// year ("2026") or a month ("2026-11").
  String? _pumpKey, _grade, _date;
  Map<String, Pump> _pumps = const {};

  bool get _filtered => _pumpKey != null || _grade != null || _date != null;

  /// A fill-up's pump, or its brand for one from before pumps existed.
  static String _pumpOf(FuelLog l) => l.pumpId ?? 'brand:${l.pumpBrand}';

  String _pumpLabel(String key) => _pumps[key]?.label ??
      (key.startsWith('brand:') && key.length > 6 ? key.substring(6) : 'Unknown');

  static String? _yearOf(FuelLog l) =>
      DateTime.tryParse(l.timestamp)?.year.toString();
  static String? _monthOf(FuelLog l) => switch (DateTime.tryParse(l.timestamp)) {
        final at? => DateFormat('yyyy-MM').format(at),
        null => null,
      };

  List<FuelLog> get _shown => [
        for (final l in _logs)
          if ((_pumpKey == null || _pumpOf(l) == _pumpKey) &&
              (_grade == null || l.fuelType == _grade) &&
              (_date == null ||
                  (_date!.length == 4 ? _yearOf(l) : _monthOf(l)) == _date))
            l,
      ];

  @override
  void initState() {
    super.initState();
    widget.reload.addListener(_load);
    widget.show?.addListener(_showRequested);
    _load();
  }

  @override
  void didUpdateWidget(FuelListScreen old) {
    super.didUpdateWidget(old);
    if (old.reload != widget.reload) {
      old.reload.removeListener(_load);
      widget.reload.addListener(_load);
    }
    if (old.show != widget.show) {
      old.show?.removeListener(_showRequested);
      widget.show?.addListener(_showRequested);
    }
  }

  @override
  void dispose() {
    widget.reload.removeListener(_load);
    widget.show?.removeListener(_showRequested);
    _scroll.dispose();
    super.dispose();
  }

  /// Scrolls to the fill-up the Dashboard asked for, then tints its row and
  /// lets the tint fade out over 2 seconds.
  Future<void> _showRequested() async {
    final id = widget.show?.value;
    if (id == null) return;
    widget.show!.value = null;
    // A filter could hide the row asked for.
    if (_filtered) setState(() => _pumpKey = _grade = _date = null);
    // Lets the tab switch bring this tab in first.
    await Future<void>.delayed(const Duration(milliseconds: 350));
    for (var i = 0; i < 30 && mounted; i++) {
      final row = _rowKeys[id]?.currentContext;
      if (row != null && row.mounted) {
        await Scrollable.ensureVisible(row,
            alignment: 0.3,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic);
        if (mounted) {
          setState(() {
            _marked = id;
            _markRun++;
          });
        }
        return;
      }
      // The list only builds rows near the screen: step down until it is.
      if (!_scroll.hasClients) return;
      final p = _scroll.position;
      if (p.pixels >= p.maxScrollExtent) return;
      _scroll.jumpTo(
          (p.pixels + p.viewportDimension).clamp(0.0, p.maxScrollExtent));
      await WidgetsBinding.instance.endOfFrame;
    }
  }

  Future<void> _load() async {
    try {
      final vehicle = await loadActiveVehicle();
      final logs = await _db.getAllLogs(vehicle.id);
      final chrono = await _db.getAllLogsChrono(vehicle.id);
      final pumps = await _db.getPumps();
      if (!mounted) return;
      setState(() {
        // Another vehicle's fill-ups start unfiltered.
        if (_vehicle != null && _vehicle!.id != vehicle.id) {
          _pumpKey = _grade = _date = null;
        }
        _pumps = {for (final p in pumps) p.id: p};
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

  Future<void> _open(Widget page) async {
    await Navigator.push(context, SmoothPageRoute(page: page));
    widget.reload.value++;
  }

  void _add() {
    final v = _vehicle;
    if (v != null) _open(EntryFormScreen(vehicleId: v.id));
  }

  /// Scan first, then the form filled from what was read. Back on the scan
  /// screen opens nothing; Skip opens a blank form.
  Future<void> _scan() async {
    final v = _vehicle;
    if (v == null) return;
    final last = await _db.getLastLog(v.id);
    if (!mounted) return;
    final outcome = await Navigator.push<ScanOutcome>(context,
        SmoothPageRoute(page: ScanPhotosScreen(lastOdometer: last?.odometer)));
    if (outcome == null || !mounted) return;
    await _open(EntryFormScreen(
        vehicleId: v.id, prefill: outcome.isEmpty ? null : outcome));
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
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  _header(colors),
                  if (_logs.isEmpty)
                    _empty(colors)
                  else ...[
                    _filters(colors),
                    ..._months(colors),
                  ],
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
            if (photoScanSupported)
              round(Icons.photo_camera_outlined, 'Scan photos to add a fill-up',
                  _scan),
            round(Icons.add, 'Add fill-up', _add),
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
          Text('Tap + to add your first fill-up.',
              style: TextStyle(color: colors.textSecondary, fontSize: 14)),
        ],
      ),
    );
  }

  /// Pump, fuel grade and date chips, then what the list now shows.
  Widget _filters(AppColors colors) {
    final shown = _shown;
    var spend = 0.0, litres = 0.0, km = 0.0, kmLitres = 0.0;
    for (final l in shown) {
      spend += l.totalCost ?? computeTotalCost(l.pricePerLitre, l.liters) ?? 0;
      litres += l.liters;
      final e = _eff[l.id];
      if (e?.value != null && e?.segmentDistance != null && e?.segmentLiters != null) {
        km += e!.segmentDistance!;
        kmLitres += e.segmentLiters!;
      }
    }
    Widget chip(String label, bool on, VoidCallback onTap) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: FilterChip(
            label: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(label),
              const Icon(Icons.expand_more, size: 18),
            ]),
            selected: on,
            showCheckmark: false,
            onSelected: (_) => onTap(),
          ),
        );
    final dateLabel = _date == null
        ? 'All dates'
        : _date!.length == 4
            ? _date!
            : DateFormat('MMM y').format(DateTime.parse('$_date-01'));
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                chip(_pumpKey == null ? 'All pumps' : _pumpLabel(_pumpKey!),
                    _pumpKey != null, _pickPump),
                chip(_grade ?? 'All grades', _grade != null, _pickGrade),
                chip(dateLabel, _date != null, _pickDate),
                if (_filtered)
                  TextButton(
                    onPressed: () =>
                        setState(() => _pumpKey = _grade = _date = null),
                    child: const Text('Clear'),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
              shown.isEmpty
                  ? 'No fill-ups match. Tap Clear to see them all.'
                  : [
                      '${shown.length} ${shown.length == 1 ? 'fill-up' : 'fill-ups'}',
                      if (spend > 0) '₹${_grouped.format(spend)}',
                      '${_grouped.format(litres.round())} L',
                      if (kmLitres > 0)
                        'avg ${(km / kmLitres).toStringAsFixed(1)} km/L',
                    ].join(' · '),
              style: TextStyle(color: colors.textSecondary, fontSize: 13)),
        ],
      ),
    );
  }

  /// A list of choices in a sheet; returns the picked key, or null when
  /// closed. "All" comes back as the empty string.
  Future<String?> _choose(String title, List<(String, String, int)> options,
      String? current) {
    final colors = AppColors.of(context);
    return showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints:
              BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.7),
          child: ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                child: Text(title, style: Theme.of(ctx).textTheme.titleMedium),
              ),
              for (final (key, label, count) in options)
                ListTile(
                  // Months sit under their year.
                  contentPadding: EdgeInsets.only(
                      left: key.length == 7 ? 40 : 24, right: 24),
                  title: Text(label),
                  subtitle: key.isEmpty
                      ? null
                      : Text('$count ${count == 1 ? 'fill-up' : 'fill-ups'}'),
                  trailing: (current ?? '') == key
                      ? Icon(Icons.check, color: colors.primary)
                      : null,
                  onTap: () => Navigator.pop(ctx, key),
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  /// Each key in [keys] with how many fill-ups it has, most first.
  static List<(String, int)> _counted(Iterable<String?> keys) {
    final n = <String, int>{};
    for (final k in keys.whereType<String>()) {
      n[k] = (n[k] ?? 0) + 1;
    }
    return n.entries.map((e) => (e.key, e.value)).toList()
      ..sort((a, b) => b.$2.compareTo(a.$2));
  }

  Future<void> _pickPump() async {
    final picked = await _choose('Pump', [
      ('', 'All pumps', 0),
      for (final (k, n) in _counted(_logs.map(_pumpOf))) (k, _pumpLabel(k), n),
    ], _pumpKey);
    if (picked != null && mounted) {
      setState(() => _pumpKey = picked.isEmpty ? null : picked);
    }
  }

  Future<void> _pickGrade() async {
    final picked = await _choose('Fuel grade', [
      ('', 'All grades', 0),
      for (final (k, n) in _counted(_logs.map((l) => l.fuelType))) (k, k, n),
    ], _grade);
    if (picked != null && mounted) {
      setState(() => _grade = picked.isEmpty ? null : picked);
    }
  }

  /// Years newest first, each followed by its months.
  Future<void> _pickDate() async {
    final years = _counted(_logs.map(_yearOf))
      ..sort((a, b) => b.$1.compareTo(a.$1));
    final months = _counted(_logs.map(_monthOf))
      ..sort((a, b) => b.$1.compareTo(a.$1));
    final picked = await _choose('Date', [
      ('', 'All dates', 0),
      for (final (y, n) in years) ...[
        (y, y, n),
        for (final (m, c) in months)
          if (m.startsWith(y))
            (m, DateFormat('MMMM').format(DateTime.parse('$m-01')), c),
      ],
    ], _date);
    if (picked != null && mounted) {
      setState(() => _date = picked.isEmpty ? null : picked);
    }
  }

  List<Widget> _months(AppColors colors) {
    final groups = <String, List<FuelLog>>{};
    for (final log in _shown) {
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
                _row(g.value[i], colors),
              ],
            ],
          ),
        ),
      ],
    ];
  }

  /// The grade sheet, then whatever was picked in it.
  Future<void> _tap(FuelLog log) async {
    final v = _vehicle;
    if (v == null) return;
    final action =
        await showGradeSheet(context, log: log, vehicle: v, eff: _eff[log.id]);
    if (!mounted || action == null) return;
    switch (action) {
      case GradeAction.open:
        await _open(RefillDetailScreen(logId: log.id));
      case GradeAction.edit:
        await _open(EntryFormScreen(logId: log.id));
      case GradeAction.delete:
        unawaited(deleteFillUpWithUndo(context, log,
            changed: () async => widget.reload.value++));
    }
  }

  Widget _row(FuelLog log, AppColors colors) {
    final at = DateTime.tryParse(log.timestamp);
    final total = log.totalCost ?? computeTotalCost(log.pricePerLitre, log.liters);
    final price =
        log.pricePerLitre ?? computePricePerLitre(log.totalCost, log.liters);
    final kmL = _eff[log.id]?.value;
    final sub = TextStyle(color: colors.textSecondary, fontSize: 13);
    // The same order on every row: price per litre, then km/L and cost per
    // km once the tank's mileage is known.
    final figures = [
      if (price != null) '₹${price.toStringAsFixed(2)}/L',
      if (kmL != null) '${kmL.toStringAsFixed(1)} km/L',
      if (kmL != null && price != null) '₹${(price / kmL).toStringAsFixed(2)}/km',
    ].join(' · ');

    final row = _rowContent(log, colors, at, total, sub, figures);
    return KeyedSubtree(
      key: _rowKeys.putIfAbsent(log.id, GlobalKey.new),
      child: log.id != _marked
          ? row
          : TweenAnimationBuilder<double>(
              key: ValueKey(_markRun),
              tween: Tween(begin: 1, end: 0),
              duration: const Duration(seconds: 2),
              curve: Curves.easeIn,
              builder: (_, t, child) => ColoredBox(
                  color: colors.primary.withValues(alpha: 0.16 * t),
                  child: child),
              child: row,
            ),
    );
  }

  Widget _rowContent(FuelLog log, AppColors colors, DateTime? at,
      double? total, TextStyle sub, String figures) {
    return InkWell(
      onTap: () => _tap(log),
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
                      style:
                          TextStyle(color: colors.textSecondary, fontSize: 11)),
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
                        if (total != null) '₹${_grouped.format(total)}',
                      ].join(' · '),
                      style: sub),
                  if (figures.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(figures,
                        style: sub.copyWith(
                            color: colors.textPrimary,
                            fontWeight: FontWeight.w500)),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (_vehicle != null) gradeChip(context, log, _vehicle!, _eff[log.id]),
          ],
        ),
      ),
    );
  }
}