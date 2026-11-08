import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../db/database_helper.dart';
import '../../utils/constants.dart';
import 'settings_widgets.dart';

class DangerSection extends StatefulWidget {
  /// Called after the wipe, so Settings stops listing deleted vehicles.
  final Future<void> Function() onDeleted;

  const DangerSection({super.key, required this.onDeleted});

  @override
  State<DangerSection> createState() => _DangerSectionState();
}

class _DangerSectionState extends State<DangerSection> {
  final _db = DatabaseHelper();
  bool _dangerExpanded = false;
  final _deleteConfirmController = TextEditingController();

  Future<void> _deleteAllData() async {
    final text = _deleteConfirmController.text.trim();
    if (text != 'DELETE') {
      showSettingsSnack(context, 'Type DELETE to confirm.');
      return;
    }
    // Every vehicle goes too; one default vehicle is left so the app always
    // has somewhere to log the next fill-up.
    await _db.resetToDefaultVehicle();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(kActiveVehicleKey);
    await widget.onDeleted();
    if (!mounted) return;
    _deleteConfirmController.clear();
    setState(() => _dangerExpanded = false);
    showSettingsSnack(context, 'All data deleted.');
  }

  @override
  void dispose() {
    _deleteConfirmController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GestureDetector(
          onTap: () => setState(() => _dangerExpanded = !_dangerExpanded),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.of(context).danger.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.of(context).danger.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                Icon(Icons.warning_amber_rounded,
                    color: AppColors.of(context).danger, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Danger Zone',
                    style: TextStyle(
                      color: AppColors.of(context).danger,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                ),
                Icon(
                  _dangerExpanded ? Icons.expand_less : Icons.expand_more,
                  color: AppColors.of(context).danger,
                ),
              ],
            ),
          ),
        ),
        AnimatedCrossFade(
          firstChild: const SizedBox.shrink(),
          secondChild: Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Deletes every vehicle and fill-up. Type DELETE to confirm '
                  'data wipe:',
                  style: TextStyle(color: AppColors.of(context).textSecondary, fontSize: 13),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _deleteConfirmController,
                  decoration: InputDecoration(
                    hintText: 'Type DELETE',
                    prefixIcon: Icon(Icons.delete_forever, color: AppColors.of(context).danger),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _deleteAllData,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.of(context).danger,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Delete All Data',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          ),
          crossFadeState: _dangerExpanded
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 300),
        ),
      ],
    );
  }
}
