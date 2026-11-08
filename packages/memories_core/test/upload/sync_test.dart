import 'dart:io';

import 'package:memories_core/memories_core.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/fixture.dart';
import 'fake_site.dart';

const String _brumamar = 'wow/eu/brumamar/nandu';
const String _errantes = 'wow/eu/los-errantes/nandu';

void main() {
  late FakeSite site;
  late UploadClient client;
  late UploadState state;
  late Directory tmp;
  late Directory latest;

  setUp(() async {
    site = await FakeSite.start();
    client = UploadClient(site.uri, UploadKey.generate());
    state = UploadState.empty();
    tmp = Directory.systemTemp.createTempSync('memories-sync-');
    latest = Directory(p.join(tmp.path, 'latest'));
    copyTree(expectedDir, latest.path);
    await client.register();
  });
  tearDown(() async {
    client.close();
    await site.close();
    tmp.deleteSync(recursive: true);
  });

  Map<String, SyncStatus> statuses(SyncReport r) => {
    for (final c in r.characters) c.path: c.status,
  };

  test(
    'uploads each character, then skips them while nothing changes',
    () async {
      final first = await syncLatest(latest, client, state);
      expect(statuses(first), {
        _brumamar: SyncStatus.uploaded,
        _errantes: SyncStatus.uploaded,
      });
      expect(first.failed, isFalse);
      expect(first.screenshots, 'none');
      expect(first.characters.first.outcome!.added, 15);
      expect(state.site(site.uri).sent.keys, [_brumamar, _errantes]);
      expect(site.callsTo('POST /api/v1/characters'), hasLength(2));

      final second = await syncLatest(latest, client, state);
      expect(statuses(second), {
        _brumamar: SyncStatus.unchanged,
        _errantes: SyncStatus.unchanged,
      });
      expect(site.callsTo('POST /api/v1/characters'), hasLength(2));
    },
  );

  test('a changed character goes out again, the other stays', () async {
    await syncLatest(latest, client, state);
    final journey = File(
      p.join(latest.path, 'eu-los-errantes-nandu', 'journey.jsonl'),
    );
    journey.writeAsStringSync(
      '${journey.readAsStringSync()}{"addon":"Memories","k":"in","m":1,"p":null,"session":1,"t":1793539999,"x":1,"y":1}\n',
    );
    final r = await syncLatest(latest, client, state);
    expect(statuses(r), {
      _brumamar: SyncStatus.unchanged,
      _errantes: SyncStatus.uploaded,
    });
    expect(r.characters.last.outcome!.added, 1);
  });

  test(
    'a failure of one character does not stop the others, and resumes',
    () async {
      site.overrides['POST /api/v1/characters'] = Reply.error(
        429,
        'rate_limited',
        'Wait 3 seconds.',
      );
      final failed = await syncLatest(latest, client, state);
      expect(failed.failed, isTrue);
      expect(failed.characters.map((c) => c.error?.code), [
        'rate_limited',
        'rate_limited',
      ]);
      expect(site.callsTo('POST /api/v1/characters'), hasLength(1));
      expect(state.site(site.uri).sent, isEmpty);
      site.overrides.clear();

      File(p.join(latest.path, 'eu-brumamar-nandu', 'journey.jsonl'))
          .writeAsStringSync('{broken\n');
      final partial = await syncLatest(latest, client, state);
      expect(statuses(partial), {
        '': SyncStatus.failed,
        _errantes: SyncStatus.uploaded,
      });
      expect(partial.characters.first.id, 'eu-brumamar-nandu');
      expect(partial.characters.first.error!.code, 'bad_files');
      expect(partial.failed, isTrue);
    },
  );

  test('screenshots stay home until the key is approved', () async {
    final r = await syncLatest(latest, client, state);
    expect(r.screenshots, 'none');
    expect(site.callsTo('POST /api/v1/characters'), hasLength(2));
    expect(site.calls.where((c) => c.method == 'PUT'), isEmpty);
  });

  test(
    'an approval sends the characters again, then each screenshot once',
    () async {
      await syncLatest(latest, client, state);
      site.screenshots = 'approved';

      final r = await syncLatest(latest, client, state);
      expect(r.screenshots, 'approved');
      expect(statuses(r)[_brumamar], SyncStatus.uploaded);
      expect(r.characters.first.shots.uploaded, 2);
      expect(r.characters.first.shots.errors, isEmpty);
      expect(site.shotFiles[_brumamar], [
        'WoWScrnShot_110126_114820.jpg',
        'WoWScrnShot_110126_115001.jpg',
      ]);
      expect(site.calls.where((c) => c.method == 'PUT'), hasLength(2));

      final again = await syncLatest(latest, client, state);
      expect(statuses(again)[_brumamar], SyncStatus.unchanged);
      expect(again.characters.first.shots.unchanged, 2);
      expect(again.characters.first.shots.uploaded, 0);
      expect(site.calls.where((c) => c.method == 'PUT'), hasLength(2));
    },
  );

  test('an approval after a revocation sends the screenshots again', () async {
    site.screenshots = 'approved';
    await syncLatest(latest, client, state);
    site.screenshots = 'denied';
    await syncLatest(latest, client, state);
    site.screenshots = 'approved';
    final r = await syncLatest(latest, client, state);
    expect(r.characters.first.shots.uploaded, 2);
    expect(site.calls.where((c) => c.method == 'PUT'), hasLength(4));
  });

  test('a changed screenshot file is sent again', () async {
    site.screenshots = 'approved';
    await syncLatest(latest, client, state);
    File(
      p.join(
        latest.path,
        'eu-brumamar-nandu',
        'screenshots',
        'WoWScrnShot_110126_114820.jpg',
      ),
    ).writeAsBytesSync([1, 2, 3]);
    final r = await syncLatest(latest, client, state);
    expect(r.characters.first.shots.uploaded, 1);
    expect(r.characters.first.shots.unchanged, 1);
  });

  test('a missing screenshots folder or file is reported, not fatal', () async {
    site.screenshots = 'approved';
    Directory(p.join(latest.path, 'eu-brumamar-nandu', 'screenshots'))
        .deleteSync(recursive: true);
    final r = await syncLatest(latest, client, state);
    final c = r.characters.first;
    expect(c.status, SyncStatus.uploaded);
    expect(c.shots.errors, hasLength(2));
    expect(c.shots.errors.first, contains('is missing'));
    expect(r.failed, isTrue);
    expect(r.characters.last.status, SyncStatus.uploaded);
  });

  test('a failure of the website stops the screenshots of that character', () async {
    site.screenshots = 'approved';
    site.overrides['PUT /api/v1/characters/$_brumamar/screenshots/WoWScrnShot_110126_114820.jpg'] =
        Reply.error(507, 'quota', 'No more room.');
    final r = await syncLatest(latest, client, state);
    expect(r.characters.first.shots.errors, [
      'WoWScrnShot_110126_114820.jpg: No more room.',
    ]);
  });

  test('a rate limit on a screenshot stops the characters after it', () async {
    site.screenshots = 'approved';
    site.overrides['PUT /api/v1/characters/$_brumamar/screenshots/WoWScrnShot_110126_114820.jpg'] =
        Reply.error(429, 'rate_limited', 'Too many requests.');
    final r = await syncLatest(latest, client, state);
    expect(r.characters.last.status, SyncStatus.failed);
    expect(r.characters.last.error!.status, 429);
    expect(site.callsTo('POST /api/v1/characters'), hasLength(1));
  });

  test('a failure of one screenshot does not stop the next one', () async {
    site.screenshots = 'approved';
    site.overrides['PUT /api/v1/characters/$_brumamar/screenshots/WoWScrnShot_110126_114820.jpg'] =
        Reply.error(415, 'unsupported_image', 'Not an image.');
    final r = await syncLatest(latest, client, state);
    expect(r.characters.first.shots.errors, hasLength(1));
    expect(r.characters.first.shots.uploaded, 1);
  });

  test(
    'a file that cannot be read is reported',
    () async {
      site.screenshots = 'approved';
      final shot = File(
        p.join(
          latest.path,
          'eu-brumamar-nandu',
          'screenshots',
          'WoWScrnShot_110126_114820.jpg',
        ),
      );
      Process.runSync('chmod', ['000', shot.path]);
      addTearDown(() => Process.runSync('chmod', ['600', shot.path]));
      final r = await syncLatest(latest, client, state);
      expect(
        r.characters.first.shots.errors.first,
        contains('WoWScrnShot_110126_114820.jpg'),
      );
    },
    skip: Platform.isWindows || Platform.environment['USER'] == 'root'
        ? 'needs a POSIX user that is not root'
        : false,
  );

  test('a missing or damaged index is a no_index error', () async {
    final index = File(p.join(latest.path, 'index.json'));
    for (final text in [null, 'nope', '{}', '[]']) {
      if (text == null) {
        index.deleteSync();
      } else {
        index.writeAsStringSync(text);
      }
      await expectLater(
        syncLatest(latest, client, state),
        throwsA(
          isA<UploadException>()
              .having((e) => e.code, 'code', 'no_index')
              .having((e) => e.message, 'message', contains('Run the gather')),
        ),
        reason: '$text',
      );
    }
  });

  test('a failed me() ends the run before any upload', () async {
    site.overrides['GET /api/v1/me'] = Reply.error(
      401,
      'bad_signature',
      'Clock.',
    );
    await expectLater(
      syncLatest(latest, client, state),
      throwsA(
        isA<UploadException>().having((e) => e.code, 'code', 'bad_signature'),
      ),
    );
    expect(site.callsTo('POST /api/v1/characters'), isEmpty);
  });

  test('one site never uses the state of another', () async {
    await syncLatest(latest, client, state);
    final other = await FakeSite.start();
    addTearDown(other.close);
    final key = UploadKey.generate();
    final otherClient = UploadClient(other.uri, key);
    addTearDown(otherClient.close);
    await otherClient.register();
    final r = await syncLatest(latest, otherClient, state);
    expect(statuses(r).values, everyElement(SyncStatus.uploaded));
  });

  test('an index entry with an unsafe path is ignored', () async {
    File(p.join(latest.path, 'index.json')).writeAsStringSync(
      '{"characters":[{"path":"../x"},{"path":3},"x",{"path":"eu-los-errantes-nandu"}]}',
    );
    final r = await syncLatest(latest, client, state);
    expect(r.characters.map((c) => c.id), ['eu-los-errantes-nandu']);
  });

  test('a character that the website lost goes out again', () async {
    await syncLatest(latest, client, state);
    site.characters.remove(_errantes);
    final r = await syncLatest(latest, client, state);
    expect(statuses(r), {
      _brumamar: SyncStatus.unchanged,
      _errantes: SyncStatus.uploaded,
    });
    expect(site.callsTo('POST /api/v1/characters'), hasLength(3));
  });

  test(
    'a removed character is skipped, even when the website lost it',
    () async {
      await syncLatest(latest, client, state);
      site.characters.remove(_errantes);
      state.site(site.uri).markRemoved(_errantes);
      final r = await syncLatest(latest, client, state);
      expect(statuses(r), {
        _brumamar: SyncStatus.unchanged,
        _errantes: SyncStatus.removed,
      });
      expect(r.failed, isFalse);
      expect(site.characters.containsKey(_errantes), isFalse);
      expect(site.callsTo('POST /api/v1/characters'), hasLength(2));
      expect(state.site(site.uri).removed, {_errantes});
    },
  );

  test('a removed character skips its screenshots too', () async {
    site.screenshots = 'approved';
    state.site(site.uri).markRemoved(_brumamar);
    final r = await syncLatest(latest, client, state);
    expect(statuses(r)[_brumamar], SyncStatus.removed);
    expect(r.characters.first.shots.uploaded, 0);
    expect(site.calls.where((c) => c.method == 'PUT'), isEmpty);
  });

  test('resendRemoved sends removed characters and clears the set', () async {
    state.site(site.uri).markRemoved(_errantes);
    final r = await syncLatest(latest, client, state, resendRemoved: true);
    expect(statuses(r), {
      _brumamar: SyncStatus.uploaded,
      _errantes: SyncStatus.uploaded,
    });
    expect(state.site(site.uri).removed, isEmpty);
    final again = await syncLatest(latest, client, state);
    expect(statuses(again)[_errantes], SyncStatus.unchanged);
  });

  test('a failed me() keeps the removed set', () async {
    state.site(site.uri).markRemoved(_errantes);
    site.overrides['GET /api/v1/me'] = Reply.error(503, 'busy', 'Busy.');
    await expectLater(
      syncLatest(latest, client, state, resendRemoved: true),
      throwsA(isA<UploadException>()),
    );
    expect(state.site(site.uri).removed, {_errantes});
  });

  test('the removed set of one site never skips on another', () async {
    state.site(Uri.parse('https://other.example')).markRemoved(_errantes);
    final r = await syncLatest(latest, client, state);
    expect(statuses(r)[_errantes], SyncStatus.uploaded);
  });
}
