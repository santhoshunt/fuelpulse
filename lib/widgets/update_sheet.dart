import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:url_launcher/url_launcher.dart';

import '../services/update_downloader.dart';
import '../services/update_installer.dart';
import '../services/update_prefs.dart';
import '../services/update_service.dart';
import '../utils/constants.dart';

// Ported from the expense tracker's update sheet. Its provider, toast and
// link widgets become SharedPreferences, a SnackBar and url_launcher.

/// The app's own package, named in the sheet's list of checks.
const kAppPackage = 'com.fabletest.fuelpulse';

/// A version written one way everywhere on the sheet: "v2.0.0", whether it
/// came as a release tag ("v2.0.0") or as the installed version ("2.0.0").
String versionLabel(String version) {
  final v = version.trim();
  return v.startsWith('v') || v.startsWith('V') ? 'v${v.substring(1)}' : 'v$v';
}

/// Opens [url] in the browser. False when nothing could open it.
Future<bool> openReleasePage(String url) async {
  try {
    return await launchUrl(Uri.parse(url),
        mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}

/// Lets the user pick one of [updates] and install it: the exact download
/// URL and the checks made before installing are on screen before the tap.
/// Nothing downloads or installs until Download & install.
Future<void> showUpdateSheet(
  BuildContext context,
  UpdateList updates, {
  UpdateInstaller? installer,
  UpdateDownloader? downloader,
}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: const Color(0xFF161616),
      builder: (_) => UpdateSheet(
        updates: updates,
        installer: installer ?? ChannelUpdateInstaller.instance,
        downloader: downloader ?? UpdateDownloader(),
      ),
    );

enum _Step { choose, needsPermission, downloading, installing }

class UpdateSheet extends StatefulWidget {
  final UpdateList updates;
  final UpdateInstaller installer;
  final UpdateDownloader downloader;

  const UpdateSheet({
    super.key,
    required this.updates,
    required this.installer,
    required this.downloader,
  });

  @override
  State<UpdateSheet> createState() => _UpdateSheetState();
}

class _UpdateSheetState extends State<UpdateSheet> with WidgetsBindingObserver {
  late ReleaseOption _picked = widget.updates.newer.first;

  /// The newest release's notes start open: they are what the update is.
  late final Set<String> _notesOpen = {widget.updates.newer.first.tag};
  _Step _step = _Step.choose;
  int _received = 0;
  DownloadCancel? _cancel;

  /// True from the tap until the download has started: a second tap in
  /// that window must not start a second download.
  bool _starting = false;

  /// The running (or winding-down cancelled) attempt; a new one waits for
  /// it, so two attempts never share the updates folder.
  Future<void>? _attempt;

  /// Completes when the app is back in front; see [_whenResumed].
  Completer<void>? _resumed;

  /// The release page link failed to open. Said on the sheet itself: a
  /// SnackBar would draw under it.
  bool _linkFailed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cancel?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final resumed = _resumed;
    _resumed = null;
    resumed?.complete();
    // Back from the system settings page: if the switch is now on, the
    // user is returned to the list to tap Download & install again.
    if (_step != _Step.needsPermission) return;
    widget.installer.canInstall().then((ok) {
      if (ok && mounted) setState(() => _step = _Step.choose);
    });
  }

  /// Android shows its confirm screen only for an app in front, so an
  /// install finished downloading in the background waits for the return.
  Future<void> _whenResumed() async {
    final state = WidgetsBinding.instance.lifecycleState;
    if (state == null || state == AppLifecycleState.resumed) return;
    await (_resumed ??= Completer<void>()).future;
  }

  static String _mb(int bytes) => (bytes / (1024 * 1024)).toStringAsFixed(1);

  Future<void> _openPage() async {
    final ok = await openReleasePage(_picked.pageUrl);
    if (mounted && ok == _linkFailed) setState(() => _linkFailed = !ok);
  }

  Future<void> _start() async {
    // A second tap can land before the rebuild hides the button.
    if (_starting || _step != _Step.choose) return;
    _starting = true;
    try {
      await _attempt;
      if (!await widget.installer.canInstall()) {
        if (mounted) setState(() => _step = _Step.needsPermission);
        return;
      }
      if (!mounted) return;
      setState(() {
        _step = _Step.downloading;
        _received = 0;
      });
    } finally {
      _starting = false;
    }
    final run = _attempt = _run(_picked, _cancel = DownloadCancel());
    await run;
    if (identical(_attempt, run)) _attempt = null;
  }

  Future<void> _run(ReleaseOption option, DownloadCancel cancel) async {
    final messenger = ScaffoldMessenger.of(context);
    String? problem;
    try {
      final apk = await widget.downloader.download(
        option,
        cancel: cancel,
        onProgress: (received, _) {
          if (mounted && !cancel.cancelled) {
            setState(() => _received = received);
          }
        },
      );
      if (cancel.cancelled || !mounted) return;
      setState(() => _step = _Step.installing);
      await _whenResumed();
      if (cancel.cancelled || !mounted) return;
      await setInstallingUpdateTag(option.tag);
      problem = await widget.installer.install(apk);
      if (problem != null) await setInstallingUpdateTag(null);
    } on UpdateDownloadException catch (e) {
      if (cancel.cancelled) return;
      problem = e.message;
    } catch (e) {
      // Anything else must still close the sheet with a reason, not leave
      // it stuck on the installing step.
      if (cancel.cancelled) return;
      await setInstallingUpdateTag(null);
      problem = 'Install failed: $e';
    } finally {
      // The install session holds its own copy once committed.
      await widget.downloader.cleanup();
    }
    // Null: the install is under way (success closes the app) or the
    // system stopped reporting; either way the sheet has nothing left.
    if (mounted) Navigator.of(context).pop();
    if (problem == null) return;
    messenger.showSnackBar(SnackBar(
      content: Text(problem),
      duration: const Duration(seconds: 8),
      action: SnackBarAction(
        label: 'Release page',
        onPressed: () => openReleasePage(option.pageUrl),
      ),
    ));
  }

  void _cancelDownload() {
    _cancel?.cancel();
    setState(() => _step = _Step.choose);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = theme.textTheme.bodySmall?.copyWith(color: kTextSecondary);
    final busy = _step == _Step.downloading || _step == _Step.installing;
    final newer = widget.updates.newer;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  // Nothing to choose between when one version is offered.
                  newer.length == 1
                      ? 'Update to ${versionLabel(newer.first.tag)}'
                      : 'Choose a version',
                  style: theme.textTheme.titleLarge
                      ?.copyWith(color: kTextPrimary),
                ),
              ),
              Text(
                'On ${versionLabel(widget.updates.currentVersion)}',
                style: muted,
              ),
            ],
          ),
          const SizedBox(height: 8),
          RadioGroup<String>(
            groupValue: _picked.tag,
            onChanged: (tag) {
              if (busy || tag == null) return;
              setState(
                () => _picked = widget.updates.newer.firstWhere(
                  (o) => o.tag == tag,
                ),
              );
            },
            child: Column(
              children: [
                for (final o in widget.updates.newer) _versionTile(o, muted),
              ],
            ),
          ),
          const Divider(height: 24),
          Text('Downloads from',
              style: theme.textTheme.titleSmall?.copyWith(color: kTextPrimary)),
          const SizedBox(height: 4),
          SelectableText(_picked.downloadUrl, style: muted),
          const SizedBox(height: 2),
          Text(
            "then GitHub's file storage "
            '(release-assets.githubusercontent.com)',
            style: muted,
          ),
          const SizedBox(height: 4),
          // The page, not the APK: a browser download skips the checks below.
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _openPage,
              icon: const Icon(Icons.open_in_new, size: 16),
              label: const Text('Release page'),
            ),
          ),
          if (_linkFailed)
            Text(
              "Couldn't open the link.",
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.error),
            ),
          const SizedBox(height: 8),
          Text(
            'Before installing, the app checks',
            style: theme.textTheme.titleSmall?.copyWith(color: kTextPrimary),
          ),
          const SizedBox(height: 4),
          for (final check in const [
            'It is this app ($kAppPackage)',
            "It is signed with this app's key",
            'It is newer than the installed version',
          ])
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  const Icon(Icons.verified_user_outlined,
                      size: 16, color: kTextSecondary),
                  const SizedBox(width: 8),
                  Expanded(child: Text(check, style: muted)),
                ],
              ),
            ),
          const SizedBox(height: 16),
          ..._stepBody(theme, muted),
        ],
      ),
    );
  }

  Widget _versionTile(ReleaseOption o, TextStyle? muted) {
    final date = o.publishedAt == null
        ? null
        : DateFormat('d MMM yyyy').format(o.publishedAt!);
    final open = _notesOpen.contains(o.tag);
    // One version: nothing to choose, so no radio button.
    final only = widget.updates.newer.length == 1;
    final notesButton = o.notes.isEmpty
        ? null
        : IconButton(
            tooltip: open ? 'Hide notes' : 'Show notes',
            icon: Icon(open ? Icons.expand_less : Icons.expand_more,
                color: kTextSecondary),
            onPressed: () => setState(
              () => open ? _notesOpen.remove(o.tag) : _notesOpen.add(o.tag),
            ),
          );
    final title = Text(versionLabel(o.tag),
        style: const TextStyle(color: kTextPrimary));
    final subtitle = Text([?date, '${_mb(o.sizeBytes)} MB'].join(' · '),
        style: muted);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (only)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: title,
            subtitle: subtitle,
            trailing: notesButton,
          )
        else
          RadioListTile<String>(
            value: o.tag,
            contentPadding: EdgeInsets.zero,
            title: title,
            subtitle: subtitle,
            secondary: notesButton,
          ),
        if (open)
          Padding(
            // Lined up with the version label: the radio and its gap take
            // 56dp; with no radio the label starts at the edge.
            padding: EdgeInsets.fromLTRB(only ? 0 : 56, 0, 8, 8),
            child: Text(o.notes, style: muted),
          ),
      ],
    );
  }

  List<Widget> _stepBody(ThemeData theme, TextStyle? muted) {
    switch (_step) {
      case _Step.choose:
        return [
          // Stacks the buttons, right-aligned, when one row cannot hold
          // them (320dp at 2x text).
          OverflowBar(
            alignment: MainAxisAlignment.end,
            overflowAlignment: OverflowBarAlignment.end,
            spacing: 8,
            overflowSpacing: 8,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton.icon(
                onPressed: _start,
                icon: const Icon(Icons.system_update_alt),
                label: const Text('Download & install'),
              ),
            ],
          ),
        ];
      case _Step.needsPermission:
        return [
          Text(
            'Android needs your OK first. Turn on "Allow from this source" '
            'for FuelPulse, then come back here. You can turn it off again '
            'after updating.',
            style: theme.textTheme.bodyMedium?.copyWith(color: kTextPrimary),
          ),
          const SizedBox(height: 12),
          OverflowBar(
            alignment: MainAxisAlignment.end,
            overflowAlignment: OverflowBarAlignment.end,
            spacing: 8,
            overflowSpacing: 8,
            children: [
              TextButton(
                onPressed: () => setState(() => _step = _Step.choose),
                child: const Text('Back'),
              ),
              FilledButton(
                onPressed: widget.installer.openInstallSettings,
                child: const Text('Open settings'),
              ),
            ],
          ),
        ];
      case _Step.downloading:
        final total = _picked.sizeBytes;
        return [
          LinearProgressIndicator(value: total == 0 ? null : _received / total),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Downloading ${_mb(_received)} of ${_mb(total)} MB',
                  style: muted,
                ),
              ),
              TextButton(
                onPressed: _cancelDownload,
                child: const Text('Cancel'),
              ),
            ],
          ),
        ];
      case _Step.installing:
        return [
          const LinearProgressIndicator(),
          const SizedBox(height: 8),
          Text(
            'Checking and installing. The app closes when it is done; open '
            'it again to finish.',
            style: muted,
          ),
        ];
    }
  }
}
