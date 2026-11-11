import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat, NumberFormat;

import '../theme/app_colors.dart';
import '../utils/odometer_reading.dart';

final _grouped = NumberFormat('#,##,##0', 'en_IN');

/// A vehicle's odometer readings, newest first: when and how each was
/// entered. Deleting one makes the one before it current, with Undo.
class ReadingsScreen extends StatefulWidget {
  final String vehicleId;
  final String vehicleName;

  const ReadingsScreen(
      {super.key, required this.vehicleId, required this.vehicleName});

  @override
  State<ReadingsScreen> createState() => _ReadingsScreenState();
}

class _ReadingsScreenState extends State<ReadingsScreen> {
  List<LoggedReading>? _readings;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await loadReadings(widget.vehicleId);
    if (mounted) setState(() => _readings = list);
  }

  Future<void> _delete(LoggedReading r) async {
    await deleteReading(widget.vehicleId, r.at);
    await _load();
    if (!mounted) return;
    final next = _readings?.firstOrNull;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(next == null
          ? 'Deleted ${_grouped.format(r.km)} km'
          : 'Deleted ${_grouped.format(r.km)} km. '
              'Now ${_grouped.format(next.km)} km.'),
      persist: false,
      duration: const Duration(seconds: 6),
      action: SnackBarAction(
        label: 'Undo',
        onPressed: () async {
          await restoreReading(widget.vehicleId, r);
          await _load();
        },
      ),
    ));
  }

  String _when(DateTime at) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(at.year, at.month, at.day);
    final time = DateFormat('HH:mm').format(at);
    if (day == today) return 'Today $time';
    if (day == today.subtract(const Duration(days: 1))) return 'Yesterday $time';
    return DateFormat(at.year == now.year ? 'd MMM, HH:mm' : 'd MMM y, HH:mm')
        .format(at);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final muted = TextStyle(color: colors.textSecondary, fontSize: 13);
    final list = _readings;
    return Scaffold(
      appBar: AppBar(title: Text('Readings · ${widget.vehicleName}')),
      body: list == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                Text(
                    'Readings you enter outside a fill-up: in Update '
                    'odometer, on trips or from the reminder. The newest is '
                    'the one the tank estimate and reminders use.',
                    style: muted),
                const SizedBox(height: 16),
                if (list.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 48),
                    child: Text(
                        'No readings yet. Tap Enter odometer reading on the '
                        'Dashboard to add one.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: colors.textPrimary, fontSize: 16)),
                  )
                else
                  Card(
                    margin: EdgeInsets.zero,
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        for (var i = 0; i < list.length; i++) ...[
                          if (i > 0)
                            Divider(
                                height: 1,
                                indent: 16,
                                endIndent: 16,
                                color: colors.cardBorder),
                          ListTile(
                            leading: Icon(Icons.speed,
                                color: i == 0
                                    ? colors.primary
                                    : colors.textSecondary),
                            title: Text('${_grouped.format(list[i].km)} km',
                                style: TextStyle(
                                    color: colors.textPrimary,
                                    fontWeight: i == 0
                                        ? FontWeight.w600
                                        : FontWeight.w400)),
                            subtitle: Text(
                                [
                                  _when(list[i].at),
                                  readingSourceLabel(list[i].how),
                                  if (i == 0) 'current',
                                ].join(' · '),
                                style: muted),
                            trailing: IconButton(
                              tooltip: 'Delete this reading',
                              icon: Icon(Icons.delete_outline,
                                  color: colors.textSecondary),
                              onPressed: () => _delete(list[i]),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}
