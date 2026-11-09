import 'dart:io' show File, Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/photo_scan.dart';
import '../services/update_installer.dart';
import '../theme/app_colors.dart';
import '../services/app_lock.dart';

/// ML Kit only runs on the phone, so scan entry points are hidden
/// elsewhere (and in widget tests).
bool get photoScanSupported =>
    !kIsWeb && (Platform.isAndroid || Platform.isIOS);

/// What [ScanPhotosScreen] hands back to the refill form.
class ScanOutcome {
  final ScanResult? odometer;
  final ScanResult? pump;

  /// When a gallery photo was taken, if the file says so; null for a camera
  /// shot (which is now) or when the time is unknown.
  final DateTime? photoTime;

  const ScanOutcome({this.odometer, this.pump, this.photoTime});

  bool get isEmpty => odometer == null && pump == null;
}

/// Two photo slots, odometer and pump display. Each is read on the phone as
/// soon as it is added; "Fill the form" returns what was read. Skip returns
/// an empty outcome (a blank form), Back returns null (no form).
class ScanPhotosScreen extends StatefulWidget {
  /// The vehicle's latest odometer: an odometer read far from it is not
  /// trusted.
  final int? lastOdometer;

  const ScanPhotosScreen({super.key, required this.lastOdometer});

  @override
  State<ScanPhotosScreen> createState() => _ScanPhotosScreenState();
}

class _ScanPhotosScreenState extends State<ScanPhotosScreen> {
  // Created on first use, so the screen can open without the recogniser.
  PhotoScanner? _scanner;
  final _results = <ScanKind, ScanResult>{};
  DateTime? _photoTime;
  ScanKind? _busy;

  @override
  void dispose() {
    _scanner?.close();
    super.dispose();
  }

  Future<void> _take(ScanKind kind, ImageSource source) async {
    final photo = await withoutRelock(() => ImagePicker()
        .pickImage(source: source, maxWidth: 2400, imageQuality: 92));
    if (photo == null || !mounted) return;
    // A gallery pick may be a copy made just now, so its file time only
    // counts when it is clearly older than the pick.
    DateTime? taken;
    if (source == ImageSource.gallery) {
      try {
        final t = await photo.lastModified();
        if (DateTime.now().difference(t) > const Duration(minutes: 10)) {
          taken = t;
        }
      } catch (_) {}
    }
    setState(() => _busy = kind);
    try {
      final r = await (_scanner ??= PhotoScanner())
          .scan(photo.path, kind, lastOdometer: widget.lastOdometer);
      if (!mounted) return;
      setState(() {
        _results[kind] = r;
        if (taken != null) _photoTime = taken;
      });
    } catch (e) {
      debugPrint('Photo scan failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not read the photo: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _report(ScanResult r) async {
    String version;
    try {
      version = await ChannelUpdateInstaller.instance.currentVersion();
    } catch (_) {
      version = 'unknown';
    }
    await r.share(version);
  }

  Future<void> _retake(ScanKind kind) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take photo'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source != null) await _take(kind, source);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan photos'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, const ScanOutcome()),
            child: const Text('Skip'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Text(
              "Take or pick two photos. My H'ness reads them on your phone; "
              'nothing is uploaded.',
              style: TextStyle(color: colors.textSecondary, fontSize: 14)),
          const SizedBox(height: 14),
          _slot(ScanKind.odometer, '1 · Odometer', colors),
          const SizedBox(height: 12),
          _slot(ScanKind.pump, '2 · Pump display', colors),
          const SizedBox(height: 20),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            onPressed: _results.isEmpty || _busy != null
                ? null
                : () => Navigator.pop(
                    context,
                    ScanOutcome(
                      odometer: _results[ScanKind.odometer],
                      pump: _results[ScanKind.pump],
                      photoTime: _photoTime,
                    )),
            child: const Text('Fill the form'),
          ),
        ],
      ),
    );
  }

  Widget _slot(ScanKind kind, String caption, AppColors colors) {
    final r = _results[kind];
    final cap = Text(caption.toUpperCase(),
        style: TextStyle(
            color: colors.textSecondary,
            fontSize: 11,
            letterSpacing: 1.2,
            fontWeight: FontWeight.w600));
    final busy = _busy == kind;

    if (r == null) {
      return Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              cap,
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busy != null
                          ? null
                          : () => _take(kind, ImageSource.camera),
                      icon: const Icon(Icons.photo_camera_outlined, size: 18),
                      label: const Text('Camera'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busy != null
                          ? null
                          : () => _take(kind, ImageSource.gallery),
                      icon: const Icon(Icons.photo_library_outlined, size: 18),
                      label: const Text('Gallery'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (busy)
                const LinearProgressIndicator()
              else
                Text(
                    'Fill the frame with the display and avoid glare. '
                    'Either photo can be skipped.',
                    style:
                        TextStyle(color: colors.textSecondary, fontSize: 12)),
            ],
          ),
        ),
      );
    }

    final (status, ok) = _status(r);
    final values = _values(r);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.file(File(r.photoPath),
                  width: 84, height: 84, fit: BoxFit.cover),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  cap,
                  const SizedBox(height: 4),
                  Text(status,
                      style: TextStyle(
                          color: ok ? colors.primary : colors.warning,
                          fontSize: 14,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 12,
                    runSpacing: 2,
                    children: [
                      for (final (label, value) in values)
                        Text.rich(TextSpan(children: [
                          TextSpan(
                              text: '$label ',
                              style: TextStyle(color: colors.textSecondary)),
                          TextSpan(
                              text: value,
                              style: TextStyle(
                                  color: colors.textPrimary,
                                  fontWeight: FontWeight.w600)),
                        ])),
                    ],
                  ),
                  if (busy) ...[
                    const SizedBox(height: 8),
                    const LinearProgressIndicator(),
                  ],
                  Row(
                    children: [
                      TextButton(
                          onPressed: _busy != null ? null : () => _retake(kind),
                          child: const Text('Retake')),
                      TextButton(
                          onPressed: () => _report(r),
                          child: const Text('Report')),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Headline for a read, and whether it can be used as it is.
  (String, bool) _status(ScanResult r) {
    if (r.kind == ScanKind.odometer) {
      return r.odometer!.value != null ? ('Read', true) : ('Not read', false);
    }
    final p = r.pump!;
    if (p.found) {
      return p.corrections == 0
          ? ('Read and checked', true)
          : (
              'Read, ${p.corrections} '
                  '${p.corrections == 1 ? 'digit' : 'digits'} fixed',
              false
            );
    }
    if (pumpSuggestion(p) != null) return ('Needs checking', false);
    if (p.rateOnly) return ('Rate only', false);
    return ('Not read', false);
  }

  List<(String, String)> _values(ScanResult r) {
    if (r.kind == ScanKind.odometer) {
      final o = r.odometer!;
      return [
        if (o.label != null) ('Label', o.label!),
        if (o.value != null) (o.isTrip ? 'Trip' : 'Odometer', '${o.value} km'),
      ];
    }
    final p = r.pump!;
    return [
      if (p.amount != null) ('Amount', '₹${p.amount!.toStringAsFixed(2)}'),
      if (p.litres != null) ('Litres', '${p.litres!.toStringAsFixed(2)} L'),
      if (p.rate != null) ('Rate', '₹${p.rate!.toStringAsFixed(2)}/L'),
    ];
  }
}
