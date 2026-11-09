import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat, NumberFormat;

import '../db/database_helper.dart';
import '../models/service_record.dart';
import '../models/service_type.dart';
import '../models/vehicle.dart';
import '../models/workshop.dart';
import '../services/service_reminders.dart';
import '../theme/app_colors.dart';
import '../utils/odometer_reading.dart';
import '../utils/page_routes.dart';
import '../utils/service_schedule.dart';
import '../utils/vehicle_manager.dart';
import 'service_form_screen.dart';

final _grouped = NumberFormat('#,##,##0', 'en_IN');

/// The latest odometer known for a vehicle: from fill-ups, services or a
/// reading typed on the Dashboard or the Odometer widget.
Future<int?> latestOdometer(String vehicleId) async {
  final db = DatabaseHelper();
  final log = await db.getLastLog(vehicleId);
  final services = await db.getServices(vehicleId);
  final reading = await loadReading(vehicleId);
  final readings = [
    ?log?.odometer,
    ?reading?.km,
    for (final s in services) s.odometer,
  ];
  return readings.isEmpty ? null : readings.reduce(math.max);
}

/// "General service, Oil change" for a record's type ids.
String serviceTypeNames(ServiceRecord r, Map<String, ServiceType> types) {
  final names = [for (final id in r.typeIds) types[id]?.name ?? 'Service'];
  return names.isEmpty ? 'Service' : names.join(', ');
}

/// "N km left", "N days left", or how far past due.
String dueText(NextService n) {
  final km = n.kmLeft;
  final days = n.daysLeft;
  if (km != null && km <= 0) return '${_grouped.format(-km)} km overdue';
  if (days != null && days < 0) {
    return '${-days} ${days == -1 ? 'day' : 'days'} overdue';
  }
  final parts = [
    if (km != null) '${_grouped.format(km)} km',
    if (days != null) '$days ${days == 1 ? 'day' : 'days'}',
  ];
  return '${parts.join(' or ')} left';
}

/// The Service list in the Garage tab: the next scheduled service for the active vehicle and
/// its service history.
class ServiceScreen extends StatefulWidget {
  final ValueNotifier<int> reload;

  const ServiceScreen({super.key, required this.reload});

  @override
  State<ServiceScreen> createState() => _ServiceScreenState();
}

class _ServiceScreenState extends State<ServiceScreen> {
  final _db = DatabaseHelper();
  Vehicle? _vehicle;
  List<ServiceRecord> _services = const [];
  Map<String, ServiceType> _types = const {};
  Map<String, Workshop> _workshops = const {};
  int? _odometer;
  bool _loading = true;
  bool _notificationsOn = true;
  Map<String, int> _billCounts = const {};

  @override
  void initState() {
    super.initState();
    widget.reload.addListener(_load);
    _load();
  }

  @override
  void didUpdateWidget(ServiceScreen old) {
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
    final services = await _db.getServices(vehicle.id);
    final types = await _db.getServiceTypes();
    final ws = await _db.getWorkshops();
    final odo = await latestOdometer(vehicle.id);
    final on = await ServiceReminders.instance.enabled();
    final bills = await _db.attachmentCounts('service');
    if (!mounted) return;
    setState(() {
      _vehicle = vehicle;
      _services = services;
      _types = {for (final t in types) t.id: t};
      _workshops = {for (final w in ws) w.id: w};
      _odometer = odo;
      _notificationsOn = on;
      _billCounts = bills;
      _loading = false;
    });
  }

  Future<void> _open({ServiceRecord? record, List<String> types = const []}) async {
    final v = _vehicle;
    if (v == null) return;
    final changed = await Navigator.push<bool>(
      context,
      SmoothPageRoute(
        page: ServiceFormScreen(
          vehicleId: v.id,
          record: record,
          presetTypeIds: types,
          odometer: _odometer,
        ),
      ),
    );
    if (changed == true) widget.reload.value++;
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final next = nextServiceFor(_services, _odometer);
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Material(
                        color: colors.card,
                        shape: CircleBorder(
                            side: BorderSide(color: colors.cardBorder)),
                        child: IconButton(
                          tooltip: 'Add service',
                          icon: Icon(Icons.add, color: colors.primary),
                          onPressed: () => _open(),
                        ),
                      ),
                    ],
                  ),
                  if (_services.isEmpty)
                    _empty(colors)
                  else ...[
                    if (next != null) ...[
                      _section('Next scheduled', colors),
                      _nextCard(next, colors),
                      if (!_notificationsOn) _notificationsOff(colors),
                    ],
                    _section('History', colors),
                    _history(colors),
                  ],
                ],
              ),
      ),
    );
  }

  Widget _section(String t, AppColors colors) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
        child: Text(t,
            style: TextStyle(
                color: colors.textSecondary,
                fontSize: 15,
                fontWeight: FontWeight.w500)),
      );

  Widget _empty(AppColors colors) => Padding(
        padding: const EdgeInsets.only(top: 80),
        child: Column(
          children: [
            Icon(Icons.build_outlined,
                size: 64, color: colors.textSecondary.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            Text('No services yet',
                style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w500)),
            const SizedBox(height: 6),
            Text('Log a service to keep its history and get reminded of the '
                'next one.',
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.textSecondary, fontSize: 14)),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => _open(),
              icon: const Icon(Icons.add),
              label: const Text('Add service'),
            ),
          ],
        ),
      );

  /// Reminders still show here; this says the phone won't.
  Widget _notificationsOff(AppColors colors) => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Row(
          children: [
            Icon(Icons.notifications_off_outlined,
                size: 20, color: colors.textSecondary),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Notifications are off, so reminders show only here.',
                  style: TextStyle(color: colors.textSecondary, fontSize: 13)),
            ),
            TextButton(
              onPressed: () async {
                await ServiceReminders.instance.askPermission();
                await _load();
              },
              child: const Text('Turn on'),
            ),
          ],
        ),
      );

  Widget _nextCard(NextService n, AppColors colors) {
    final r = n.record;
    final due = [
      if (r.nextDueKm != null) '${_grouped.format(r.nextDueKm!)} km',
      if (r.nextDueDate != null)
        DateFormat('d MMM y').format(DateTime.parse(r.nextDueDate!)),
    ];
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(serviceTypeNames(r, _types),
                          style: TextStyle(
                              color: colors.textPrimary,
                              fontSize: 17,
                              fontWeight: FontWeight.w600)),
                      Text('Due at ${due.join(' or ')}',
                          style: TextStyle(
                              color: colors.textSecondary, fontSize: 13)),
                    ],
                  ),
                ),
                Text(dueText(n),
                    style: TextStyle(
                        color: n.overdue ? colors.danger : colors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: n.progress(),
                minHeight: 6,
                color: n.overdue ? colors.danger : colors.primarySoft,
                backgroundColor: colors.cardBorder,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text('Last done at ${_grouped.format(r.odometer)} km',
                      style: TextStyle(
                          color: colors.textSecondary, fontSize: 12)),
                ),
                if (_odometer != null)
                  Text('Now ${_grouped.format(_odometer!)} km',
                      style: TextStyle(
                          color: colors.textSecondary, fontSize: 12)),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: () => _open(types: r.typeIds),
                    child: const Text('Mark done'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _open(record: r),
                    child: const Text('Reschedule'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _history(AppColors colors) {
    final muted = TextStyle(color: colors.textSecondary, fontSize: 13);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < _services.length; i++) ...[
            if (i > 0)
              Divider(
                  height: 1,
                  indent: 16,
                  endIndent: 16,
                  color: colors.cardBorder),
            InkWell(
              onTap: () => _open(record: _services[i]),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(serviceTypeNames(_services[i], _types),
                              style: TextStyle(
                                  color: colors.textPrimary,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600)),
                          Text(
                              [
                                if (_workshops[_services[i].workshopId] != null)
                                  _workshops[_services[i].workshopId]!.name,
                                '${_grouped.format(_services[i].odometer)} km',
                              ].join(' · '),
                              style: muted),
                          Text(
                              DateFormat('d MMM y').format(
                                  DateTime.tryParse(_services[i].timestamp) ??
                                      DateTime.now()),
                              style: muted),
                          if ((_billCounts[_services[i].id] ?? 0) > 0)
                            Row(children: [
                              Icon(Icons.attach_file,
                                  size: 15, color: colors.textSecondary),
                              Text(
                                  _billCounts[_services[i].id] == 1
                                      ? '1 bill'
                                      : '${_billCounts[_services[i].id]} bills',
                                  style: muted),
                            ]),
                        ],
                      ),
                    ),
                    if (_services[i].cost != null)
                      Text('₹${_grouped.format(_services[i].cost!)}',
                          style: TextStyle(
                              color: colors.textPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.w600)),
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
