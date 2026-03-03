import 'package:flutter/material.dart';
import '../utils/constants.dart';

/// Colored rounded square badge with brand abbreviation + optional name label.
class BrandBadge extends StatelessWidget {
  final String brandName;
  final bool showLabel;
  final double size;

  const BrandBadge({
    super.key,
    required this.brandName,
    this.showLabel = true,
    this.size = 30,
  });

  @override
  Widget build(BuildContext context) {
    final config = getBrandConfig(brandName);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: config.background,
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: Alignment.center,
          child: Text(
            config.abbreviation,
            style: TextStyle(
              color: config.textColor,
              fontSize: size * 0.4,
              fontWeight: FontWeight.bold,
              height: 1,
            ),
          ),
        ),
        if (showLabel) ...[
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              brandName.isEmpty ? 'Unknown' : brandName,
              style: TextStyle(
                color: kTextPrimary,
                fontSize: 13,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ],
    );
  }
}
