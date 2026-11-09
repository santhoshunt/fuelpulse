import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart' show DateFormat, NumberFormat;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../db/database_helper.dart';
import '../models/attachment.dart';
import '../models/paper.dart';
import '../models/vehicle.dart';
import '../screens/service_screen.dart' show latestOdometer, serviceTypeNames;
import '../utils/cost_calculator.dart';
import '../utils/custom_pictures.dart';
import '../utils/efficiency_calculator.dart';
import '../utils/trip_calculator.dart';

final _n = NumberFormat('#,##,##0', 'en_IN');
final _d = DateFormat('d MMM y');

String _date(String? iso) {
  final d = DateTime.tryParse(iso ?? '');
  return d == null ? '' : _d.format(d);
}

/// Makes [v]'s full history as a PDF and opens the share sheet.
Future<void> shareVehicleHistory(Vehicle v) async {
  final dir = await getTemporaryDirectory();
  final safeName = v.name.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');
  final out = File('${dir.path}/my_hness_history_$safeName.pdf');
  await out.writeAsBytes(await buildVehicleHistoryPdf(v), flush: true);
  await SharePlus.instance.share(ShareParams(
      files: [XFile(out.path, mimeType: 'application/pdf')],
      subject: "${v.name} · vehicle history"));
}

/// [v]'s full history as PDF bytes: a summary, then fill-ups, services,
/// tyres and battery, papers and trips, then every bill and document photo
/// as an appendix, one a page. Roboto is bundled for the ₹ sign.
Future<Uint8List> buildVehicleHistoryPdf(Vehicle v) async {
  final db = DatabaseHelper();
  final chrono = await db.getAllLogsChrono(v.id);
  final services = await db.getServices(v.id);
  final types = {for (final t in await db.getServiceTypes()) t.id: t};
  final workshops = {for (final w in await db.getWorkshops()) w.id: w.name};
  final parts = await db.getParts(v.id);
  final papers = await db.getPapers(v.id);
  final checks = await db.getChecks(v.id);
  final trips = await db.getTrips(v.id);
  final eff = calculateEfficiency(chrono);
  final avg = averageKmL(chrono);
  final odo = await latestOdometer(v.id);
  final now = DateTime.now();

  final font = pw.Font.ttf(await rootBundle.load('assets/fonts/roboto-regular.ttf'));
  final bold = pw.Font.ttf(await rootBundle.load('assets/fonts/roboto-bold.ttf'));
  final doc = pw.Document(
    theme: pw.ThemeData.withFont(base: font, bold: bold),
    title: '${v.name} · vehicle history',
    author: "My H'ness",
  );

  // Summary figures.
  final fuelSpend = chrono.fold<double>(
      0,
      (s, l) =>
          s + (l.totalCost ?? computeTotalCost(l.pricePerLitre, l.liters) ?? 0));
  final litres = chrono.fold<double>(0, (s, l) => s + l.liters);
  final serviceSpend = services.fold<double>(0, (s, r) => s + (r.cost ?? 0));
  final readings = [for (final l in chrono) l.odometer, for (final s in services) s.odometer];
  final first = chrono.isEmpty ? null : DateTime.tryParse(chrono.first.timestamp);

  pw.Widget heading(String s) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 18, bottom: 6),
        child: pw.Text(s,
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
      );
  pw.Widget table(List<String> headers, List<List<String>> rows) => rows.isEmpty
      ? pw.Text('None.', style: const pw.TextStyle(color: PdfColors.grey700))
      : pw.TableHelper.fromTextArray(
          headers: headers,
          data: rows,
          headerStyle: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold),
          cellStyle: const pw.TextStyle(fontSize: 8.5),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
          border: const pw.TableBorder(
              horizontalInside: pw.BorderSide(color: PdfColors.grey300, width: .5)),
          cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        );

  // Bills and photos for the appendix, newest owner first.
  final appendix = <(String, Attachment)>[];
  Future<void> collect(String type, String id, String label) async {
    for (final a in await db.getAttachments(type, id)) {
      appendix.add((label, a));
    }
  }

  for (final s in services) {
    await collect('service', s.id,
        'Service · ${_date(s.timestamp)} · ${serviceTypeNames(s, types)}');
  }
  for (final l in chrono.reversed) {
    await collect('fuel', l.id, 'Fill-up receipt · ${_date(l.timestamp)}');
  }
  for (final p in papers) {
    await collect('paper', p.id, 'Paper · ${p.displayName}');
  }
  final billCounts = <String, int>{
    for (final s in services)
      s.id: appendix.where((e) => e.$2.ownerId == s.id).length,
  };
  // Only photos whose file is still on the phone.
  final photos = <(String, pw.MemoryImage)>[];
  for (final (label, a) in appendix) {
    if (a.isPdf) continue;
    final file = pictureFile(a.file);
    if (await file.exists()) {
      photos.add((label, pw.MemoryImage(await file.readAsBytes())));
    }
  }
  final pdfBills = [for (final (label, a) in appendix) if (a.isPdf) label];

  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(32),
    // The default stops at 20 pages; years of fill-ups run longer.
    maxPages: 1000,
    footer: (ctx) => pw.Align(
      alignment: pw.Alignment.centerRight,
      child: pw.Text(
          "${v.name} · made by My H'ness on ${_d.format(now)} · page ${ctx.pageNumber} of ${ctx.pagesCount}",
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
    ),
    build: (ctx) => [
      pw.Text('${v.name} · vehicle history',
          style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
      pw.Text(
          [
            if (v.model.isNotEmpty) v.model,
            if (first != null) 'from ${_d.format(first)} to ${_d.format(now)}',
          ].join(' · '),
          style: const pw.TextStyle(color: PdfColors.grey700)),
      heading('Summary'),
      table(const ['Figure', 'Value'], [
        if (odo != null) ['Odometer now', '${_n.format(odo)} km'],
        if (readings.length > 1)
          ['Distance recorded', '${_n.format(readings.reduce(math.max) - readings.reduce(math.min))} km'],
        if (avg != null) ['Average mileage', '${avg.toStringAsFixed(1)} km/L'],
        ['Fuel', '₹${_n.format(fuelSpend)} · ${litres.toStringAsFixed(1)} L · ${chrono.length} fill-ups'],
        ['Service', '₹${_n.format(serviceSpend)} · ${services.length} visits'],
        if (trips.isNotEmpty) ['Trips', '${trips.length}'],
      ]),
      heading('Fill-ups'),
      table(const ['Date', 'Odometer', 'Litres', '₹/L', 'Total ₹', 'Tank', 'Pump', 'km/L'], [
        for (final l in chrono.reversed)
          [
            _date(l.timestamp),
            _n.format(l.odometer),
            l.liters.toStringAsFixed(2),
            (l.pricePerLitre ?? computePricePerLitre(l.totalCost, l.liters))
                    ?.toStringAsFixed(2) ??
                '',
            (l.totalCost ?? computeTotalCost(l.pricePerLitre, l.liters))
                    ?.toStringAsFixed(0) ??
                '',
            l.fullTank ? 'Full' : 'Partial',
            l.pumpBrand,
            eff[l.id]?.value?.toStringAsFixed(1) ?? '',
          ],
      ]),
      heading('Services'),
      table(const ['Date', 'Odometer', 'Work done', 'Workshop', 'Cost ₹', 'Bills'], [
        for (final s in services)
          [
            _date(s.timestamp),
            _n.format(s.odometer),
            serviceTypeNames(s, types),
            workshops[s.workshopId] ?? '',
            s.cost?.toStringAsFixed(0) ?? '',
            '${billCounts[s.id] ?? 0}',
          ],
      ]),
      heading('Tyres and battery'),
      table(const ['Part', 'Brand', 'Fitted', 'At km', 'Life', 'Used'], [
        for (final p in parts)
          [
            p.label,
            p.brand,
            _date(p.fittedAt),
            _n.format(p.fittedOdometer),
            [
              if (p.lifeKm != null) '${_n.format(p.lifeKm)} km',
              if (p.lifeMonths != null) '${p.lifeMonths} months',
            ].join(' or '),
            switch (p.wear(odo ?? p.fittedOdometer, now)) {
              final w? => '${(w * 100).round()}%',
              null => '',
            },
          ],
      ]),
      heading('Checks'),
      table(const ['Check', 'Every', 'Last done', 'Next due'], [
        for (final c in checks)
          [
            c.name,
            [
              if (c.everyDays != null) '${c.everyDays} days',
              if (c.everyKm != null) '${_n.format(c.everyKm)} km',
            ].join(' or '),
            '${_date(c.lastDoneAt)} at ${_n.format(c.lastDoneKm)} km',
            [
              if (c.dueDate != null) _d.format(c.dueDate!),
              if (c.dueKm != null) '${_n.format(c.dueKm)} km',
            ].join(' or '),
          ],
      ]),
      heading('Papers'),
      table(const ['Paper', 'Number', 'Issued', 'Expires'], [
        for (final Paper p in papers)
          [p.displayName, p.number, _date(p.issuedOn), _date(p.expiresOn)],
      ]),
      heading('Trips'),
      table(const ['Trip', 'From', 'To', 'km', 'Fuel', 'Fuel ₹'], [
        for (final t in trips)
          () {
            final end = t.endOdometer ?? odo ?? t.startOdometer;
            final f = tripFuel(t, chrono, endOdometer: end, averageKmL: avg);
            return [
              t.name,
              _date(t.startAt),
              t.endAt == null ? 'on now' : _date(t.endAt),
              _n.format(end - t.startOdometer),
              f == null ? '' : '${f.litres.toStringAsFixed(1)} L (${f.quality.name})',
              f?.cost?.toStringAsFixed(0) ?? '',
            ];
          }(),
      ]),
      if (photos.isNotEmpty || pdfBills.isNotEmpty) ...[
        heading('Appendix: bills and photos'),
        pw.Text(
            [
              if (photos.isNotEmpty)
                '${photos.length} ${photos.length == 1 ? 'photo follows' : 'photos follow'}, one a page.',
              if (pdfBills.isNotEmpty)
                'PDF bills are kept in the app: ${pdfBills.join('; ')}.',
            ].join(' '),
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
      ],
    ],
  ));

  for (final (label, image) in photos) {
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      build: (ctx) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(label,
              style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 10),
          pw.Expanded(child: pw.Center(child: pw.Image(image, fit: pw.BoxFit.contain))),
        ],
      ),
    ));
  }

  return doc.save();
}
