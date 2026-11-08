import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:memories_core/memories_core.dart' hide UploadState;
import 'package:wow_journey/src/gather/gather_controller.dart';
import 'package:wow_journey/src/settings/settings.dart';
import 'package:wow_journey/src/settings/settings_controller.dart';
import 'package:wow_journey/src/ui/messages.dart';
import 'package:wow_journey/src/upload/upload_controller.dart';

import 'support/fakes.dart';

const String site = 'https://wowjourney.xyz';
const String otherSite = 'http://localhost:8080';
final DateTime uploadedAt = DateTime(2026, 11, 8, 15, 30);

const RemoteCharacter nandu = RemoteCharacter(
  path: 'wow/eu/brumamar/nandu',
  url: '$site/wow/eu/brumamar/nandu/',
  guid: 'Player-1-00000001',
  steps: 15,
  updated: 1,
);

CharacterResult _result(
  String id, {
  SyncStatus status = SyncStatus.uploaded,
  UploadException? error,
  ShotsResult shots = const ShotsResult(),
}) => CharacterResult(
  id: id,
  path: 'wow/eu/${id.substring(3)}'.replaceFirst('-', '/'),
  status: status,
  error: error,
  shots: shots,
);

class _Rig {
  _Rig({Settings settings = readySettings, bool registered = true})
    : store = FakeSettingsStore((settings: settings, notice: null)),
      upload = FakeUploadService(),
      gatherService = FakeGatherService(
        snapshot: const BackupSnapshot(
          characters: [
            CharacterSummary(
              id: 'eu-brumamar-nandu',
              name: 'Ñandú',
              realm: 'Brumamar',
            ),
          ],
        ),
      ) {
    settingsController = SettingsController(store);
    gather = GatherController(gatherService);
    if (registered) {
      upload.registeredSites.add(settings.site);
      upload.fingerprint = '0123456789abcdef';
    }
    controller = UploadController(
      service: upload,
      settings: settingsController,
      gather: gather,
      clock: () => uploadedAt,
    );
  }

  final FakeSettingsStore store;
  final FakeUploadService upload;
  final FakeGatherService gatherService;
  late final SettingsController settingsController;
  late final GatherController gather;
  late final UploadController controller;

  Future<void> load() async {
    await settingsController.load();
    await gather.refresh('/backups/WoW Journey');
    await pumpEventQueue();
  }

  Future<void> gatherOnce() async {
    await gather.gatherNow(
      flavorDir: retailDir,
      backupRoot: '/backups/WoW Journey',
    );
    await pumpEventQueue();
  }

  void dispose() {
    controller.dispose();
    gather.dispose();
    settingsController.dispose();
  }
}

Settings get _on => readySettings.copyWith(upload: true);

Future<_Rig> _rig({
  Settings settings = readySettings,
  bool registered = true,
}) async {
  final rig = _Rig(settings: settings, registered: registered);
  addTearDown(rig.dispose);
  await rig.load();
  return rig;
}

void main() {
  group('state', () {
    test('a key error clears once the key reads again', () async {
      final rig = _Rig();
      addTearDown(rig.dispose);
      rig.upload.statusError = const UploadException('bad_key', 'Bad key.');
      await rig.load();
      expect(rig.controller.registerError, 'Bad key.');
      rig.upload.statusError = null;
      await rig.controller.refresh();
      expect(rig.controller.registerError, isNull);
      expect(rig.controller.registered, isTrue);
    });

    test('is unregistered until the key is registered on the site', () async {
      final rig = await _rig(registered: false);
      expect(rig.controller.state, UploadState.unregistered);
      expect(rig.controller.registered, isFalse);
      expect(rig.upload.calls, isEmpty);
    });

    test('is off when registered with the switch off, and reads me', () async {
      final rig = _Rig();
      rig.upload.meInfo = const MeInfo(
        screenshots: 'pending',
        characters: [nandu],
      );
      addTearDown(rig.dispose);
      await rig.load();
      final c = rig.controller;
      expect(c.state, UploadState.off);
      expect(c.fingerprint, '0123456789abcdef');
      expect(c.characters, [nandu]);
      expect(c.screenshots, 'pending');
      expect(rig.upload.calls, ['me $site']);
    });

    test('is idle when registered with the switch on', () async {
      final rig = await _rig(settings: _on);
      expect(rig.controller.state, UploadState.idle);
    });

    test('names a character from the gather, or from its path', () async {
      final rig = await _rig();
      await rig.gather.refresh('/backups/WoW Journey');
      expect(rig.controller.describe(nandu.path), (
        name: 'Ñandú',
        realm: 'Brumamar',
      ));
      expect(rig.controller.describe('wow/eu/other-realm/zed'), (
        name: 'zed',
        realm: 'other-realm',
      ));
    });
  });

  group('uploadNow', () {
    test('goes uploading, then done, and refreshes the characters', () async {
      final rig = await _rig(settings: _on);
      rig.upload
        ..pendingSync = Completer<SyncReport>()
        ..meInfo = const MeInfo(screenshots: 'none', characters: [nandu]);
      final states = <UploadState>[];
      rig.controller.addListener(() => states.add(rig.controller.state));

      final run = rig.controller.uploadNow();
      expect(rig.controller.state, UploadState.uploading);
      expect(rig.controller.busy, isTrue);
      rig.upload.pendingSync!.complete(
        SyncReport(
          screenshots: 'none',
          characters: [_result('eu-brumamar-nandu')],
        ),
      );
      final report = await run;

      expect(report!.characters, hasLength(1));
      expect(rig.controller.state, UploadState.done);
      expect(rig.controller.lastUpload, uploadedAt);
      expect(rig.controller.issues, isEmpty);
      expect(rig.controller.characters, [nandu]);
      expect(states, contains(UploadState.uploading));
      expect(states.last, UploadState.done);
      expect(rig.upload.syncs, [(site, '/backups/WoW Journey/latest')]);
    });

    test('progress follows the sync, then clears', () async {
      final rig = await _rig(settings: _on);
      rig.upload.pendingSync = Completer<SyncReport>();
      final run = rig.controller.uploadNow();
      expect(rig.controller.progress, isNull);

      rig.upload.onProgress!(0, 90);
      expect(rig.controller.progress, 0);
      expect(rig.controller.progressCounts, (done: 0, total: 90));
      rig.upload.onProgress!(12, 90);
      expect(rig.controller.progress, closeTo(12 / 90, 1e-9));
      expect(rig.controller.progressCounts, (done: 12, total: 90));

      rig.upload.pendingSync!.complete(
        const SyncReport(screenshots: 'none', characters: []),
      );
      await run;
      expect(rig.controller.progress, isNull);
      expect(rig.controller.progressCounts, (done: 0, total: 0));
    });

    test('nothing to send leaves the progress unknown', () async {
      final rig = await _rig(settings: _on);
      rig.upload.pendingSync = Completer<SyncReport>();
      final run = rig.controller.uploadNow();
      rig.upload.onProgress!(0, 0);
      expect(rig.controller.progress, isNull);
      rig.upload.pendingSync!.complete(
        const SyncReport(screenshots: 'none', characters: []),
      );
      await run;
    });

    test(
      'a paused run is neutral: no issue, no failure, and it resumes',
      () async {
        final rig = await _rig(settings: _on);
        const busy = UploadException(
          'rate_limited',
          'Too many requests.',
          status: 429,
          retryAfter: 30,
          recoverable: true,
        );
        rig.upload.report = SyncReport(
          screenshots: 'approved',
          characters: [
            _result('eu-brumamar-nandu', shots: const ShotsResult(stop: busy)),
            _result(
              'eu-brumamar-nandu',
              status: SyncStatus.failed,
              error: busy,
            ),
          ],
        );
        await rig.gatherOnce();
        expect(rig.controller.state, UploadState.paused);
        expect(rig.controller.issues, isEmpty);
        expect(rig.controller.lastReport!.paused, isTrue);
        expect(rig.controller.lastUpload, isNull);

        rig.upload.report = null;
        await rig.controller.uploadNow();
        expect(rig.upload.syncs, hasLength(2));
        expect(rig.controller.state, UploadState.done);
        expect(rig.controller.lastUpload, uploadedAt);
      },
    );

    test('a recoverable error of the first request is paused too', () async {
      final rig = await _rig(settings: _on);
      rig.upload.syncError = const UploadException(
        'rate_limited',
        'Too many requests.',
        status: 429,
        recoverable: true,
      );
      await rig.controller.uploadNow();
      expect(rig.controller.state, UploadState.paused);
      expect(rig.controller.issues, isEmpty);
    });

    test('a real error next to a pause still shows', () async {
      final rig = await _rig(settings: _on);
      rig.upload.report = SyncReport(
        screenshots: 'none',
        characters: [
          _result(
            'eu-brumamar-nandu',
            status: SyncStatus.failed,
            error: const UploadException('claimed', 'Text.', status: 409),
          ),
        ],
      );
      await rig.controller.uploadNow();
      expect(rig.controller.state, UploadState.failed);
      expect(rig.controller.issues, hasLength(1));
    });

    test('returns null while an upload runs', () async {
      final rig = await _rig(settings: _on);
      rig.upload.pendingSync = Completer<SyncReport>();
      final first = rig.controller.uploadNow();
      expect(await rig.controller.uploadNow(), isNull);
      rig.upload.pendingSync!.complete(
        const SyncReport(screenshots: 'none', characters: []),
      );
      await first;
      expect(rig.upload.syncs, hasLength(1));
    });

    test('does nothing when the switch is off', () async {
      final rig = await _rig();
      expect(await rig.controller.uploadNow(), isNull);
      expect(rig.upload.syncs, isEmpty);
      expect(rig.controller.state, UploadState.off);
    });

    test('does nothing when the key is not registered', () async {
      final rig = await _rig(settings: _on, registered: false);
      expect(await rig.controller.uploadNow(), isNull);
      expect(rig.upload.syncs, isEmpty);
    });

    test('a failed character makes the state failed, and the next gather tries again', () async {
      final rig = await _rig(settings: _on);
      rig.upload.report = SyncReport(
        screenshots: 'none',
        characters: [
          _result(
            'eu-brumamar-nandu',
            status: SyncStatus.failed,
            error: const UploadException(
              'claimed',
              'Server text.',
              status: 409,
            ),
          ),
        ],
      );
      await rig.gatherOnce();
      expect(rig.controller.state, UploadState.failed);
      expect(rig.controller.issues, [claimedText('Ñandú', 'Brumamar')]);
      expect(syncSummaryText(rig.upload.report!), '1 character failed.');

      rig.upload.report = null;
      await rig.gatherOnce();
      expect(rig.upload.syncs, hasLength(2));
      expect(rig.controller.state, UploadState.done);
      expect(rig.controller.issues, isEmpty);
    });

    test(
      'a rejected upload shows the first 3 problems in plain words',
      () async {
        final rig = await _rig(settings: _on);
        final problems = [
          for (var i = 1; i <= 5; i++)
            UploadProblem(
              file: 'journey',
              line: i,
              field: 'k',
              reason: 'the value is wrong',
            ),
        ];
        rig.upload.report = SyncReport(
          screenshots: 'none',
          characters: [
            _result(
              'eu-brumamar-nandu',
              status: SyncStatus.failed,
              error: UploadException(
                'invalid',
                'Rejected.',
                status: 422,
                problems: problems,
              ),
            ),
          ],
        );
        await rig.controller.uploadNow();
        final text = rig.controller.issues.single;
        expect(text, contains('Ñandú'));
        expect(text, contains('journey, line 1, field k: the value is wrong'));
        expect(text, contains('line 3'));
        expect(text, isNot(contains('line 4')));
        expect(text, contains('And 2 more problems.'));
      },
    );

    test('a failure that stops the run shows once', () async {
      final rig = await _rig(settings: _on);
      const stop = UploadException(
        'network',
        'Could not reach wowjourney.xyz. Check the internet connection and '
            'the website address.',
      );
      rig.upload.report = SyncReport(
        screenshots: 'none',
        characters: [
          for (final id in ['eu-brumamar-nandu', 'eu-los-errantes-nandu'])
            _result(id, status: SyncStatus.failed, error: stop),
        ],
      );
      await rig.controller.uploadNow();
      expect(rig.controller.issues, [stop.message]);
    });

    test('screenshot errors show with the character name', () async {
      final rig = await _rig(settings: _on);
      rig.upload.meInfo = const MeInfo(screenshots: 'approved', characters: []);
      rig.upload.report = SyncReport(
        screenshots: 'approved',
        characters: [
          _result(
            'eu-brumamar-nandu',
            shots: const ShotsResult(
              errors: ['a.jpg: The image is too large.'],
            ),
          ),
        ],
      );
      await rig.controller.uploadNow();
      expect(rig.controller.issues, ['Ñandú: a.jpg: The image is too large.']);
      expect(rig.controller.state, UploadState.failed);
      expect(rig.controller.screenshots, 'approved');
    });

    test(
      'an exception of the service becomes a message and never escapes',
      () async {
        final rig = await _rig(settings: _on);
        rig.upload.syncError = const UploadException(
          'no_index',
          'Could not read the index. Run the gather first, then try again.',
        );
        expect(await rig.controller.uploadNow(), isNull);
        expect(rig.controller.state, UploadState.failed);
        expect(rig.controller.issues, [
          'Could not read the index. Run the gather first, then try again.',
        ]);

        rig.upload.syncError = StateError('boom');
        await rig.controller.uploadNow();
        expect(rig.controller.issues, [genericFailureText]);
        expect(rig.controller.issues.single, isNot(contains('boom')));
      },
    );

    test('a revoked key says so and turns the switch off', () async {
      final rig = await _rig(settings: _on);
      rig.upload.syncError = const UploadException(
        'key_revoked',
        'Server text.',
        status: 403,
      );
      await rig.controller.uploadNow();
      expect(rig.controller.issues, [keyRevokedText(site)]);
      expect(rig.settingsController.settings.upload, isFalse);
      expect(rig.controller.state, UploadState.off);
      await pumpEventQueue();
      expect(rig.store.saved.last.upload, isFalse);
    });

    test('a key the website no longer knows shows Register again', () async {
      final rig = await _rig(settings: _on);
      rig.upload.syncError = const UploadException(
        'not_registered',
        'Server text.',
        status: 401,
      );
      await rig.controller.uploadNow();
      expect(rig.controller.registered, isFalse);
      expect(rig.controller.state, UploadState.unregistered);
    });
  });

  group('after a gather', () {
    test('uploads when the switch is on and the key is registered', () async {
      final rig = await _rig(settings: _on);
      await rig.gatherOnce();
      expect(rig.upload.syncs, [(site, '/backups/WoW Journey/latest')]);
      expect(rig.controller.state, UploadState.done);
    });

    test('never sends the removed characters again', () async {
      final rig = await _rig(settings: _on);
      await rig.gatherOnce();
      await rig.controller.uploadNow(resendRemoved: true);
      expect(rig.upload.resends, [false, true]);
    });

    test('does not upload when the switch is off', () async {
      final rig = await _rig();
      await rig.gatherOnce();
      expect(rig.upload.syncs, isEmpty);
    });

    test('does not upload when the key is not registered', () async {
      final rig = await _rig(settings: _on, registered: false);
      await rig.gatherOnce();
      expect(rig.upload.syncs, isEmpty);
    });

    test('does not upload after a gather that failed', () async {
      final rig = await _rig(settings: _on);
      rig.gatherService.next = (
        result: const GatherResult(
          issues: [GatherIssue(GatherIssueCode.noWtf, 'x', fatal: true)],
        ),
        snapshot: const BackupSnapshot(),
      );
      await rig.gatherOnce();
      expect(rig.gather.state, GatherState.failed);
      expect(rig.upload.syncs, isEmpty);
    });

    test('a gather while an upload runs waits for the next gather', () async {
      final rig = await _rig(settings: _on);
      rig.upload.pendingSync = Completer<SyncReport>();
      await rig.gatherOnce();
      expect(rig.controller.state, UploadState.uploading);
      await rig.gatherOnce();
      expect(rig.upload.syncs, hasLength(1));

      rig.upload.pendingSync!.complete(
        const SyncReport(screenshots: 'none', characters: []),
      );
      await pumpEventQueue();
      expect(rig.controller.state, UploadState.done);
      rig.upload.pendingSync = null;
      await rig.gatherOnce();
      expect(rig.upload.syncs, hasLength(2));
    });

    test('Upload now waits while a gather writes latest/', () async {
      final rig = await _rig(settings: _on);
      rig.gatherService.pending = Completer<GatherReport>();
      final run = rig.gather.gatherNow(
        flavorDir: retailDir,
        backupRoot: '/backups/WoW Journey',
      );
      await pumpEventQueue();
      expect(rig.gather.state, GatherState.running);
      expect(rig.controller.canUploadNow, isFalse);
      expect(await rig.controller.uploadNow(resendRemoved: true), isNull);
      expect(rig.upload.syncs, isEmpty);

      rig.gatherService.pending!.complete((
        result: const GatherResult(),
        snapshot: const BackupSnapshot(),
      ));
      await run;
      await pumpEventQueue();
      expect(rig.controller.canUploadNow, isTrue);
      expect(rig.upload.resends, [false]);
    });

    test('a new snapshot of the same gather does not upload again', () async {
      final rig = await _rig(settings: _on);
      await rig.gatherOnce();
      await rig.gather.refresh('/backups/WoW Journey');
      await pumpEventQueue();
      expect(rig.upload.syncs, hasLength(1));
    });
  });

  group('website', () {
    test('changeSite refuses an address the app does not accept', () async {
      final rig = await _rig();
      final message = rig.controller.changeSite('http://example.com');
      expect(message, contains('https://'));
      expect(rig.settingsController.settings.site, site);
      expect(rig.controller.changeSite('not a url'), isNotNull);
    });

    test('a new site starts unregistered with the switch off, and the old one is kept', () async {
      final rig = await _rig(settings: _on);
      expect(rig.controller.changeSite('http://localhost:8080/'), isNull);
      await pumpEventQueue();
      final s = rig.settingsController.settings;
      expect(s.site, otherSite);
      expect(s.upload, isFalse);
      expect(rig.controller.state, UploadState.unregistered);
      expect(rig.controller.characters, isEmpty);
      expect(rig.upload.registeredSites, {site});

      expect(rig.controller.changeSite(site), isNull);
      await pumpEventQueue();
      expect(rig.controller.state, UploadState.off);
    });

    test('the same address changes nothing', () async {
      final rig = await _rig();
      expect(rig.controller.changeSite('$site/'), isNull);
      expect(rig.store.saved, isEmpty);
    });

    test('checkSite keeps the name and the registration mode', () async {
      final rig = await _rig(registered: false);
      await rig.controller.checkSite();
      expect(rig.controller.siteInfo!.name, 'Journey Site');
      expect(rig.controller.siteError, isNull);
      expect(rig.upload.calls, ['info $site']);
    });

    test(
      'checkSite shows a plain message when the site is not reachable',
      () async {
        final rig = await _rig(registered: false);
        rig.upload.infoError = const UploadException(
          'network',
          'Could not reach wowjourney.xyz. Check the internet connection and '
              'the website address.',
        );
        await rig.controller.checkSite();
        expect(rig.controller.siteInfo, isNull);
        expect(rig.controller.siteError, startsWith('Could not reach'));
      },
    );

    test(
      'checkSite rejects an answer that is not from a Memories website',
      () async {
        final rig = await _rig(registered: false);
        rig.upload.siteInfo = const SiteInfo(
          api: 2,
          name: 'x',
          registration: 'open',
        );
        await rig.controller.checkSite();
        expect(rig.controller.siteError, notAMemoriesSiteText);
      },
    );
  });

  group('register', () {
    test('registers with the trimmed code and reads the characters', () async {
      final rig = await _rig(registered: false);
      rig.upload.meInfo = const MeInfo(
        screenshots: 'none',
        characters: [nandu],
      );
      expect(await rig.controller.register('  ABCD  '), isTrue);
      expect(rig.upload.registrations, [(site, 'ABCD')]);
      expect(rig.controller.registered, isTrue);
      expect(rig.controller.fingerprint, isNotNull);
      expect(rig.controller.characters, [nandu]);
      expect(rig.controller.state, UploadState.off);
      expect(rig.controller.registerError, isNull);
    });

    test('a refused code shows the message of the website', () async {
      final rig = await _rig(registered: false);
      rig.upload.registerError = const UploadException(
        'invite_invalid',
        'This invite code is not valid. Ask the website admin for a new one.',
        status: 403,
      );
      expect(await rig.controller.register('nope'), isFalse);
      expect(rig.controller.registered, isFalse);
      expect(
        rig.controller.registerError,
        'This invite code is not valid. Ask the website admin for a new one.',
      );
    });

    test('a revoked key says so', () async {
      final rig = await _rig(registered: false);
      rig.upload.registerError = const UploadException(
        'key_revoked',
        'Server text.',
        status: 403,
      );
      expect(await rig.controller.register(null), isFalse);
      expect(rig.controller.registerError, keyRevokedText(site));
    });
  });

  group('characters and screenshots', () {
    test('removeCharacter deletes and reads the website again', () async {
      final rig = _Rig();
      addTearDown(rig.dispose);
      rig.upload.meInfo = const MeInfo(
        screenshots: 'none',
        characters: [nandu],
      );
      await rig.load();
      expect(await rig.controller.removeCharacter(nandu.path), isTrue);
      expect(rig.upload.deletions, [(site, nandu.path)]);
      expect(rig.controller.characters, isEmpty);
    });

    test('a character that is already gone counts as removed', () async {
      final rig = await _rig();
      rig.upload.deleteError = const UploadException(
        'not_found',
        'Not found.',
        status: 404,
      );
      expect(await rig.controller.removeCharacter(nandu.path), isTrue);
      expect(rig.controller.issues, isEmpty);
    });

    test('a failed removal shows a message and keeps the character', () async {
      final rig = _Rig();
      addTearDown(rig.dispose);
      rig.upload.meInfo = const MeInfo(
        screenshots: 'none',
        characters: [nandu],
      );
      await rig.load();
      rig.upload.deleteError = const UploadException(
        'network',
        'Could not reach wowjourney.xyz. Check the internet connection and '
            'the website address.',
      );
      expect(await rig.controller.removeCharacter(nandu.path), isFalse);
      expect(rig.controller.issues.single, startsWith('Could not reach'));
      expect(rig.controller.characters, [nandu]);
    });

    test('a removal while an upload runs says to wait', () async {
      final rig = await _rig(settings: _on);
      rig.upload.pendingSync = Completer<SyncReport>();
      unawaited(rig.controller.uploadNow());
      await pumpEventQueue();
      expect(await rig.controller.removeCharacter(nandu.path), isFalse);
      expect(rig.controller.issues, [busyText]);
      expect(rig.upload.deletions, isEmpty);
      rig.upload.pendingSync!.complete(
        const SyncReport(screenshots: 'none', characters: []),
      );
      await pumpEventQueue();
    });

    test('a removal whose local record failed still counts as gone', () async {
      final rig = await _rig();
      rig.upload.deleteError = const UploadException('bad_state', 'Not saved.');
      expect(await rig.controller.removeCharacter(nandu.path), isTrue);
      expect(rig.controller.issues, ['Not saved.']);
      expect(rig.upload.calls.last, 'me $site');
    });

    test('a failed reload after an upload keeps its messages', () async {
      final rig = await _rig(settings: _on);
      rig.upload.report = SyncReport(
        screenshots: 'none',
        characters: [
          _result(
            'eu-brumamar-nandu',
            status: SyncStatus.failed,
            error: const UploadException('claimed', 'Taken.', status: 409),
          ),
        ],
      );
      rig.upload.meError = const UploadException('network', 'No network.');
      await rig.gatherOnce();
      expect(rig.controller.issues, [
        claimedText('Ñandú', 'Brumamar'),
        'No network.',
      ]);
    });

    test('removing works with the switch off', () async {
      final rig = await _rig();
      expect(rig.settingsController.settings.upload, isFalse);
      expect(await rig.controller.removeCharacter(nandu.path), isTrue);
    });

    test('requestScreenshots moves none to pending, then waits', () async {
      final rig = await _rig();
      expect(rig.controller.canRequestScreenshots, isTrue);
      expect(await rig.controller.requestScreenshots(), isTrue);
      expect(rig.controller.screenshots, 'pending');
      expect(rig.controller.canRequestScreenshots, isFalse);
      expect(await rig.controller.requestScreenshots(), isFalse);
      expect(
        rig.upload.calls.where((c) => c.startsWith('requestScreenshots')),
        hasLength(1),
      );
    });

    test('a denied key can ask again, an approved one cannot', () async {
      final rig = _Rig();
      addTearDown(rig.dispose);
      rig.upload.meInfo = const MeInfo(screenshots: 'denied', characters: []);
      await rig.load();
      expect(rig.controller.canRequestScreenshots, isTrue);
      rig.upload.meInfo = const MeInfo(screenshots: 'approved', characters: []);
      await rig.controller.refresh();
      expect(rig.controller.canRequestScreenshots, isFalse);
    });

    test('a failed request shows a message', () async {
      final rig = await _rig();
      rig.upload.requestError = const UploadException(
        'network',
        'Could not reach wowjourney.xyz. Check the internet connection and '
            'the website address.',
      );
      expect(await rig.controller.requestScreenshots(), isFalse);
      expect(rig.controller.issues.single, startsWith('Could not reach'));
    });
  });

  test('a revoked key found when reading me turns the switch off', () async {
    final rig = _Rig(settings: _on);
    addTearDown(rig.dispose);
    rig.upload.meError = const UploadException(
      'key_revoked',
      'Server text.',
      status: 403,
    );
    await rig.load();
    expect(rig.controller.issues, [keyRevokedText(site)]);
    expect(rig.settingsController.settings.upload, isFalse);
  });
}
