import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../db/database_helper.dart';
import '../models/attachment.dart';
import '../models/paper.dart';
import '../models/vehicle.dart';
import '../theme/app_colors.dart';
import '../utils/custom_pictures.dart';
import '../utils/mileage_bands.dart' show bandColor;
import '../utils/page_routes.dart';
import '../utils/vehicle_manager.dart';
import 'paper_form_screen.dart';

/// A paper's state against today: expired, due within its reminder window,
/// or valid. Null without an expiry date.
({String text, bool urgent})? paperStatus(Paper p, {DateTime? now}) {
  final exp = DateTime.tryParse(p.expiresOn ?? '');
  if (exp == null) return null;
  final n = now ?? DateTime.now();
  final today = DateTime(n.year, n.month, n.day);
  final days = DateTime(exp.year, exp.month, exp.day).difference(today).inDays;
  if (days < 0) return (text: 'Expired', urgent: true);
  if (days == 0) return (text: 'Expires today', urgent: true);
  if (days <= p.remindDays) {
    return (text: 'Expires in $days ${days == 1 ? 'day' : 'days'}', urgent: true);
  }
  return (text: 'Valid', urgent: false);
}

/// A coloured outline tag: the colour on the border and text only.
Widget statusTag(String text, Color color) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
      decoration: BoxDecoration(
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Text(text,
          style: TextStyle(
              color: color, fontSize: 11, fontWeight: FontWeight.w600)),
    );

/// The Papers list in the Garage tab: the active vehicle's documents, the
/// nearest expiry first.
class PapersScreen extends StatefulWidget {
  final ValueNotifier<int> reload;

  const PapersScreen({super.key, required this.reload});

  @override
  State<PapersScreen> createState() => _PapersScreenState();
}

class _PapersScreenState extends State<PapersScreen> {
  final _db = DatabaseHelper();
  Vehicle? _vehicle;
  List<Paper> _papers = const [];
  Map<String, Attachment> _thumbs = const {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    widget.reload.addListener(_load);
    _load();
  }

  @override
  void didUpdateWidget(PapersScreen old) {
    super.didUpdateWidget(old);
    if (old.reload != widget.reload) {
      old.reload.removeListener(_load);
      widget.reload.addListener(_load);
    }
  }

  @override
  void dispose() {
    widget.reload.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final v = await loadActiveVehicle();
    final papers = await _db.getPapers(v.id);
    final thumbs = <String, Attachment>{};
    for (final p in papers) {
      final first = (await _db.getAttachments('paper', p.id))
          .where((a) => !a.isPdf)
          .firstOrNull;
      if (first != null) thumbs[p.id] = first;
    }
    if (!mounted) return;
    setState(() {
      _vehicle = v;
      _papers = papers;
      _thumbs = thumbs;
      _loading = false;
    });
  }

  Future<void> _open([Paper? p]) async {
    final v = _vehicle;
    if (v == null) return;
    final changed = await Navigator.push<bool>(context,
        SmoothPageRoute(page: PaperFormScreen(vehicleId: v.id, paper: p)));
    if (changed == true) widget.reload.value++;
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    if (_loading) return const Center(child: CircularProgressIndicator());
    final green = bandColor(4, Theme.of(context).brightness);
    final muted = TextStyle(color: colors.textSecondary, fontSize: 13);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Material(
              color: colors.card,
              shape: CircleBorder(side: BorderSide(color: colors.cardBorder)),
              child: IconButton(
                tooltip: 'Add paper',
                icon: Icon(Icons.add, color: colors.primary),
                onPressed: () => _open(),
              ),
            ),
          ],
        ),
        if (_papers.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 60),
            child: Column(
              children: [
                Icon(Icons.folder_open_outlined,
                    size: 64,
                    color: colors.textSecondary.withValues(alpha: 0.5)),
                const SizedBox(height: 16),
                Text('No papers yet',
                    style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w500)),
                const SizedBox(height: 6),
                Text(
                    'Keep the RC, insurance and PUC certificate here, and '
                    'get a reminder before one lapses.',
                    textAlign: TextAlign.center,
                    style: muted),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () => _open(),
                  icon: const Icon(Icons.add),
                  label: const Text('Add paper'),
                ),
              ],
            ),
          ),
        for (final p in _papers) ...[
          const SizedBox(height: 10),
          Card(
            margin: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => _open(p),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 60,
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        color: colors.primaryTint,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: colors.cardBorder),
                      ),
                      child: _thumbs[p.id] == null
                          ? Icon(Icons.description_outlined,
                              color: colors.primary)
                          : Image.file(pictureFile(_thumbs[p.id]!.file),
                              fit: BoxFit.cover,
                              cacheWidth: 150,
                              errorBuilder: (_, _, _) => Icon(
                                  Icons.description_outlined,
                                  color: colors.primary)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(p.displayName,
                              style: TextStyle(
                                  color: colors.textPrimary,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600)),
                          Text(
                              [
                                if (p.number.isNotEmpty) p.number,
                                if (p.expiresOn != null)
                                  'Valid till ${DateFormat('d MMM y').format(DateTime.parse(p.expiresOn!))}'
                                else
                                  'No expiry',
                              ].join(' · '),
                              style: muted),
                          if (paperStatus(p) case final s?) ...[
                            const SizedBox(height: 4),
                            statusTag(s.text, s.urgent ? colors.danger : green),
                          ],
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right, color: colors.textSecondary),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
