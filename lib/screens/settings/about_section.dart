import 'package:flutter/material.dart';
import '../../services/update_installer.dart';
import '../../services/update_prefs.dart';
import '../../services/update_service.dart';
import '../../utils/constants.dart';
import '../../widgets/update_sheet.dart';
import 'settings_widgets.dart';

/// The installed version, an on-demand update check and the daily launch
/// check switch.
class AboutSection extends StatefulWidget {
  /// Injectable for tests; defaults to the real GitHub check.
  final UpdateService Function() service;
  final UpdateInstaller installer;

  AboutSection({
    super.key,
    UpdateService Function()? service,
    UpdateInstaller? installer,
  })  : service = service ?? UpdateService.new,
        installer = installer ?? ChannelUpdateInstaller.instance;

  @override
  State<AboutSection> createState() => _AboutSectionState();
}

class _AboutSectionState extends State<AboutSection> {
  String? _version;
  bool _onLaunch = true;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    String? version;
    try {
      version = await widget.installer.currentVersion();
    } catch (_) {
      // Not Android (tests, desktop): no version to show.
    }
    final onLaunch = await updateOnLaunch();
    if (!mounted) return;
    setState(() {
      _version = version;
      _onLaunch = onLaunch;
    });
  }

  Future<void> _check() async {
    if (_checking) return;
    setState(() => _checking = true);
    final result = await widget.service().check();
    if (!mounted) return;
    setState(() => _checking = false);
    switch (result) {
      case UpdateAvailable(:final updates):
        availableUpdate.value = updates;
        await markUpdateChecked(DateTime.now());
        if (mounted) {
          await showUpdateSheet(context, updates, installer: widget.installer);
        }
      case UpToDate(:final currentVersion):
        await markUpdateChecked(DateTime.now());
        if (mounted) {
          showSettingsSnack(context,
              "You're on the latest version (${versionLabel(currentVersion)}).");
        }
      case CheckFailed(:final message):
        showSettingsSnack(context, message);
    }
  }

  Future<void> _setOnLaunch(bool value) async {
    setState(() => _onLaunch = value);
    await setUpdateOnLaunch(value);
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        sectionHeader('About'),
        const SizedBox(height: 4),
        Text(
          _version == null ? 'FuelPulse' : 'FuelPulse ${versionLabel(_version!)}',
          style: const TextStyle(color: kTextMuted, fontSize: 12),
        ),
        const SizedBox(height: 12),
        actionCard(
          icon: Icons.system_update_alt,
          label: _checking ? 'Checking…' : 'Check for updates',
          onTap: _check,
          accent: accent,
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Check for updates on launch',
              style: TextStyle(color: kTextPrimary, fontSize: 14)),
          subtitle: const Text(
              'Once a day, FuelPulse asks GitHub for a newer release. Nothing '
              'downloads until you choose to.',
              style: TextStyle(color: kTextMuted, fontSize: 12)),
          value: _onLaunch,
          onChanged: _setOnLaunch,
        ),
      ],
    );
  }
}
