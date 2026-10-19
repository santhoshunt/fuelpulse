import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../../db/database_helper.dart';
import '../../services/backup_payload.dart';
import '../../services/drive_backup_service.dart';
import '../../utils/constants.dart';
import 'restore_mode_dialog.dart';

// ── Google Drive backup section ─────────────────────────────────────────

class DriveBackupSection extends StatefulWidget {
  /// Called after any restore, with whether it was a replace (which also
  /// rewrote settings and lists) or a merge (which can add vehicles).
  final Future<void> Function(bool replaced) onRestored;

  const DriveBackupSection({super.key, required this.onRestored});

  @override
  State<DriveBackupSection> createState() => _DriveBackupSectionState();
}

class _DriveBackupSectionState extends State<DriveBackupSection> {
  final _svc = DriveBackupService();
  final _db = DatabaseHelper();

  bool _loading = true;
  GoogleSignInAccount? _account;
  String _freq = 'daily';
  DateTime? _lastBackup;
  String? _lastError;
  bool _uploading = false;
  bool _restoring = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    GoogleSignInAccount? account;
    try {
      account = await _svc.currentUser;
    } catch (_) {
      // Platform channel unavailable (tests, unsupported OS) — treat as
      // signed out rather than crashing Settings.
      account = null;
    }
    final freq = await _svc.getFrequency();
    final last = await _svc.lastBackupAt();
    final error = await _svc.lastError();
    if (!mounted) return;
    setState(() {
      _account = account;
      _freq = freq;
      _lastBackup = last;
      _lastError = error;
      _loading = false;
    });
  }

  Future<void> _connect() async {
    GoogleSignInAccount? account;
    try {
      account = await _svc.signIn();
    } catch (_) {
      account = null;
    }
    if (account == null && mounted) {
      // The classic symptom of a missing/mismatched OAuth Android client is
      // a null result with no error — name the likely cause.
      _showSnack(
        'Google sign-in was cancelled or failed. If this keeps happening, '
        'the OAuth Android client (package name + SHA-1) may be missing.',
      );
    }
    // Full reload — last-backup/error state is account-scoped.
    await _load();
  }

  Future<void> _disconnect() async {
    await _svc.signOut();
    await _load();
  }

  Future<void> _backupNow() async {
    if (_uploading) return;
    setState(() => _uploading = true);
    try {
      // Snapshot before uploadNow's first network await.
      final payload = await buildBackupPayload();
      final name = await _svc.uploadNow(payload);
      if (mounted) _showSnack('Saved to Drive: $name');
    } catch (e) {
      if (mounted) _showSnack('Backup failed: $e');
    } finally {
      if (mounted) {
        setState(() => _uploading = false);
        await _load();
      }
    }
  }

  Future<void> _restore() async {
    if (_restoring) return;
    final count = await _db.getLogCount();
    if (!mounted) return;
    final mode = await showRestoreModeDialog(context,
        title: 'Restore from Drive', currentCount: count);
    if (mode == null) return;

    setState(() => _restoring = true);
    try {
      final backup = await _svc.downloadLatest();
      final restored =
          await restoreBackup(backup.data, replace: mode == 'replace');
      await widget.onRestored(mode == 'replace');
      if (mounted) {
        _showSnack(
          'Restored $restored ${restored == 1 ? 'entry' : 'entries'} from '
          'backup (${DriveBackupService.formatLastBackup(backup.createdAt)}).',
        );
      }
    } on FormatException catch (e) {
      if (mounted) _showSnack(e.message);
    } catch (e) {
      if (mounted) _showSnack('Restore failed: $e');
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }

  Future<void> _setFrequency(String freq) async {
    setState(() => _freq = freq); // optimistic
    await _svc.setFrequency(freq);
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;

    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    if (_account == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            "Backs up every vehicle and its fill-ups (including costs), fuel "
            "types, pump brands and settings to a "
            "'${DriveBackupService.folderName}' folder in your Google Drive "
            'on the chosen schedule. Off until connected — nothing is '
            'uploaded.',
            style: TextStyle(color: kTextMuted, fontSize: 12),
          ),
          const SizedBox(height: 12),
          _card(
            icon: Icons.cloud_outlined,
            iconColor: accent,
            label: 'Connect Google Drive',
            onTap: _connect,
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Silent scheduled uploads mean a recorded failure is the one thing
        // this section must never hide.
        if (_lastError != null) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF59E0B).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.3)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.cloud_off_outlined,
                    color: Color(0xFFF59E0B), size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'The last Drive backup failed: $_lastError',
                    style: const TextStyle(
                        color: Color(0xFFF59E0B), fontSize: 12),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        // Account + last backup + disconnect
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Row(
            children: [
              Icon(Icons.account_circle_outlined, color: accent, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _account!.email,
                      style: const TextStyle(
                          color: kTextPrimary, fontSize: 13),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Last backup: '
                      '${DriveBackupService.formatLastBackup(_lastBackup)}',
                      style: const TextStyle(
                          color: kTextMuted, fontSize: 11),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: _disconnect,
                child: const Text('Disconnect',
                    style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Frequency
        Row(
          children: [
            const Text('Frequency',
                style: TextStyle(color: kTextSecondary, fontSize: 13)),
            const Spacer(),
            for (final f in ['daily', 'weekly', 'monthly']) ...[
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: ChoiceChip(
                  label: Text(DriveBackupService.freqLabel(f),
                      style: const TextStyle(fontSize: 12)),
                  selected: _freq == f,
                  onSelected: (_) => _setFrequency(f),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),

        // Back up now / Restore
        Row(
          children: [
            Expanded(
              child: _card(
                icon: _uploading ? null : Icons.cloud_upload_outlined,
                iconColor: accent,
                label: _uploading ? 'Backing up…' : 'Back up now',
                onTap: _backupNow,
                busy: _uploading,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _card(
                icon: _restoring ? null : Icons.cloud_download_outlined,
                iconColor: accent,
                label: _restoring ? 'Restoring…' : 'Restore',
                onTap: _restore,
                busy: _restoring,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _card({
    required IconData? icon,
    required Color iconColor,
    required String label,
    required VoidCallback onTap,
    bool busy = false,
  }) {
    return InkWell(
      onTap: busy ? null : onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Column(
          children: [
            if (busy)
              const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Icon(icon, color: iconColor, size: 28),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(color: kTextSecondary, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
