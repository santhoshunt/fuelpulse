import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show NumberFormat;

import '../db/database_helper.dart';
import '../models/service_type.dart';
import '../theme/app_colors.dart';
import 'settings/settings_widgets.dart';

final _grouped = NumberFormat('#,##,##0', 'en_IN');

/// "Every 3,000 km or 6 months", "Every 500 km", "When needed".
String intervalText(ServiceType t) {
  final km = t.intervalKm;
  final mo = t.intervalMonths;
  final months = mo == null ? null : (mo == 1 ? '1 month' : '$mo months');
  if (km == null && months == null) return 'When needed';
  if (km == null) return 'Every $months';
  if (months == null) return 'Every ${_grouped.format(km)} km';
  return 'Every ${_grouped.format(km)} km or $months';
}

/// Kinds of service work and how often each is due. The interval pre-fills
/// the next service when one is logged.
class ServiceTypesScreen extends StatefulWidget {
  const ServiceTypesScreen({super.key});

  @override
  State<ServiceTypesScreen> createState() => _ServiceTypesScreenState();
}

class _ServiceTypesScreenState extends State<ServiceTypesScreen> {
  List<ServiceType> _types = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final t = await DatabaseHelper().getServiceTypes();
    if (mounted) setState(() => _types = t);
  }

  Future<void> _edit([ServiceType? t]) async {
    await showServiceTypeEditor(context,
        type: t, nextSortOrder: _types.length);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final muted = TextStyle(color: colors.textSecondary, fontSize: 13);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Service types'),
        actions: [
          IconButton(
              tooltip: 'Add service type',
              icon: const Icon(Icons.add),
              onPressed: () => _edit()),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          settingsGroup([
            for (final t in _types)
              ListTile(
                title: Text(t.name,
                    style: TextStyle(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w600)),
                subtitle: Text(intervalText(t), style: muted),
                trailing:
                    Icon(Icons.chevron_right, color: colors.textSecondary),
                onTap: () => _edit(t),
              ),
          ]),
          const SizedBox(height: 12),
          Text(
              'The interval pre-fills "Schedule the next one" when you log a '
              'service.',
              style: muted),
        ],
      ),
    );
  }
}

/// Adds or edits a service type. Returns the saved one, or null.
Future<ServiceType?> showServiceTypeEditor(BuildContext context,
    {ServiceType? type, int nextSortOrder = 0}) {
  return showModalBottomSheet<ServiceType>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _TypeEditor(type: type, nextSortOrder: nextSortOrder),
  );
}

class _TypeEditor extends StatefulWidget {
  final ServiceType? type;
  final int nextSortOrder;
  const _TypeEditor({this.type, required this.nextSortOrder});

  @override
  State<_TypeEditor> createState() => _TypeEditorState();
}

class _TypeEditorState extends State<_TypeEditor> {
  late final _name = TextEditingController(text: widget.type?.name ?? '');
  late final _km =
      TextEditingController(text: widget.type?.intervalKm?.toString() ?? '');
  late final _months = TextEditingController(
      text: widget.type?.intervalMonths?.toString() ?? '');
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _km.dispose();
    _months.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Enter a name');
      return;
    }
    final km = int.tryParse(_km.text.trim());
    final months = int.tryParse(_months.text.trim());
    final t = ServiceType(
      id: widget.type?.id ?? ServiceType.generateId(),
      name: _name.text.trim(),
      intervalKm: km != null && km > 0 ? km : null,
      intervalMonths: months != null && months > 0 ? months : null,
      sortOrder: widget.type?.sortOrder ?? widget.nextSortOrder,
    );
    await DatabaseHelper().upsertServiceType(t);
    if (mounted) Navigator.pop(context, t);
  }

  Future<void> _delete() async {
    await DatabaseHelper().deleteServiceType(widget.type!.id);
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
          Text(widget.type == null ? 'Add service type' : 'Edit service type',
              style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),
          TextField(
            controller: _name,
            autofocus: widget.type == null,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(labelText: 'Name', errorText: _error),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _km,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'Every (km)', hintText: 'Optional'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _months,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'Or every (months)', hintText: 'Optional'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: _save, child: const Text('Save type')),
          if (widget.type != null)
            TextButton(
              onPressed: _delete,
              style: TextButton.styleFrom(foregroundColor: colors.danger),
              child: const Text('Delete type'),
            ),
        ],
      ),
    );
  }
}
