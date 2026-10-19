import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fuelpulse/services/update_service.dart';

// Ported from the expense tracker's update_service_test.dart, plus the
// per-architecture asset cases FuelPulse's split APKs need.

const _abi = 'arm64-v8a';

Map<String, Object?> _asset(String tag, String abi, {int size = 22000000}) => {
      'name': UpdateService.assetNameFor(abi),
      'size': size,
      'browser_download_url': UpdateService.assetUrlFor(tag, abi),
    };

/// A release as GitHub's /releases endpoint returns it, with all three
/// architectures unless a test overrides the assets.
Map<String, Object?> release(
  String tag, {
  bool draft = false,
  bool prerelease = false,
  List<Map<String, Object?>>? assets,
  String body = 'Notes',
}) =>
    {
      'tag_name': tag,
      'draft': draft,
      'prerelease': prerelease,
      'published_at': '2026-10-19T10:00:00Z',
      'body': body,
      'assets': assets ??
          [for (final abi in kSupportedAbis) _asset(tag, abi)],
    };

void main() {
  group('compareVersions', () {
    test('orders dotted numerics, ignoring v prefix and +build', () {
      expect(UpdateService.compareVersions('1.0.0', 'v1.1.0'), lessThan(0));
      expect(UpdateService.compareVersions('v2.0.0', '1.9.9'), greaterThan(0));
      expect(UpdateService.compareVersions('1.0.0+1', '1.0.0'), 0);
      expect(UpdateService.compareVersions('1.0', '1.0.0'), 0);
      expect(UpdateService.compareVersions('1.10.0', '1.9.0'), greaterThan(0));
    });

    test('malformed input compares equal, so it never announces an update',
        () {
      expect(UpdateService.compareVersions('garbage', '1.0.0'), 0);
      expect(UpdateService.compareVersions('1.0.0', ''), 0);
      expect(UpdateService.compareVersions('1.x.0', '1.0.0'), 0);
    });
  });

  group('parseReleases', () {
    List<String> tags(List<Object?> json,
            [String current = '2.0.0', String abi = _abi]) =>
        [for (final r in UpdateService.parseReleases(json, current, abi)) r.tag];

    test('keeps newer releases, newest first, with their details', () {
      final out = UpdateService.parseReleases([
        release('v2.0.1'),
        release('v2.1.0', body: '  Fixes  '),
        release('v2.0.0'),
      ], '2.0.0', _abi);
      expect([for (final r in out) r.tag], ['v2.1.0', 'v2.0.1']);
      final top = out.first;
      expect(top.abi, _abi);
      expect(top.sizeBytes, 22000000);
      expect(top.notes, 'Fixes');
      expect(
        top.downloadUrl,
        'https://github.com/santhoshunt/fuelpulse/releases/download/'
        'v2.1.0/app-arm64-v8a-release.apk',
      );
      expect(top.publishedAt, isNotNull);
      expect(top.pageUrl,
          'https://github.com/santhoshunt/fuelpulse/releases/tag/v2.1.0');
    });

    test('picks the APK for the phone\'s own architecture', () {
      for (final abi in kSupportedAbis) {
        final out = UpdateService.parseReleases([release('v2.1.0')], '2.0.0', abi);
        expect(out.single.downloadUrl,
            endsWith('/v2.1.0/app-$abi-release.apk'), reason: abi);
      }
    });

    test('skips a release missing this architecture\'s APK', () {
      expect(
        tags([
          release('v2.1.0', assets: [
            _asset('v2.1.0', 'armeabi-v7a'),
            _asset('v2.1.0', 'x86_64'),
          ]),
        ]),
        isEmpty,
      );
    });

    test('drops drafts, prereleases, and older or same versions', () {
      expect(
        tags([
          release('v2.1.0', draft: true),
          release('v2.1.0', prerelease: true),
          release('v2.0.0'),
          release('v1.3.0'),
        ]),
        isEmpty,
      );
    });

    test('drops a tag that is not vX.Y.Z', () {
      expect(
        tags([release('2.1.0'), release('v2.1.0-rc1'), release('v3')]),
        isEmpty,
      );
    });

    test('drops tags that could reach a path or pass for digits', () {
      for (final tag in [
        'v1.0.0/../x',
        'v2.1.0\n',
        'v١.0.0',
        'v1.2.3.4.5',
        'v2.1.0 ',
      ]) {
        expect(tags([release(tag)]), isEmpty, reason: tag);
      }
      expect(tags([release('v2.2.3.4')], '1.0.0'), ['v2.2.3.4']);
    });

    test('drops a release with two APKs for the same architecture', () {
      final apk = _asset('v2.1.0', _abi);
      expect(tags([release('v2.1.0', assets: [apk, apk])]), isEmpty);
    });

    test('drops an asset served from anywhere but its own release URL', () {
      for (final url in [
        'https://github.com/someone-else/fuelpulse/releases/download/'
            'v2.1.0/app-arm64-v8a-release.apk',
        'https://evil.example/app-arm64-v8a-release.apk',
        'http://github.com/santhoshunt/fuelpulse/releases/download/'
            'v2.1.0/app-arm64-v8a-release.apk',
        UpdateService.assetUrlFor('v2.0.9', _abi),
        // Right release, wrong architecture's file.
        UpdateService.assetUrlFor('v2.1.0', 'x86_64'),
      ]) {
        expect(
          tags([
            release('v2.1.0', assets: [
              {..._asset('v2.1.0', _abi), 'browser_download_url': url},
            ]),
          ]),
          isEmpty,
          reason: url,
        );
      }
    });

    test('drops a size of zero, a missing size, or one over the cap', () {
      for (final size in [0, -1, null, UpdateService.maxAssetBytes + 1]) {
        expect(
          tags([
            release('v2.1.0', assets: [
              {..._asset('v2.1.0', _abi), 'size': size},
            ]),
          ]),
          isEmpty,
          reason: '$size',
        );
      }
    });

    test('anything that is not a list of maps gives nothing', () {
      expect(
          UpdateService.parseReleases({'tag_name': 'v9.0.0'}, '1.0.0', _abi), []);
      expect(UpdateService.parseReleases(['x', 3, null], '1.0.0', _abi), []);
      expect(UpdateService.parseReleases(null, '1.0.0', _abi), []);
    });
  });

  group('plainNotes', () {
    test("GitHub's generated notes read as plain text", () {
      expect(
        UpdateService.plainNotes(
          "## What's Changed\r\n"
          '* Fix the **toast** by @me in [#12](https://x/12)\r\n'
          '- `Show all` lists\r\n'
          '\r\n\r\n\r\n'
          '**Full Changelog**: https://github.com/a/b/compare/v1...v2',
        ),
        "What's Changed\n"
        '• Fix the toast by @me in #12\n'
        '• Show all lists\n'
        '\n'
        'Full Changelog: https://github.com/a/b/compare/v1...v2',
      );
    });

    test('marks inside words and unpaired ones stay', () {
      expect(
        UpdateService.plainNotes('Rename FOO__BAR, keep 2**3 and a - dash'),
        'Rename FOO__BAR, keep 2**3 and a - dash',
      );
    });
  });

  group('check', () {
    UpdateService service(MockClient client,
            {String current = '2.0.0', String? abi = _abi}) =>
        UpdateService(
          clientFactory: () => client,
          currentVersion: () async => current,
          primaryAbi: () async => abi,
        );

    test('asks the releases list and returns the newer ones', () async {
      Uri? asked;
      final client = MockClient((request) async {
        asked = request.url;
        return http.Response(
          jsonEncode([release('v2.1.0'), release('v2.0.1')]),
          200,
        );
      });
      final result = await service(client).check();
      expect(asked.toString(),
          'https://api.github.com/repos/santhoshunt/fuelpulse/releases?per_page=30');
      expect(result, isA<UpdateAvailable>());
      final update = result as UpdateAvailable;
      expect(update.latestTag, 'v2.1.0');
      expect(update.updates.newer, hasLength(2));
      expect(update.updates.currentVersion, '2.0.0');
      expect(update.htmlUrl, endsWith('/releases/tag/v2.1.0'));
    });

    test('a phone with no published architecture fails without asking',
        () async {
      var asked = false;
      final client = MockClient((request) async {
        asked = true;
        return http.Response('[]', 200);
      });
      final result = await service(client, abi: null).check();
      expect(result, isA<CheckFailed>());
      expect((result as CheckFailed).message, contains('processor'));
      expect(asked, isFalse);
    });

    test('nothing newer gives UpToDate with the current version', () async {
      final client = MockClient(
        (request) async => http.Response(jsonEncode([release('v2.0.0')]), 200),
      );
      final result = await service(client).check();
      expect(result, isA<UpToDate>());
      expect((result as UpToDate).currentVersion, '2.0.0');
    });

    test('non-200 gives CheckFailed naming the status', () async {
      final client =
          MockClient((request) async => http.Response('rate limited', 403));
      final result = await service(client).check();
      expect(result, isA<CheckFailed>());
      expect((result as CheckFailed).message, contains('403'));
    });

    test('malformed JSON or a non-list gives CheckFailed', () async {
      for (final body in ['not json', jsonEncode({'tag_name': 'v9.0.0'})]) {
        final client = MockClient((request) async => http.Response(body, 200));
        expect(await service(client).check(), isA<CheckFailed>());
      }
    });

    test('network error gives CheckFailed', () async {
      final client = MockClient(
          (request) async => throw http.ClientException('no network'));
      expect(await service(client).check(), isA<CheckFailed>());
    });
  });

  group('shouldCheckForUpdate', () {
    final now = DateTime(2026, 10, 19, 12);
    test('off never checks', () {
      expect(shouldCheckForUpdate(enabled: false, lastCheck: null, now: now),
          isFalse);
    });
    test('never checked, or a day or more ago, checks', () {
      expect(shouldCheckForUpdate(enabled: true, lastCheck: null, now: now),
          isTrue);
      expect(
        shouldCheckForUpdate(
            enabled: true,
            lastCheck: now.subtract(const Duration(hours: 24)),
            now: now),
        isTrue,
      );
    });
    test('within the day waits', () {
      expect(
        shouldCheckForUpdate(
            enabled: true,
            lastCheck: now.subtract(const Duration(hours: 23)),
            now: now),
        isFalse,
      );
    });
  });
}
