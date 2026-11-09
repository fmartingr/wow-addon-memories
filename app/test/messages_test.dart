import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:memories_core/memories_core.dart';
import 'package:wow_journey/l10n/app_localizations.dart';
import 'package:wow_journey/src/settings/settings_store.dart';
import 'package:wow_journey/src/ui/messages.dart';
import 'package:wow_journey/src/upload/notice.dart';
import 'package:wow_journey/src/version.dart';

import 'support/texts.dart';

AppLocalizations _in(Locale locale) => lookupAppLocalizations(locale);

void main() {
  setUpAll(initializeDateFormatting);

  group('issueText', () {
    for (final code in GatherIssueCode.values) {
      test('$code has plain English text', () {
        final text = issueText(en, code);
        expect(text, isNotEmpty);
        expect(text, endsWith('.'));
        expect(text, isNot(contains('--')));
        expect(text, isNot(contains('Exception')));
        expect(text, isNot(contains(r'$')));
        expect(text, isNot(contains(code.name)));
        for (final sentence in text.split('. ')) {
          expect(
            sentence.split(' ').length,
            lessThanOrEqualTo(20),
            reason: 'short sentences: "$sentence"',
          );
        }
      });
    }

    test('no data tells the player what to do', () {
      expect(
        issueText(en, GatherIssueCode.noData),
        'No Memories data yet. Play with the Memories addons on, then log out.',
      );
    });
  });

  group('every language', () {
    for (final locale in AppLocalizations.supportedLocales) {
      final l = _in(locale);
      final name = locale.languageCode;

      test('$name: each issue, fix and notice text is whole', () {
        final texts = [
          for (final c in GatherIssueCode.values) issueText(l, c),
          for (final f in IssueFix.values) f.label(l),
          for (final n in SettingsNotice.values) settingsNoticeText(l, n),
          for (final e in SiteError.values) siteErrorText(l, e),
          for (final s in ['none', 'pending', 'approved', 'denied'])
            screenshotsText(l, s),
          for (final code in _knownUploadCodes)
            uploadErrorText(l, code, 'server text', 'https://example.com'),
          noticeText(l, const ClaimedNotice('Nandu', 'Brumamar')),
          noticeText(l, const ClaimedNotice('Nandu', null)),
          noticeText(l, const RejectedNotice('Nandu', 'a: b.', 0)),
          noticeText(l, const RejectedNotice('Nandu', 'a: b.', 1)),
          noticeText(l, const RejectedNotice('Nandu', 'a: b.', 5)),
          noticeText(l, const BusyNotice()),
          noticeText(l, const GenericFailureNotice()),
          noticeText(l, const NotAMemoriesSiteNotice()),
          for (final n in [0, 1, 2, 5]) ...[
            l.andMore(n),
            l.syncUploaded(n),
            l.syncShots(n),
            l.syncRemoved(n),
            l.syncFailed(n),
            l.syncShotsFailed(n),
            l.flavorInstallFolder(n, 'a, b'),
          ],
        ];
        for (final text in texts) {
          expect(text, isNotEmpty);
          expect(text, isNot(contains('{')), reason: text);
          expect(text, isNot(contains('}')), reason: text);
          expect(text, isNot(contains('null')), reason: text);
        }
      });
    }
  });

  group('known upload codes', () {
    test('a known code shows its own text, not the text of the server', () {
      for (final code in _knownUploadCodes) {
        expect(
          uploadErrorText(en, code, 'server text', 'https://example.com'),
          isNot('server text'),
          reason: code,
        );
      }
    });

    test('an unknown code shows the text of the server', () {
      expect(
        uploadErrorText(en, 'brand_new', 'server text', 'https://example.com'),
        'server text',
      );
      expect(
        uploadErrorText(en, 'http_x', 'server text', 'https://example.com'),
        'server text',
      );
    });

    test('bad_site says why the address is refused', () {
      expect(
        uploadErrorText(en, 'bad_site', 'x', 'http://example.com'),
        en.siteHttpLoopback,
      );
      expect(
        uploadErrorText(en, 'bad_site', 'x', 'https://example.com/api'),
        en.sitePath,
      );
    });

    test('http_<n> names the status', () {
      expect(
        uploadErrorText(en, 'http_502', 'x', 'https://example.com'),
        contains('status 502'),
      );
    });

    test('the network text names the host, not the port', () {
      expect(
        uploadErrorText(en, 'network', 'x', 'http://localhost:8080'),
        startsWith('Could not reach localhost.'),
      );
    });

    test('a character name goes before the text', () {
      expect(
        noticeText(
          en,
          const UploadErrorNotice(
            'quota',
            'x',
            'https://example.com',
            who: 'A',
          ),
        ),
        startsWith('A: '),
      );
    });

    test('the same notice is equal and different ones are not', () {
      const a = UploadErrorNotice('quota', 'x', 'https://example.com');
      const b = UploadErrorNotice('quota', 'x', 'https://example.com');
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(const TextNotice('x')));
      expect(a, isNot(const UploadErrorNotice('busy', 'x', 'https://a.b')));
    });
  });

  test('the fixes are the ones a player can do', () {
    expect(issueFix(GatherIssueCode.noWtf), IssueFix.chooseWowFolder);
    expect(issueFix(GatherIssueCode.notWritable), IssueFix.chooseBackupFolder);
    expect(issueFix(GatherIssueCode.overlap), IssueFix.chooseBackupFolder);
    expect(issueFix(GatherIssueCode.lockHeld), IssueFix.tryAgain);
    expect(issueFix(GatherIssueCode.ioError), IssueFix.tryAgain);
    expect(issueFix(GatherIssueCode.badIndex), IssueFix.openLatest);
    expect(issueFix(GatherIssueCode.noData), isNull);
    expect(IssueFix.chooseWowFolder.label(en), 'Choose folder');
    expect(IssueFix.tryAgain.label(en), 'Try again');
  });

  test('formatSize', () {
    expect(formatSize(en, 0), '0 bytes');
    expect(formatSize(en, 1023), '1023 bytes');
    expect(formatSize(en, 1536), '1.5 KB');
    expect(formatSize(en, 5 * 1024 * 1024), '5.0 MB');
    expect(formatSize(en, 3 * 1024 * 1024 * 1024), '3.0 GB');
  });

  for (final locale in AppLocalizations.supportedLocales) {
    test('${locale.languageCode}: sizes and times use whole text', () {
      final l = _in(locale);
      expect(formatSize(l, 1536), isNot(contains('{')));
      final now = DateTime(2026, 11, 8, 20);
      expect(formatTime(l, DateTime(2026, 11, 8, 14, 32), now), '14:32');
      expect(
        formatTime(l, DateTime(2026, 11, 7, 9, 5), now),
        '2026-11-07 09:05',
      );
    });
  }

  test('formatTime shows the date only on another day', () {
    final now = DateTime(2026, 11, 8, 20);
    expect(formatTime(en, DateTime(2026, 11, 8, 14, 32), now), '14:32');
    expect(
      formatTime(en, DateTime(2026, 11, 7, 9, 5), now),
      '2026-11-07 09:05',
    );
  });

  test('className', () {
    expect(className(en, 'HUNTER'), 'Hunter');
    expect(className(en, 'DEATHKNIGHT'), 'Death Knight');
    expect(className(en, 'DEMONHUNTER'), 'Demon Hunter');
    expect(className(en, 'SOMETHINGNEW'), 'Somethingnew');
    expect(className(en, ''), '');
  });

  test('the app version is the version of pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final version = RegExp(
      r'^version: ([^+\s]+)',
      multiLine: true,
    ).firstMatch(pubspec)![1];
    expect(appVersion, version);
  });

  group('website text', () {
    test('siteLabel drops the scheme and keeps a port', () {
      expect(siteLabel('https://wowjourney.xyz'), 'wowjourney.xyz');
      expect(siteLabel('http://localhost:8080'), 'localhost:8080');
      expect(siteLabel('nonsense'), 'nonsense');
    });

    test('the revoked and claimed texts say what happened', () {
      expect(
        keyRevokedText('https://wowjourney.xyz'),
        "The website admin blocked this app's key. Uploads to wowjourney.xyz "
        'are off.',
      );
      expect(
        claimedText('Nandu', 'Brumamar'),
        'Another player already uploaded Nandu on Brumamar. Ask the website '
        'admin.',
      );
      expect(
        noticeEn(const ClaimedNotice('Nandu', null)),
        'Another player already uploaded Nandu on its realm. Ask the website '
        'admin.',
      );
    });

    test('a rejected upload counts the problems that it does not list', () {
      String rejected(int more) =>
          noticeEn(RejectedNotice('Nandu', 'journey, line 1: bad.', more));
      expect(
        rejected(0),
        'The website did not accept the data of Nandu: journey, line 1: bad. '
        'Fix the saved files, then upload again.',
      );
      expect(rejected(1), contains('bad. And 1 more problem. Fix'));
      expect(rejected(2), contains('bad. And 2 more problems. Fix'));
    });

    test('the 3-file list says how many more', () {
      expect(en.andMore(1), 'and 1 more');
      expect(en.andMore(2), 'and 2 more');
    });

    test('an install folder counts its game versions', () {
      expect(
        en.flavorInstallFolder(1, '_retail_'),
        'This is the World of Warcraft folder. It holds one game version: '
        '_retail_. Pick that folder.',
      );
      expect(
        en.flavorInstallFolder(2, '_retail_, _classic_'),
        'This is the World of Warcraft folder. It holds 2 game versions: '
        '_retail_, _classic_. Pick one of them.',
      );
    });

    test('every screenshot state has a sentence', () {
      for (final state in ['none', 'pending', 'approved', 'denied']) {
        expect(screenshotsText(en, state), endsWith('.'));
      }
    });

    test('the sync summary counts characters and screenshots', () {
      const ok = CharacterResult(
        id: 'a',
        path: 'p',
        status: SyncStatus.uploaded,
        shots: ShotsResult(uploaded: 2),
      );
      expect(
        syncSummary(
          const SyncReport(screenshots: 'approved', characters: [ok, ok]),
        ),
        'Uploaded 2 characters, sent 4 screenshots.',
      );
      expect(
        syncSummary(const SyncReport(screenshots: 'none', characters: [])),
        'Everything is up to date.',
      );
      const shotsOnly = CharacterResult(
        id: 'a',
        path: 'p',
        status: SyncStatus.unchanged,
        shots: ShotsResult(uploaded: 1, errors: ['x']),
      );
      expect(
        syncSummary(
          const SyncReport(screenshots: 'approved', characters: [shotsOnly]),
        ),
        'Sent 1 screenshot, 1 screenshot failed.',
      );
      const removed = CharacterResult(
        id: 'a',
        path: 'p',
        status: SyncStatus.removed,
      );
      expect(
        syncSummary(
          const SyncReport(screenshots: 'none', characters: [removed]),
        ),
        'Everything is up to date, skipped 1 removed character (Upload now '
        'sends it again).',
      );
      expect(
        syncSummary(
          const SyncReport(
            screenshots: 'none',
            characters: [ok, removed, removed],
          ),
        ),
        'Uploaded 1 character, sent 2 screenshots, skipped 2 removed characters '
        '(Upload now sends them again).',
      );
    });

    test('the removal message says the rule', () {
      expect(removedText('Nandu'), startsWith('Nandu was removed'));
      expect(removedText('Nandu'), contains('Gathers do not upload it again'));
      expect(removedText('Nandu'), contains('Upload now does'));
    });
  });
}

const _knownUploadCodes = [
  'network',
  'bad_response',
  'bad_files',
  'no_index',
  'bad_key',
  'bad_site',
  'bad_state',
  'failed',
  'http_500',
  'key_revoked',
  'not_registered',
  'invalid',
  'invite_invalid',
  'bad_signature',
  'rate_limited',
  'busy',
  'quota',
  'too_large',
  'internal',
  'bad_request',
  'not_found',
  'screenshots_not_approved',
  'unsupported_image',
  'not_referenced',
  'guid_mismatch',
  'gzip_required',
];
