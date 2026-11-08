import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Pictures you pick for a brand logo or a vehicle: cropped to a centre
/// square, scaled to [kPictureSize] px, kept as PNGs in app storage and in
/// backups. Files are named, never pathed, so a restore on another phone
/// finds them in its own folder.
const kPictureSize = 256;

/// Brand name → picture file name, for brands with your own logo.
const kBrandLogosKey = 'fuel_brand_logos';

/// The folder pictures live in; set by [initPictures] before the first frame.
String picturesPath = '';

/// Your logo per brand. Widgets listen, so a change shows everywhere.
final ValueNotifier<Map<String, String>> brandLogos = ValueNotifier(const {});

Future<void> initPictures() async {
  if (kIsWeb) return;
  final dir = Directory('${(await getApplicationDocumentsDirectory()).path}/pictures');
  await dir.create(recursive: true);
  picturesPath = dir.path;
  await reloadBrandLogos();
}

Future<void> reloadBrandLogos() async {
  final prefs = await SharedPreferences.getInstance();
  try {
    final m = jsonDecode(prefs.getString(kBrandLogosKey) ?? '{}') as Map;
    brandLogos.value = {for (final e in m.entries) '${e.key}': '${e.value}'};
  } catch (_) {
    brandLogos.value = const {};
  }
}

Future<void> _saveBrandLogos(Map<String, String> m) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(kBrandLogosKey, jsonEncode(m));
  brandLogos.value = Map.unmodifiable(m);
}

/// Sets ([file] given) or removes the logo for [brand].
Future<void> setBrandLogo(String brand, String? file) async {
  final m = Map<String, String>.of(brandLogos.value);
  file == null ? m.remove(brand) : m[brand] = file;
  await _saveBrandLogos(m);
}

/// Keeps a custom logo with its brand through a rename.
Future<void> renameBrandLogo(String from, String to) async {
  final file = brandLogos.value[from];
  if (file == null) return;
  final m = Map<String, String>.of(brandLogos.value)
    ..remove(from)
    ..[to] = file;
  await _saveBrandLogos(m);
}

File pictureFile(String name) => File('$picturesPath/$name');

/// Opens the gallery and saves the pick as a square PNG. Returns its file
/// name, or null when cancelled.
Future<String?> pickSquarePicture(String prefix) async {
  final pick = await ImagePicker()
      .pickImage(source: ImageSource.gallery, maxWidth: 1200, maxHeight: 1200);
  if (pick == null) return null;
  final codec = await ui.instantiateImageCodec(await pick.readAsBytes());
  final image = (await codec.getNextFrame()).image;
  final side = math.min(image.width, image.height).toDouble();
  final src = ui.Rect.fromLTWH((image.width - side) / 2,
      (image.height - side) / 2, side, side);
  final recorder = ui.PictureRecorder();
  final size = kPictureSize.toDouble();
  ui.Canvas(recorder).drawImageRect(image, src,
      ui.Rect.fromLTWH(0, 0, size, size),
      ui.Paint()..filterQuality = ui.FilterQuality.high);
  final out = await recorder.endRecording().toImage(kPictureSize, kPictureSize);
  final png = await out.toByteData(format: ui.ImageByteFormat.png);
  final name = '${prefix}_${DateTime.now().millisecondsSinceEpoch}.png';
  await pictureFile(name).writeAsBytes(png!.buffer.asUint8List(), flush: true);
  return name;
}

/// Every picture in use, as base64, for a backup.
Future<Map<String, String>> picturesForBackup(Iterable<String> names) async {
  final out = <String, String>{};
  for (final n in names.toSet()) {
    final f = pictureFile(n);
    if (picturesPath.isNotEmpty && await f.exists()) {
      out[n] = base64Encode(await f.readAsBytes());
    }
  }
  return out;
}

/// Writes a backup's pictures; a name that already exists is kept.
Future<void> restorePictures(Map<dynamic, dynamic> pictures) async {
  if (picturesPath.isEmpty) return;
  for (final e in pictures.entries) {
    final name = '${e.key}';
    // Names only: a path in a crafted file must not write outside the folder.
    if (name.contains('/') || name.contains('\\') || name.contains('..')) {
      continue;
    }
    final f = pictureFile(name);
    if (await f.exists()) continue;
    try {
      await f.writeAsBytes(base64Decode('${e.value}'), flush: true);
    } catch (_) {}
  }
}

/// Replaces (or with [merge], adds to) the brand logo map from a backup.
Future<void> restoreBrandLogos(Map<dynamic, dynamic> m, {bool merge = false}) async {
  final next = merge ? Map<String, String>.of(brandLogos.value) : <String, String>{};
  for (final e in m.entries) {
    if (merge && next.containsKey('${e.key}')) continue;
    next['${e.key}'] = '${e.value}';
  }
  await _saveBrandLogos(next);
}
