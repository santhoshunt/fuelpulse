import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../utils/constants.dart';
import '../utils/custom_pictures.dart';
import 'brand_badge.dart';

/// Logo files under assets/brand_logos/, keyed by the canonical names in
/// [kBrands]. Aliases such as "Hindustan Petroleum" reach them through
/// [getBrandConfig].
const _logoFiles = {
  'Shell': 'shell',
  'HP': 'hp',
  'Indian Oil': 'indian_oil',
  'Bharat Petroleum': 'bharat_petroleum',
  'Nayara Energy': 'nayara_energy',
  'Jio-BP': 'jio_bp',
};

/// A pump brand's logo on a white rounded tile: your own logo for the brand
/// if you set one, else the bundled one, else the coloured initials of
/// [BrandBadge].
class BrandLogo extends StatelessWidget {
  final String brandName;
  final double size;

  const BrandLogo({super.key, required this.brandName, this.size = 40});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Map<String, String>>(
      valueListenable: brandLogos,
      builder: (context, logos, _) {
        final own = logos[brandName];
        final file = _logoFiles[getBrandConfig(brandName).name];
        if (own == null && file == null) {
          return BrandBadge(brandName: brandName, showLabel: false, size: size);
        }
        return Container(
          width: size,
          height: size,
          padding: EdgeInsets.all(own != null ? 0 : size * 0.08),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            // White in both modes: the logos are drawn for a white background.
            color: Colors.white,
            borderRadius: BorderRadius.circular(size * 0.25),
            border: Border.all(color: AppColors.of(context).cardBorder),
          ),
          child: own != null
              ? Image.file(pictureFile(own),
                  fit: BoxFit.cover,
                  semanticLabel: brandName,
                  errorBuilder: (_, _, _) => BrandBadge(
                      brandName: brandName, showLabel: false, size: size))
              : Image.asset(
                  'assets/brand_logos/$file.png',
                  fit: BoxFit.contain,
                  semanticLabel: brandName,
                ),
        );
      },
    );
  }
}
