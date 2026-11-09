// Builds the Android launcher icons from tool/icon/my_hness_icon.webp.
//
// Run: flutter test tool/make_launcher_icons_test.dart
//
// The source is a rounded square on a black page. The script finds the
// square, trims its rim, clips to its rounded corners, and writes:
// - mipmap-*/ic_launcher_foreground.png: the art filling the central 72 of
//   108 units, so the adaptive icon mask shows the whole picture.
// - mipmap-*/ic_launcher.png: the art alone, for launchers without
//   adaptive icons.
// It prints the colour for values/ic_launcher_background.xml.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

const _res = 'android/app/src/main/res';
const _densities = {
  'mdpi': 1.0,
  'hdpi': 1.5,
  'xhdpi': 2.0,
  'xxhdpi': 3.0,
  'xxxhdpi': 4.0,
};

void main() {
  testWidgets('make launcher icons', (tester) async {
    await tester.runAsync(() async {
      final bytes = File('tool/icon/my_hness_icon.webp').readAsBytesSync();
      final codec = await ui.instantiateImageCodec(bytes);
      final src = (await codec.getNextFrame()).image;
      final data = (await src.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      final w = src.width, h = src.height;
      int lum(int x, int y) {
        final i = (y * w + x) * 4;
        final r = data.getUint8(i), g = data.getUint8(i + 1), b = data.getUint8(i + 2);
        return [r, g, b].reduce((a, c) => a > c ? a : c);
      }

      // The art's bounding box: everything brighter than the black page.
      var left = w, top = h, right = 0, bottom = 0;
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          if (lum(x, y) > 24) {
            if (x < left) left = x;
            if (x > right) right = x;
            if (y < top) top = y;
            if (y > bottom) bottom = y;
          }
        }
      }
      // A square inside it, trimmed by 1.5% to drop the light rim.
      final side = (right - left < bottom - top ? right - left : bottom - top);
      final inset = side * 0.015;
      final crop = ui.Rect.fromLTWH(left + inset, top + inset,
          side - 2 * inset, side - 2 * inset);
      // The art's corner radius, from how far along the diagonal from the
      // top-left corner the first bright pixel sits: t = r × (1 − 1/√2).
      var t0 = 0;
      while (lum(left + t0, top + t0) <= 24) {
        t0++;
      }
      final radius = t0 / 0.2929 - inset;

      // The art's edge colour, averaged along the crop's border.
      var rs = 0, gs = 0, bs = 0, n = 0;
      void sample(int x, int y) {
        final i = (y * w + x) * 4;
        rs += data.getUint8(i);
        gs += data.getUint8(i + 1);
        bs += data.getUint8(i + 2);
        n++;
      }

      final l = crop.left.ceil() + 2, t = crop.top.ceil() + 2;
      final r = crop.right.floor() - 2, b = crop.bottom.floor() - 2;
      for (var x = l; x <= r; x += 4) {
        sample(x, t);
        sample(x, b);
      }
      for (var y = t; y <= b; y += 4) {
        sample(l, y);
        sample(r, y);
      }
      final edge = ui.Color.fromARGB(255, rs ~/ n, gs ~/ n, bs ~/ n);

      Future<void> write(String path, int size, ui.Rect target, {bool fill = false}) async {
        final rec = ui.PictureRecorder();
        final canvas = ui.Canvas(rec);
        if (fill) {
          canvas.drawRect(ui.Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()),
              ui.Paint()..color = edge);
        }
        // Round the corners like the art, so its black page never shows.
        final scale = target.width / crop.width;
        canvas.clipRRect(ui.RRect.fromRectAndRadius(
            target, ui.Radius.circular(radius * scale)));
        canvas.drawImageRect(src, crop, target,
            ui.Paint()..filterQuality = ui.FilterQuality.high);
        final img = await rec.endRecording().toImage(size, size);
        final png = await img.toByteData(format: ui.ImageByteFormat.png);
        File(path).writeAsBytesSync(Uint8List.view(png!.buffer));
      }

      for (final e in _densities.entries) {
        final fg = (108 * e.value).round();
        final art = fg * 72 / 108;
        final off = (fg - art) / 2;
        await write('$_res/mipmap-${e.key}/ic_launcher_foreground.png', fg,
            ui.Rect.fromLTWH(off, off, art, art), fill: true);
        final legacy = (48 * e.value).round();
        await write('$_res/mipmap-${e.key}/ic_launcher.png', legacy,
            ui.Rect.fromLTWH(0, 0, legacy.toDouble(), legacy.toDouble()));
      }
      final hex = edge.toARGB32().toRadixString(16).substring(2).toUpperCase();
      // ignore: avoid_print
      print('crop $crop, radius ${radius.toStringAsFixed(1)}, background #$hex');
    });
  });
}
