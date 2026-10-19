import 'package:flutter/material.dart';

import '../services/update_prefs.dart';
import '../services/update_service.dart';
import '../utils/constants.dart';
import 'glossy_card.dart';
import 'update_sheet.dart';

// Ported from the expense tracker's update banner, restyled as a glossy
// card and reading the "Not now" tag from SharedPreferences.

/// Home's "Update available" card: shown when the launch check (or
/// Settings) found a newer release and the newest one wasn't answered with
/// Not now. It only opens the version sheet; nothing downloads from here.
class UpdateBanner extends StatefulWidget {
  const UpdateBanner({super.key});

  @override
  State<UpdateBanner> createState() => _UpdateBannerState();
}

class _UpdateBannerState extends State<UpdateBanner> {
  String? _dismissed;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    dismissedUpdateTag().then((tag) {
      if (mounted) {
        setState(() {
          _dismissed = tag;
          _loaded = true;
        });
      }
    });
  }

  Future<void> _notNow(String tag) async {
    setState(() => _dismissed = tag);
    await dismissUpdate(tag);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<UpdateList?>(
      valueListenable: availableUpdate,
      builder: (context, updates, _) {
        if (!_loaded || updates == null || updates.newer.isEmpty) {
          return const SizedBox.shrink();
        }
        final newest = updates.newer.first.tag;
        if (newest == _dismissed) return const SizedBox.shrink();
        final accent = Theme.of(context).colorScheme.primary;
        final n = updates.newer.length;
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: GlossyCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.system_update_alt, size: 20, color: accent),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Update available: $newest',
                        style: const TextStyle(
                          color: kTextPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  n == 1
                      ? 'A newer version is on GitHub.'
                      : '$n newer versions on GitHub.',
                  style: const TextStyle(color: kTextSecondary, fontSize: 13),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton(
                      onPressed: () => showUpdateSheet(context, updates),
                      child: const Text('See versions'),
                    ),
                    OutlinedButton(
                      onPressed: () => _notNow(newest),
                      child: const Text('Not now'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
