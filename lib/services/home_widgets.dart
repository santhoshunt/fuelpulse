import 'dart:io' show Platform;
import 'dart:math' as math;
import 'dart:ui' show DartPluginRegistrant;

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';
import 'package:intl/intl.dart' show DateFormat, NumberFormat;
import 'package:shared_preferences/shared_preferences.dart';

import '../db/database_helper.dart';
import '../models/check.dart';
import '../screens/checks_card.dart' show kCheckWidgetDoneKey, markCheckDone;
import '../screens/service_screen.dart' show dueText, latestOdometer;
import '../utils/cost_calculator.dart';
import '../utils/efficiency_calculator.dart';
import '../utils/odometer_reading.dart';
import '../utils/service_schedule.dart';
import '../utils/tank_level_calculator.dart';
import '../utils/trip_calculator.dart';
import '../utils/vehicle_manager.dart';

/// Done on the Next check widget, run by home_widget on a background
/// isolate so the app stays closed. The link names the check and the Done
/// it replaces; a second tap before the widget redraws finds that Done
/// already replaced and does nothing.
@pragma('vm:entry-point')
Future<void> homeWidgetTapped(Uri? uri) async {
  if (uri?.host != 'checkdone') return;
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  final id = uri!.queryParameters['id'];
  final c = (await DatabaseHelper().getEveryCheck())
      .where((c) => c.id == id)
      .firstOrNull;
  if (c == null || c.lastDoneAt != uri.queryParameters['at']) {
    await HomeWidgets.refresh(chart: false);
    return;
  }
  await markCheckDone(c, await latestOdometer(c.vehicleId));
  // The app offers Undo for it when it next opens.
  await (await SharedPreferences.getInstance())
      .setString(kCheckWidgetDoneKey, c.id);
}

/// Fills the Android home screen widgets (FuelWidgets.kt) for the active
/// vehicle and asks them to redraw. Called at launch and whenever the app's
/// data may have changed. Elsewhere it does nothing.
class HomeWidgets {
  static bool get supported => !kIsWeb && Platform.isAndroid;

  static const _widgets = [
    'MileageWidget',
    'QuickAddWidget',
    'TankWidget',
    'ServiceWidget',
    'SpendWidget',
    'BestPumpWidget',
    'OdometerWidget',
    'TripWidget',
    'CheckWidget',
  ];

  /// Lets the Next check widget's Done run [homeWidgetTapped]. Once per
  /// launch is enough; home_widget keeps the handle.
  static Future<void> registerTaps() async {
    if (!supported) return;
    try {
      await HomeWidget.registerInteractivityCallback(homeWidgetTapped);
    } catch (e) {
      debugPrint('Widget taps failed: $e');
    }
  }

  /// "Due in 2 days", "3 days overdue", "220 km left".
  static String _checkDue(Check c, DateTime now, int? odometer) {
    final days = c.daysLeft(now), km = c.kmLeft(odometer);
    if (days != null && days < 0) {
      return '${-days} ${days == -1 ? 'day' : 'days'} overdue';
    }
    if (km != null && km <= 0) return 'Due now';
    if (days == 0) return 'Due today';
    if (days != null) return 'Due in $days ${days == 1 ? 'day' : 'days'}';
    if (km != null) return '${_n.format(km)} km left';
    return '';
  }

  static final _n = NumberFormat('#,##,##0', 'en_IN');

  /// With [chart] false, leaves the Fuel spend chart as it was: drawing it
  /// needs the app's screen, which a background isolate does not have.
  static Future<void> refresh({bool chart = true}) async {
    if (!supported) return;
    try {
      final values = await _values();
      for (final e in values.entries) {
        await HomeWidget.saveWidgetData(e.key, e.value);
      }
      // Redraw first: drawing the spend chart is the slow part, and only
      // the Fuel spend widget shows it.
      for (final w in _widgets) {
        await HomeWidget.updateWidget(
            qualifiedAndroidName: 'com.fabletest.fuelpulse.$w');
      }
      if (!chart) return;
      await _spendChart();
      await HomeWidget.updateWidget(
          qualifiedAndroidName: 'com.fabletest.fuelpulse.SpendWidget');
    } catch (e) {
      debugPrint('Home widgets failed: $e');
    }
  }

  static Future<Map<String, Object?>> _values() async {
    final db = DatabaseHelper();
    final v = await loadActiveVehicle();
    final chrono = await db.getAllLogsChrono(v.id);
    final eff = calculateEfficiency(chrono);
    final overall = calculateBrandEfficiency(chrono);
    final avg = overall.totalLiters > 0 ? overall.overallEfficiency : null;
    final kmLs = eff.values.map((e) => e.value).whereType<double>().toList();
    double? last;
    for (final l in chrono.reversed) {
      last = eff[l.id]?.value;
      if (last != null) break;
    }
    final latest = chrono.isEmpty ? null : chrono.last;
    final cap = v.tankCapacity ?? 0;
    final after =
        latest == null ? null : calculateTankLevels(chrono, cap, eff)[latest.id];
    final reading = await loadReading(v.id);
    final left = after == null || latest == null
        ? null
        : tankNow(
            afterRefill: after,
            refillOdometer: latest.odometer,
            reading: reading,
            avgKmL: avg);
    final tank = left ?? after;
    final cost = calculateCostStats(chrono);
    final odo = await latestOdometer(v.id);
    final next = nextServiceFor(await db.getServices(v.id), odo);
    final types = {for (final t in await db.getServiceTypes()) t.id: t.name};

    // The pump with the best km/L, with its average price.
    final byPump = calculateGroupedEfficiency(chrono, (l) => l.pumpId ?? '',
        emptyKeyLabel: '');
    final best = byPump.rankings.where((g) => g.label.isNotEmpty).firstOrNull;
    String? pumpTitle;
    String? pumpFigures;
    if (best != null) {
      final pump =
          (await db.getPumps()).where((p) => p.id == best.label).firstOrNull;
      double spend = 0, litres = 0;
      for (final l in chrono.where((l) => l.pumpId == best.label)) {
        final p = l.pricePerLitre ?? computePricePerLitre(l.totalCost, l.liters);
        if (p == null) continue;
        spend += p * l.liters;
        litres += l.liters;
      }
      pumpTitle = pump?.label ?? 'Pump';
      pumpFigures = [
        '${best.weightedEfficiency.toStringAsFixed(1)} km/L',
        if (litres > 0)
          '₹${(spend / litres / best.weightedEfficiency).toStringAsFixed(2)}/km',
      ].join(' · ');
    }

    // The Trip widget: the trip on now, or the last one with Start.
    final trip = await db.activeTrip(v.id);
    final lastTrip = trip == null ? (await db.getTrips(v.id)).firstOrNull : null;
    final tripKm = trip == null
        ? 0
        : math.max(0, (odo ?? trip.startOdometer) - trip.startOdometer);
    final tripCost = trip == null
        ? null
        : tripFuel(trip, chrono,
                endOdometer: odo ?? trip.startOdometer, averageKmL: avg)
            ?.cost;
    final tripSince = trip == null ? null : DateTime.tryParse(trip.startAt);

    // The Next check widget: due ones first, then the soonest by days,
    // then by km.
    final now = DateTime.now();
    final checks = (await db.getChecks(v.id))
      ..sort((a, b) {
        int rank(Check c) => c.isDue(now, odo) ? 0 : 1;
        const far = 1 << 30;
        return rank(a) != rank(b)
            ? rank(a) - rank(b)
            : (a.daysLeft(now) ?? far) != (b.daysLeft(now) ?? far)
                ? (a.daysLeft(now) ?? far) - (b.daysLeft(now) ?? far)
                : (a.kmLeft(odo) ?? far) - (b.kmLeft(odo) ?? far);
      });
    final check = checks.firstOrNull;
    final alsoThisWeek = checks
        .skip(1)
        .where((c) => c.isDue(now, odo) || (c.daysLeft(now) ?? 8) <= 7)
        .length;

    final dueParts = next == null
        ? const <String>[]
        : [
            if (next.record.nextDueKm != null)
              '${_n.format(next.record.nextDueKm)} km',
            if (next.record.nextDueDate != null)
              DateFormat('d MMM')
                  .format(DateTime.parse(next.record.nextDueDate!)),
          ];
    return {
      'vehicle': v.name,
      'mileage_avg': avg?.toStringAsFixed(1) ?? '—',
      'mileage_sub': kmLs.isEmpty
          ? 'Needs two full-tank fill-ups'
          : 'Last ${last?.toStringAsFixed(1) ?? '—'} · '
              'Best ${kmLs.reduce(math.max).toStringAsFixed(1)}',
      'tank_value': tank == null || cap <= 0
          ? 'Set a tank size'
          : left != null
              ? 'About ${left.toStringAsFixed(1)} L left'
              : '${after!.toStringAsFixed(1)} of ${cap.toStringAsFixed(0)} L',
      'tank_sub': tank == null || avg == null
          ? ''
          : left != null
              ? 'about ${(left * avg).round()} km, from your reading'
              : 'about ${(after! * avg).round()} km after the last fill-up',
      'tank_percent': tank == null || cap <= 0 ? 0 : (tank / cap * 100).round(),
      'service_title': next == null
          ? 'Nothing scheduled'
          : '${[for (final id in next.record.typeIds) types[id] ?? 'Service'].join(', ')} at ${dueParts.join(' or ')}',
      'service_left': next == null ? '' : dueText(next),
      'service_percent': next == null ? 0 : (next.progress() * 100).round(),
      'spend_month': '₹${_n.format(cost.monthSpend)} this month',
      'spend_avg': v.monthlyBudget != null
          ? (cost.monthSpend > v.monthlyBudget!
              ? '₹${_n.format(cost.monthSpend - v.monthlyBudget!)} over the ₹${_n.format(v.monthlyBudget)} budget'
              : '₹${_n.format(v.monthlyBudget! - cost.monthSpend)} left of ₹${_n.format(v.monthlyBudget)}')
          : cost.avgMonthlySpend == null
              ? ''
              : 'average ₹${_n.format(cost.avgMonthlySpend)} a month',
      'pump_title': pumpTitle,
      'pump_figures': pumpFigures,
      'trip_title': trip == null
          ? 'No trip on'
          : '${trip.name} · ${_n.format(tripKm)} km',
      'trip_sub': trip != null
          ? [
              if (tripSince != null)
                'since ${DateFormat('E HH:mm').format(tripSince)}',
              if (tripCost != null) '₹${_n.format(tripCost)}',
            ].join(' · ')
          : lastTrip == null
              ? 'Start one as you leave'
              : 'last: ${lastTrip.name}, '
                  '${_n.format(math.max(0, (lastTrip.endOdometer ?? lastTrip.startOdometer) - lastTrip.startOdometer))} km',
      'trip_action': trip == null ? 'Start' : 'End',
      'trip_link': trip == null
          ? 'fuelpulse://starttrip?v=${v.id}'
          : 'fuelpulse://endtrip?v=${v.id}',
      'trip_open': trip == null
          ? 'fuelpulse://trips'
          : 'fuelpulse://trip?v=${v.id}',
      'check_title': check?.name ?? 'No checks yet',
      'check_sub': check == null
          ? 'Add one in Garage, Service'
          : [
              _checkDue(check, now, odo),
              // Short, and last: a narrow widget or large text cuts the
              // end of the line, never the due part.
              if (alsoThisWeek > 0) '$alsoThisWeek more this week',
            ].where((s) => s.isNotEmpty).join(' · '),
      // Empty hides Done.
      'check_done': check == null
          ? ''
          : Uri(scheme: 'fuelpulse', host: 'checkdone', queryParameters: {
              'id': check.id,
              'at': check.lastDoneAt,
            }).toString(),
      'odo_value': odo == null ? '—' : '${_n.format(odo)} km',
      'odo_sub': reading == null
          ? 'Tap Update to enter today\'s reading'
          : 'read ${DateFormat('d MMM').format(reading.at)}'
              '${left == null ? '' : ' · about ${left.toStringAsFixed(1)} L left'}',
    };
  }

  /// The last six months' fuel spend as bars, drawn to a PNG the Spend
  /// widget shows.
  static Future<void> _spendChart() async {
    final v = await loadActiveVehicle();
    final chrono = await DatabaseHelper().getAllLogsChrono(v.id);
    final now = DateTime.now();
    final start = DateTime(now.year, now.month - 5);
    final months = List<double>.filled(6, 0);
    for (final l in chrono) {
      final at = DateTime.tryParse(l.timestamp);
      final spend = l.totalCost ?? computeTotalCost(l.pricePerLitre, l.liters);
      if (at == null || spend == null || at.isBefore(start)) continue;
      final i = (at.year - start.year) * 12 + at.month - start.month;
      if (i >= 0 && i < 6) months[i] += spend;
    }
    final top = months.reduce(math.max);
    await HomeWidget.renderFlutterWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var i = 0; i < 6; i++)
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 5),
                      height: top > 0 ? math.max(3, 52 * months[i] / top) : 3,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE0913A),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      DateFormat('MMM')
                          .format(DateTime(start.year, start.month + i)),
                      style: const TextStyle(
                          color: Color(0xFFAFC0D8), fontSize: 11),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
      key: 'spend_chart',
      logicalSize: const Size(320, 80),
    );
  }
}
