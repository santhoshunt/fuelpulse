// Builds the notification small icon: Material's motorcycle glyph, white on
// clear, at every density. Android draws a small icon as a white shape, so
// a full-colour picture shows as a white square.
//
// Run: flutter test tool/make_notification_icon_test.dart
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';

const _res = 'android/app/src/main/res';
const _sizes = {'mdpi': 24, 'hdpi': 36, 'xhdpi': 48, 'xxhdpi': 72, 'xxxhdpi': 96};

void main() {
  testWidgets('make notification icon', (tester) async {
    await tester.runAsync(() async {
      final fonts = join(Platform.environment['FLUTTER_ROOT']!, 'bin', 'cache',
          'artifacts', 'material_fonts');
      final bytes =
          await File(join(fonts, 'materialicons-regular.otf')).readAsBytes();
      final loader = FontLoader('MaterialIcons')
        ..addFont(Future.value(ByteData.view(bytes.buffer)));
      await loader.load();

      for (final e in _sizes.entries) {
        final size = e.value.toDouble();
        final rec = ui.PictureRecorder();
        final tp = TextPainter(
          text: TextSpan(
            text: String.fromCharCode(Icons.two_wheeler.codePoint),
            style: TextStyle(
                fontFamily: 'MaterialIcons',
                // A little inside the edges, as status bar icons are drawn.
                fontSize: size * 22 / 24,
                color: const Color(0xFFFFFFFF)),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(ui.Canvas(rec),
            Offset((size - tp.width) / 2, (size - tp.height) / 2));
        final img = await rec.endRecording().toImage(e.value, e.value);
        final png = await img.toByteData(format: ui.ImageByteFormat.png);
        final dir = Directory('$_res/drawable-${e.key}')..createSync();
        File('${dir.path}/ic_stat_notify.png')
            .writeAsBytesSync(Uint8List.view(png!.buffer));
      }
    });
  });
}
