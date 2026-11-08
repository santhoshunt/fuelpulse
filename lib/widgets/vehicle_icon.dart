import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../models/vehicle.dart';
import '../utils/custom_pictures.dart';

/// OpenMoji pictures (openmoji.org, CC BY-SA 4.0) a vehicle can show.
const kVehiclePictures = {
  'motorcycle': 'Motorcycle',
  'scooter': 'Scooter',
  'car': 'Car',
  'truck': 'Truck',
};

/// The pictures offered for a vehicle type, default first.
List<String> picturesFor(VehicleType t) => switch (t) {
      VehicleType.bike => const ['motorcycle', 'scooter'],
      VehicleType.car => const ['car'],
      VehicleType.other => const ['truck'],
    };

/// A vehicle's picture: your own (`file:` icon), the chosen OpenMoji one,
/// or its type's default.
class VehicleIcon extends StatelessWidget {
  final VehicleType type;
  final String? icon;
  final double size;

  const VehicleIcon({super.key, required this.type, this.icon, this.size = 28});

  VehicleIcon.of(Vehicle v, {super.key, this.size = 28})
      : type = v.type,
        icon = v.icon;

  @override
  Widget build(BuildContext context) {
    final i = icon;
    if (i != null && i.startsWith('file:')) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.25),
        child: Image.file(pictureFile(i.substring(5)),
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => _svg(picturesFor(type).first)),
      );
    }
    final options = picturesFor(type);
    return _svg(i != null && options.contains(i) ? i : options.first);
  }

  Widget _svg(String name) => SvgPicture.asset(
        'assets/vehicle_icons/$name.svg',
        width: size,
        height: size,
        semanticsLabel: kVehiclePictures[name],
      );
}
