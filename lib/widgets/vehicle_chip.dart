import 'package:flutter/material.dart';
import '../models/vehicle.dart';
import '../utils/constants.dart';
import 'vehicle_picker.dart';

/// The Home screen's vehicle switcher: icon, name and a chevron in an
/// accent-bordered pill. Tapping opens the vehicle picker.
class VehicleChip extends StatelessWidget {
  final Vehicle vehicle;
  final VoidCallback onTap;

  const VehicleChip({super.key, required this.vehicle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;

    return Semantics(
      button: true,
      label: 'Vehicle: ${vehicle.name}. Tap to switch.',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: accent.withValues(alpha: 0.6)),
            color: Colors.white.withValues(alpha: 0.03),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(vehicleIcon(vehicle.type), color: kTextSecondary, size: 18),
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 220),
                child: Text(
                  vehicle.name,
                  style: const TextStyle(color: kTextPrimary, fontSize: 14),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 2),
              const Icon(Icons.keyboard_arrow_down_rounded,
                  color: kTextSecondary, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
