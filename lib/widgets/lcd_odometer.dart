import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// A dashboard-style seven-segment odometer: lit segments over dim unlit
/// ones, slightly slanted like a real LCD.
class LcdOdometer extends StatelessWidget {
  final int value;

  /// Small trailing digit, only when the reading has one.
  final int? tenths;

  const LcdOdometer({super.key, required this.value, this.tenths});

  @override
  Widget build(BuildContext context) {
    final digits = value.abs().toString().padLeft(6, '0');
    return Semantics(
      label: 'Odometer $value km',
      child: Container(
        padding: const EdgeInsets.fromLTRB(7, 5, 7, 4),
        decoration: BoxDecoration(
          color: AppColors.lcdBackground,
          border: Border.all(color: AppColors.lcdBorder),
          borderRadius: BorderRadius.circular(6),
        ),
        child: ExcludeSemantics(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final d in digits.split('')) ...[
                _SegmentDigit(digit: int.parse(d), width: 12, height: 21),
                const SizedBox(width: 3),
              ],
              if (tenths != null) ...[
                const SizedBox(width: 2),
                _SegmentDigit(digit: tenths! % 10, width: 8, height: 13),
                const SizedBox(width: 3),
              ],
              const Text('km',
                  style: TextStyle(
                      color: AppColors.lcdUnit, fontSize: 10, height: 1)),
            ],
          ),
        ),
      ),
    );
  }
}

class _SegmentDigit extends StatelessWidget {
  final int digit;
  final double width;
  final double height;

  const _SegmentDigit(
      {required this.digit, required this.width, required this.height});

  @override
  Widget build(BuildContext context) {
    return Transform(
      // A 6 degree forward slant.
      transform: Matrix4.skewX(-0.105),
      alignment: Alignment.center,
      child: CustomPaint(
        size: Size(width, height),
        painter: _SegmentPainter(digit),
      ),
    );
  }
}

class _SegmentPainter extends CustomPainter {
  final int digit;

  _SegmentPainter(this.digit);

  /// Segments a to g (top, top right, bottom right, bottom, bottom left,
  /// top left, middle) lit for each digit.
  static const _lit = <String>[
    'abcdef', 'bc', 'abdeg', 'abcdg', 'bcfg', //
    'acdfg', 'acdefg', 'abc', 'abcdefg', 'abcdfg',
  ];

  /// Each segment's rectangle in a 12 × 22 cell.
  static const _rects = <String, Rect>{
    'a': Rect.fromLTWH(2.5, 0.4, 7, 1.7),
    'b': Rect.fromLTWH(9.9, 2.4, 1.7, 7.6),
    'c': Rect.fromLTWH(9.9, 12, 1.7, 7.6),
    'd': Rect.fromLTWH(2.5, 19.9, 7, 1.7),
    'e': Rect.fromLTWH(0.4, 12, 1.7, 7.6),
    'f': Rect.fromLTWH(0.4, 2.4, 1.7, 7.6),
    'g': Rect.fromLTWH(2.5, 10.15, 7, 1.7),
  };

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 12, size.height / 22);
    final on = Paint()..color = AppColors.lcdLit;
    final off = Paint()..color = AppColors.lcdUnlit;
    final lit = _lit[digit.clamp(0, 9)];
    for (final e in _rects.entries) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(e.value, const Radius.circular(0.85)),
        lit.contains(e.key) ? on : off,
      );
    }
  }

  @override
  bool shouldRepaint(_SegmentPainter old) => old.digit != digit;
}
