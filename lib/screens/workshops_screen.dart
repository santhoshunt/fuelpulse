import 'package:flutter/material.dart';

import '../db/database_helper.dart';
import '../models/workshop.dart';
import '../theme/app_colors.dart';
import 'settings/settings_widgets.dart';

/// Garages and service centres, with how many visits each has.
class WorkshopsScreen extends StatefulWidget {
  const WorkshopsScreen({super.key});

  @override
  State<WorkshopsScreen> createState() => _WorkshopsScreenState();
}

class _WorkshopsScreenState extends State<WorkshopsScreen> {
  final _db = DatabaseHelper();
  List<Workshop> _workshops = const [];
  Map<String, int> _visits = const {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final ws = await _db.getWorkshops();
    final services = await _db.getEveryService();
    if (!mounted) return;
    setState(() {
      _workshops = ws;
      _visits = {};
      for (final s in services) {
        final id = s.workshopId;
        if (id != null) _visits[id] = (_visits[id] ?? 0) + 1;
      }
    });
  }

  Future<void> _edit([Workshop? w]) async {
    await showWorkshopEditor(context, workshop: w);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final muted = TextStyle(color: colors.textSecondary, fontSize: 13);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Workshops'),
        actions: [
          IconButton(
              tooltip: 'Add workshop',
              icon: const Icon(Icons.add),
              onPressed: () => _edit()),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          if (_workshops.isEmpty)
            Text('No workshops yet. Add one here or from the service form.',
                style: muted)
          else
            settingsGroup([
              for (final w in _workshops)
                ListTile(
                  title: Text(w.name,
                      style: TextStyle(
                          color: colors.textPrimary,
                          fontWeight: FontWeight.w600)),
                  subtitle: Text(
                      [w.area, w.phone].where((s) => s.isNotEmpty).join(' · '),
                      style: muted),
                  trailing: Text(_n(_visits[w.id] ?? 0), style: muted),
                  onTap: () => _edit(w),
                ),
            ]),
          const SizedBox(height: 12),
          Text('Each workshop has a name, an area and an optional phone number.',
              style: muted),
        ],
      ),
    );
  }

  static String _n(int n) => n == 1 ? '1 visit' : '$n visits';
}

/// Adds or edits a workshop. Returns the saved one, or null.
Future<Workshop?> showWorkshopEditor(BuildContext context,
    {Workshop? workshop}) {
  return showModalBottomSheet<Workshop>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _WorkshopEditor(workshop: workshop),
  );
}

class _WorkshopEditor extends StatefulWidget {
  final Workshop? workshop;
  const _WorkshopEditor({this.workshop});

  @override
  State<_WorkshopEditor> createState() => _WorkshopEditorState();
}

class _WorkshopEditorState extends State<_WorkshopEditor> {
  late final _name = TextEditingController(text: widget.workshop?.name ?? '');
  late final _area = TextEditingController(text: widget.workshop?.area ?? '');
  late final _phone =
      TextEditingController(text: widget.workshop?.phone ?? '');
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _area.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Enter a name');
      return;
    }
    final w = (widget.workshop ?? Workshop(id: Workshop.generateId(), name: ''))
        .copyWith(
            name: _name.text.trim(),
            area: _area.text.trim(),
            phone: _phone.text.trim());
    await DatabaseHelper().upsertWorkshop(w);
    if (mounted) Navigator.pop(context, w);
  }

  Future<void> _delete() async {
    await DatabaseHelper().deleteWorkshop(widget.workshop!.id);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 20, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.workshop == null ? 'Add workshop' : 'Edit workshop',
              style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),
          TextField(
            controller: _name,
            autofocus: widget.workshop == null,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(labelText: 'Name', errorText: _error),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _area,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Area (optional)'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Phone (optional)'),
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: _save, child: const Text('Save workshop')),
          if (widget.workshop != null)
            TextButton(
              onPressed: _delete,
              style: TextButton.styleFrom(foregroundColor: colors.danger),
              child: const Text('Delete workshop'),
            ),
        ],
      ),
    );
  }
}
