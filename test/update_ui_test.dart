import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fuelpulse/screens/settings/about_section.dart';
import 'package:fuelpulse/services/update_downloader.dart';
import 'package:fuelpulse/services/update_installer.dart';
import 'package:fuelpulse/services/update_prefs.dart';
import 'package:fuelpulse/services/update_service.dart';
import 'package:fuelpulse/utils/constants.dart';
import 'package:fuelpulse/widgets/update_banner.dart';
import 'package:fuelpulse/widgets/update_sheet.dart';

// Ported from the expense tracker's update_ui_test.dart and
// update_sheet_v1381_test.dart.

ReleaseOption opt(String tag) => ReleaseOption(
      tag: tag,
      abi: 'arm64-v8a',
      publishedAt: DateTime(2026, 10, 19),
      sizeBytes: 22 * 1024 * 1024,
      notes: 'What changed in $tag',
      downloadUrl: UpdateService.assetUrlFor(tag, 'arm64-v8a'),
    );

class FakeInstaller implements UpdateInstaller {
  bool allowed = true;
  String? refusal;
  int installs = 0;
  int settingsOpened = 0;

  @override
  Future<bool> canInstall() async => allowed;

  @override
  Future<void> openInstallSettings() async => settingsOpened++;

  @override
  Future<String?> install(File apk) async {
    installs++;
    return refusal;
  }

  @override
  Future<String> currentVersion() async => '2.0.0';

  @override
  Future<String?> primaryAbi() async => 'arm64-v8a';
}

class FakeDownloader extends UpdateDownloader {
  int downloads = 0;
  int cleanups = 0;

  @override
  Future<File> download(
    ReleaseOption option, {
    void Function(int received, int total)? onProgress,
    DownloadCancel? cancel,
  }) async {
    downloads++;
    return File('${option.tag}.apk');
  }

  @override
  Future<void> cleanup() async => cleanups++;
}

/// A download that stays in progress until the test calls [finish], so the
/// sheet's downloading step can be seen and cancelled.
class _HeldDownloader extends UpdateDownloader {
  final _done = Completer<void>();
  void Function(int received, int total)? progress;
  DownloadCancel? cancel;

  void finish() {
    if (!_done.isCompleted) _done.complete();
  }

  @override
  Future<File> download(
    ReleaseOption option, {
    void Function(int received, int total)? onProgress,
    DownloadCancel? cancel,
  }) async {
    progress = onProgress;
    this.cancel = cancel;
    await _done.future;
    throw const UpdateDownloadException('Download cancelled.');
  }

  @override
  Future<void> cleanup() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    availableUpdate.value = null;
  });

  Future<void> pumpWith(WidgetTester tester, Widget body) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: body)));
    await tester.pumpAndSettle();
  }

  test('versions are written one way', () {
    expect(versionLabel('2.0.0'), 'v2.0.0');
    expect(versionLabel('v2.0.1'), 'v2.0.1');
    expect(versionLabel('V2.0.1'), 'v2.0.1');
  });

  testWidgets('the banner offers the newest version; Not now waits for a '
      'newer one', (tester) async {
    await pumpWith(tester, const UpdateBanner());
    expect(find.textContaining('Update available'), findsNothing);

    availableUpdate.value = UpdateList('2.0.0', [opt('v2.0.2'), opt('v2.0.1')]);
    await tester.pump();
    expect(find.text('Update available: v2.0.2'), findsOneWidget);
    expect(find.text('2 newer versions on GitHub.'), findsOneWidget);

    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Update available'), findsNothing);
    expect(await dismissedUpdateTag(), 'v2.0.2');

    availableUpdate.value = UpdateList('2.0.0', [opt('v2.0.3')]);
    await tester.pump();
    expect(find.text('Update available: v2.0.3'), findsOneWidget);
  });

  testWidgets('a version answered with Not now stays hidden after restart',
      (tester) async {
    SharedPreferences.setMockInitialValues({kUpdateDismissedKey: 'v2.0.2'});
    availableUpdate.value = UpdateList('2.0.0', [opt('v2.0.2')]);
    await pumpWith(tester, const UpdateBanner());
    expect(find.textContaining('Update available'), findsNothing);
  });

  Future<(FakeInstaller, FakeDownloader)> openSheet(
    WidgetTester tester, {
    bool allowed = true,
    String? refusal,
    UpdateList? updates,
  }) async {
    final installer = FakeInstaller()
      ..allowed = allowed
      ..refusal = refusal;
    final downloader = FakeDownloader();
    await pumpWith(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => showUpdateSheet(
            context,
            updates ?? UpdateList('2.0.0', [opt('v2.1.0'), opt('v2.0.1')]),
            installer: installer,
            downloader: downloader,
          ),
          child: const Text('open'),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return (installer, downloader);
  }

  Future<void> tapInstall(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Download & install'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Download & install'));
    await tester.pumpAndSettle();
  }

  testWidgets('the sheet names the download URL and the checks before any '
      'tap', (tester) async {
    final (installer, downloader) = await openSheet(tester);
    expect(find.text('Choose a version'), findsOneWidget);
    expect(find.text('On v2.0.0'), findsOneWidget);
    expect(find.text('v2.1.0'), findsOneWidget);
    expect(find.text('v2.0.1'), findsOneWidget);
    expect(find.text(UpdateService.assetUrlFor('v2.1.0', 'arm64-v8a')),
        findsOneWidget);
    expect(find.textContaining(kAppPackage), findsOneWidget);
    expect(find.text("It is signed with this app's key"), findsOneWidget);
    expect(downloader.downloads, 0, reason: 'nothing before the tap');

    await tester.tap(find.text('v2.0.1'));
    await tester.pump();
    expect(find.text(UpdateService.assetUrlFor('v2.0.1', 'arm64-v8a')),
        findsOneWidget);
    expect(installer.installs, 0);
  });

  testWidgets('one version: the title names it and its notes are open',
      (tester) async {
    await openSheet(tester, updates: UpdateList('2.0.0', [opt('v2.0.1')]));
    expect(find.text('Update to v2.0.1'), findsOneWidget);
    expect(find.text('Choose a version'), findsNothing);
    expect(find.byType(Radio<String>), findsNothing);
    expect(find.text('What changed in v2.0.1'), findsOneWidget);

    await tester.tap(find.byTooltip('Hide notes'));
    await tester.pump();
    expect(find.text('What changed in v2.0.1'), findsNothing);
  });

  testWidgets('several versions: only the newest notes start open',
      (tester) async {
    await openSheet(tester);
    expect(find.byType(Radio<String>), findsNWidgets(2));
    expect(find.text('What changed in v2.1.0'), findsOneWidget);
    expect(find.text('What changed in v2.0.1'), findsNothing);
  });

  testWidgets('without the install permission it explains and opens '
      'settings', (tester) async {
    final (installer, downloader) = await openSheet(tester, allowed: false);
    await tapInstall(tester);
    expect(find.textContaining('Android needs your OK first'), findsOneWidget);
    expect(find.textContaining('for FuelPulse'), findsOneWidget);
    expect(downloader.downloads, 0);
    await tester.ensureVisible(find.text('Open settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open settings'));
    await tester.pump();
    expect(installer.settingsOpened, 1);
  });

  testWidgets('a double tap starts one download', (tester) async {
    final (installer, downloader) =
        await openSheet(tester, refusal: 'refused');
    await tester.ensureVisible(find.text('Download & install'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Download & install'));
    await tester.tap(find.text('Download & install'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(downloader.downloads, 1);
    expect(installer.installs, 1);
  });

  testWidgets('a refused install closes the sheet and says why, with the '
      'release page', (tester) async {
    final (installer, downloader) = await openSheet(
      tester,
      refusal: "This update is not signed with this app's key.",
    );
    await tapInstall(tester);
    expect(downloader.downloads, 1);
    expect(installer.installs, 1);
    expect(downloader.cleanups, greaterThan(0), reason: 'no APK left');
    expect(find.text('Choose a version'), findsNothing);
    expect(find.text("This update is not signed with this app's key."),
        findsOneWidget);
    expect(find.text('Release page'), findsOneWidget);
    expect(await installingUpdateTag(), isNull,
        reason: 'a refused install leaves nothing to report');
  });

  testWidgets('the downloading step shows progress and Cancel stops it',
      (tester) async {
    final downloader = _HeldDownloader();
    await pumpWith(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => showUpdateSheet(
            context,
            UpdateList('2.0.0', [opt('v2.1.0')]),
            installer: FakeInstaller(),
            downloader: downloader,
          ),
          child: const Text('open'),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Download & install'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Download & install'));
    await tester.pump();
    await tester.pump();

    downloader.progress!(11 * 1024 * 1024, 22 * 1024 * 1024);
    await tester.pump();
    expect(find.text('Downloading 11.0 of 22.0 MB'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pump();
    expect(downloader.cancel!.cancelled, isTrue);
    expect(find.text('Download & install'), findsOneWidget,
        reason: 'back to the version list');
    downloader.finish();
    await tester.pumpAndSettle();
  });

  testWidgets('the open notes line up with the version label',
      (tester) async {
    await openSheet(tester, updates: UpdateList('2.0.0', [opt('v2.0.1')]));
    expect(tester.getTopLeft(find.text('What changed in v2.0.1')).dx,
        tester.getTopLeft(find.text('v2.0.1')).dx);
  });

  testWidgets('with several versions the notes still line up with the label',
      (tester) async {
    await openSheet(tester);
    expect(tester.getTopLeft(find.text('What changed in v2.1.0')).dx,
        tester.getTopLeft(find.text('v2.1.0')).dx);
  });

  testWidgets('a started install records its tag for the next launch',
      (tester) async {
    await openSheet(tester);
    await tapInstall(tester);
    expect(await installingUpdateTag(), 'v2.1.0');
  });

  group('Settings About section', () {
    UpdateService serviceReturning(List<Object?> releases) => UpdateService(
          clientFactory: () => MockClient(
              (_) async => http.Response(jsonEncode(releases), 200)),
          currentVersion: () async => '2.0.0',
          primaryAbi: () async => 'arm64-v8a',
        );

    Map<String, Object?> releaseJson(String tag) => {
          'tag_name': tag,
          'draft': false,
          'prerelease': false,
          'published_at': '2026-10-19T10:00:00Z',
          'body': 'Notes for $tag',
          'assets': [
            {
              'name': UpdateService.assetNameFor('arm64-v8a'),
              'size': 1000,
              'browser_download_url':
                  UpdateService.assetUrlFor(tag, 'arm64-v8a'),
            },
          ],
        };

    Future<void> pumpAbout(WidgetTester tester, UpdateService service) async {
      await pumpWith(
        tester,
        SingleChildScrollView(
          child: AboutSection(
              service: () => service, installer: FakeInstaller()),
        ),
      );
    }

    testWidgets('shows the installed version', (tester) async {
      await pumpAbout(tester, serviceReturning([]));
      expect(find.text('FuelPulse v2.0.0'), findsOneWidget);
    });

    testWidgets('a newer release opens the update sheet', (tester) async {
      await pumpAbout(tester, serviceReturning([releaseJson('v2.1.0')]));
      await tester.tap(find.text('Check for updates'));
      await tester.runAsync(
          () => Future.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();
      expect(find.text('Update to v2.1.0'), findsOneWidget);
      expect(availableUpdate.value?.newer.first.tag, 'v2.1.0');
    });

    testWidgets('no newer release says so', (tester) async {
      await pumpAbout(tester, serviceReturning([releaseJson('v2.0.0')]));
      await tester.tap(find.text('Check for updates'));
      await tester.runAsync(
          () => Future.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();
      expect(find.text("You're on the latest version (v2.0.0)."),
          findsOneWidget);
    });

    testWidgets('the launch check switch is stored', (tester) async {
      await pumpAbout(tester, serviceReturning([]));
      expect(await updateOnLaunch(), isTrue);
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(await updateOnLaunch(), isFalse);
    });
  });

  testWidgets('the one-version title fits 320dp at 2x text', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await openSheet(tester, updates: UpdateList('2.0.0', [opt('v2.0.1')]));
    expect(tester.takeException(), isNull);
    expect(find.text('Update to v2.0.1'), findsOneWidget);
  });
}
