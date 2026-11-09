import 'package:flutter/material.dart';

import '../models/vehicle.dart';
import '../theme/app_colors.dart';
import '../utils/vehicle_manager.dart';
import '../widgets/period_selector.dart';
import 'papers_screen.dart';
import 'service_screen.dart';
import 'trips_screen.dart';

/// The Garage tab: the active vehicle's services, trips and papers behind
/// one switch.
class GarageScreen extends StatefulWidget {
  final ValueNotifier<int> reload;

  /// Which list shows: 0 Service, 1 Trips, 2 Papers. AppShell sets it from
  /// a link.
  final ValueNotifier<int> section;

  const GarageScreen({super.key, required this.reload, required this.section});

  @override
  State<GarageScreen> createState() => _GarageScreenState();
}

class _GarageScreenState extends State<GarageScreen> {
  static const _labels = ['Service', 'Trips', 'Papers'];
  Vehicle? _vehicle;

  @override
  void initState() {
    super.initState();
    widget.reload.addListener(_load);
    widget.section.addListener(_onSection);
    _load();
  }

  @override
  void dispose() {
    widget.reload.removeListener(_load);
    widget.section.removeListener(_onSection);
    super.dispose();
  }

  void _onSection() => setState(() {});

  Future<void> _load() async {
    final v = await loadActiveVehicle();
    if (mounted) setState(() => _vehicle = v);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final section = widget.section.value.clamp(0, _labels.length - 1);
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Garage',
                      style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 34,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.5)),
                  Text(_vehicle?.name ?? '',
                      style: TextStyle(
                          color: colors.textSecondary,
                          fontSize: 15,
                          fontWeight: FontWeight.w500)),
                  const SizedBox(height: 12),
                  PeriodSelector(
                    months: section,
                    options: [for (var i = 0; i < _labels.length; i++) i],
                    label: (i) => _labels[i],
                    onChanged: (i) => widget.section.value = i,
                  ),
                ],
              ),
            ),
            Expanded(
              child: IndexedStack(
                index: section,
                children: [
                  ServiceScreen(reload: widget.reload),
                  TripsScreen(reload: widget.reload),
                  PapersScreen(reload: widget.reload),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
