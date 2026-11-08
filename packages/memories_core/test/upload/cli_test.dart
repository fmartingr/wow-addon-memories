import 'dart:convert';
import 'dart:io';

import 'package:memories_core/memories_core.dart';
import 'package:memories_core/src/upload/cli.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/fixture.dart';
import 'fake_site.dart';

typedef Result = ({int code, String out, String err});

void main() {
  late FakeSite site;
  late Directory tmp;
  late String keyPath;
  late String statePath;
  late String latest;

  setUp(() async {
    site = await FakeSite.start();
    tmp = Directory.systemTemp.createTempSync('memories-upload-cli-');
    keyPath = p.join(tmp.path, 'key.json');
    statePath = p.join(tmp.path, 'state.json');
    latest = p.join(tmp.path, 'latest');
    copyTree(expectedDir, latest);
  });
  tearDown(() async {
    await site.close();
    tmp.deleteSync(recursive: true);
  });

  Future<Result> run(List<String> args, {bool withSite = true}) async {
    final out = StringBuffer();
    final err = StringBuffer();
    final code = await runMemoriesUpload(
      [
        if (withSite) ...['--site', site.uri.toString()],
        '--key',
        keyPath,
        '--state',
        statePath,
        ...args,
      ],
      out: out,
      err: err,
    );
    return (code: code, out: out.toString(), err: err.toString());
  }

  Future<Result> raw(List<String> args) async {
    final out = StringBuffer();
    final err = StringBuffer();
    final code = await runMemoriesUpload(args, out: out, err: err);
    return (code: code, out: out.toString(), err: err.toString());
  }

  group('usage errors', () {
    test('exit code 2 with the fixed flag messages', () async {
      final cases = [
        ('no arguments', <String>[], 'usage:'),
        ('unknown flag', ['--nope'], 'flag provided but not defined: -nope'),
        ('missing value', ['--site'], 'flag needs an argument: -site'),
        ('extra argument', ['--site', 'https://a.example', 'x'], 'usage:'),
        ('empty key', ['--site', 'https://a.example', '--key', ''], 'usage:'),
        (
          'plain http on another host',
          ['--site', 'http://example.com'],
          'must start with https://',
        ),
        ('no host', ['--site', 'example'], 'usage:'),
        (
          'bad delete path',
          ['--site', 'https://a.example', '--delete', 'wow/eu'],
          '--delete needs a character path',
        ),
      ];
      for (final (name, args, want) in cases) {
        final r = await raw(args);
        expect(r.code, 2, reason: name);
        expect(r.err, contains(want), reason: name);
        expect(r.out, isEmpty, reason: name);
      }
      expect(site.calls, isEmpty);
      expect(File(keyPath).existsSync(), isFalse);
    });

    test('help exits 0 and the single-dash form works', () async {
      final r = await raw(['-h']);
      expect(r.code, 0);
      expect(r.err, contains('-request-screenshots'));
      final dash = await raw([
        '-site',
        site.uri.toString(),
        '-key',
        keyPath,
        '-state=$statePath',
      ]);
      expect(dash.code, 0, reason: dash.err);
    });
  });

  test('the first run makes the key, registers and saves the state', () async {
    final r = await run([]);
    expect(r.code, 0, reason: r.err);
    expect(r.out, contains('Made a new key'));
    expect(r.out, contains('Registered this key'));
    final key = UploadKey.load(File(keyPath));
    expect(r.out, contains(key.fingerprint));
    expect(site.registered, contains(key.publicKey));
    final state = UploadState.load(File(statePath));
    expect(state.site(site.uri).registered, isTrue);

    final again = await run([]);
    expect(again.code, 0);
    expect(again.out, isEmpty);
    expect(site.callsTo('POST /api/v1/register'), hasLength(1));
  });

  test('an invite registers the key even when the state says so', () async {
    site.invite = 'CODE';
    final bad = await run(['--invite', 'WRONG']);
    expect(bad.code, 1);
    expect(bad.err, contains('invite code is not valid'));
    expect(
      UploadState.load(File(statePath)).site(site.uri).registered,
      isFalse,
    );

    final ok = await run(['--invite', 'CODE']);
    expect(ok.code, 0, reason: ok.err);
    final again = await run(['--invite', 'CODE']);
    expect(again.out, contains('already registered'));
  });

  test('uploads the latest folder, then reports it unchanged', () async {
    final first = await run(['--latest', latest]);
    expect(first.code, 0, reason: first.err);
    expect(
      first.out,
      contains('uploaded wow/eu/brumamar/nandu: 15 steps, 15 new.'),
    );
    expect(first.out, contains('${site.uri}/wow/eu/brumamar/nandu/'));
    expect(first.out, contains('uploaded wow/eu/los-errantes/nandu: 1 steps'));
    expect(first.out, contains('Screenshots were not uploaded'));
    expect(first.out, contains('2 uploaded, 0 unchanged, 0 failed'));

    final second = await run(['--latest', latest]);
    expect(second.code, 0);
    expect(second.out, contains('unchanged wow/eu/brumamar/nandu'));
    expect(second.out, contains('0 uploaded, 2 unchanged'));
    expect(site.callsTo('POST /api/v1/characters'), hasLength(2));
  });

  test('request screenshots, approval, then the screenshots go up', () async {
    await run(['--latest', latest]);
    final req = await run(['--request-screenshots']);
    expect(req.code, 0, reason: req.err);
    expect(req.out, contains('Screenshot state of this key: pending.'));

    site.screenshots = 'approved';
    final r = await run(['--latest', latest]);
    expect(r.code, 0, reason: r.err);
    expect(r.out, contains('screenshots wow/eu/brumamar/nandu: 2 uploaded'));
    expect(r.out, isNot(contains('were not uploaded')));
    expect(site.shotFiles[_path], hasLength(2));
  });

  test('delete removes the character and forgets it', () async {
    await run(['--latest', latest]);
    final r = await run(['--delete', _path]);
    expect(r.code, 0, reason: r.err);
    expect(r.out, contains('Removed $_path'));
    expect(UploadState.load(File(statePath)).site(site.uri).sent.keys, [
      'wow/eu/los-errantes/nandu',
    ]);
    final again = await run(['--latest', latest]);
    expect(again.out, contains('uploaded $_path'));
    expect(again.out, contains('unchanged wow/eu/los-errantes/nandu'));
  });

  test('actions run in the order register, latest, delete, request', () async {
    final r = await run([
      '--request-screenshots',
      '--delete',
      _path,
      '--latest',
      latest,
    ]);
    expect(r.code, 0, reason: r.err);
    expect(site.calls.map((c) => c.method).toList(), [
      'POST',
      'GET',
      'POST',
      'POST',
      'DELETE',
      'POST',
    ]);
    expect(site.calls.map((c) => c.path), [
      '/api/v1/register',
      '/api/v1/me',
      '/api/v1/characters',
      '/api/v1/characters',
      '/api/v1/characters/$_path',
      '/api/v1/screenshots/request',
    ]);
  });

  group('failures exit 1 and print the plain message', () {
    test('a 422 prints each problem', () async {
      site.overrides['POST /api/v1/characters'] = Reply.error(
        422,
        'invalid',
        'The upload has data that this website does not accept.',
        problems: [
          {
            'file': 'journey',
            'line': 4,
            'field': 'zone',
            'reason': 'is too long',
          },
        ],
      );
      final r = await run(['--latest', latest]);
      expect(r.code, 1);
      expect(r.err, contains('failed wow/eu/brumamar/nandu:'));
      expect(r.err, contains('does not accept'));
      expect(r.err, contains('  journey, line 4, field zone: is too long'));
      expect(r.out, contains('0 uploaded, 0 unchanged, 2 failed'));
    });

    test('a 409 is printed, and the other character still goes up', () async {
      site.overrides['POST /api/v1/characters'] = Reply.error(
        409,
        'claimed',
        'Another key already owns this web address.',
      );
      final r = await run(['--latest', latest]);
      expect(r.code, 1);
      expect(r.err, contains('Another key already owns'));
    });

    test('a 429 prints Retry-After', () async {
      site.overrides['POST /api/v1/register'] = const Reply(
        429,
        '{"error":"rate_limited","message":"Too many requests. Wait 30 seconds."}',
        {'Retry-After': '30'},
      );
      final r = await run([]);
      expect(r.code, 1);
      expect(r.err, contains('Too many requests'));
      expect(r.err, contains('Retry-After: 30 seconds.'));
    });

    test('a wrong clock prints the message of the server', () async {
      site.overrides['GET /api/v1/me'] = Reply.error(
        401,
        'bad_signature',
        'The time of your computer is off. Check the computer clock.',
      );
      final r = await run(['--latest', latest]);
      expect(r.code, 1);
      expect(r.err, contains('Check the computer clock.'));
    });

    test('a missing latest/index.json', () async {
      final r = await run(['--latest', p.join(tmp.path, 'none')]);
      expect(r.code, 1);
      expect(r.err, contains('Run the gather first'));
    });

    test('a site that is down', () async {
      final url = site.uri.toString();
      await site.close();
      final out = StringBuffer();
      final err = StringBuffer();
      final code = await runMemoriesUpload(
        ['--site', url, '--key', keyPath, '--state', statePath],
        out: out,
        err: err,
      );
      expect(code, 1);
      expect(err.toString(), contains('Could not reach 127.0.0.1.'));
      site = await FakeSite.start();
    });

    test('a delete of an unknown character', () async {
      final r = await run(['--delete', _path]);
      expect(r.code, 1);
      expect(r.err, contains('No such character'));
    });

    test('a key that the server forgot is registered again', () async {
      await run([]);
      site.registered.clear();
      final r = await run(['--latest', latest]);
      expect(r.code, 1);
      expect(r.err, contains('not registered'));
      expect(
        UploadState.load(File(statePath)).site(site.uri).registered,
        isFalse,
      );
      final fixed = await run(['--latest', latest]);
      expect(fixed.code, 0, reason: fixed.err);
    });

    test(
      'a rate limit on a screenshot prints Retry-After once and stops the run',
      () async {
        await run([]);
        site.screenshots = 'approved';
        site.overrides['PUT /api/v1/characters/$_path/screenshots/'
            'WoWScrnShot_110126_114820.jpg'] = const Reply(
          429,
          '{"error":"rate_limited","message":"Too many requests."}',
          {'Retry-After': '30'},
        );
        final r = await run(['--latest', latest]);
        expect(r.code, 1);
        expect('Retry-After: 30 seconds.'.allMatches(r.err), hasLength(1));
        expect(r.err, contains('the run stopped at the error above'));
      },
    );

    test(
      'a key forgot during the upload is registered on the next run, and the '
      'error prints once',
      () async {
        await run([]);
        site.overrides['POST /api/v1/characters'] = Reply.error(
          401,
          'not_registered',
          'This key is not registered.',
        );
        final r = await run(['--latest', latest]);
        expect(r.code, 1);
        expect('not registered'.allMatches(r.err), hasLength(1));
        expect(r.err, contains('the run stopped at the error above'));
        expect(
          UploadState.load(File(statePath)).site(site.uri).registered,
          isFalse,
        );
      },
    );
  });

  test('a damaged key file ends the run and is never overwritten', () async {
    File(keyPath).writeAsStringSync('garbage');
    final r = await run([]);
    expect(r.code, 1);
    expect(r.err, contains('is damaged'));
    expect(File(keyPath).readAsStringSync(), 'garbage');
    expect(site.calls, isEmpty);
  });

  test('a key path that cannot be written ends the run', () async {
    keyPath = p.join(tmp.path, 'a-file', 'key.json');
    File(p.join(tmp.path, 'a-file')).writeAsStringSync('x');
    final r = await run([]);
    expect(r.code, 1);
    expect(r.err, contains('could not read or write the key file'));
  });

  test('a damaged state file starts fresh with a warning', () async {
    File(statePath).writeAsStringSync('garbage');
    final r = await run(['--latest', latest]);
    expect(r.code, 0, reason: r.err);
    expect(r.err, contains('warning'));
    expect(r.err, contains('damaged'));
    expect((jsonDecode(File(statePath).readAsStringSync()) as Map)['v'], 1);
  });

  test('a state path that cannot be written is an error', () async {
    statePath = p.join(tmp.path, 'a-file', 'state.json');
    File(p.join(tmp.path, 'a-file')).writeAsStringSync('x');
    final r = await run([]);
    expect(r.code, 1);
    expect(r.err, contains('state file'));
  });
}

const String _path = 'wow/eu/brumamar/nandu';
