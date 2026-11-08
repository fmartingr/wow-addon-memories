import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:memories_core/memories_core.dart';
import 'package:memories_core/src/upload/key.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/fixture.dart';
import 'fake_site.dart';

final DateTime _now = DateTime.utc(2026, 11, 8, 12);

Matcher _fails(String code, {int? status}) => throwsA(
  isA<UploadException>()
      .having((e) => e.code, 'code', code)
      .having((e) => e.status, 'status', status ?? anything),
);

void main() {
  late FakeSite site;
  late UploadKey key;
  late UploadClient client;

  setUp(() async {
    site = await FakeSite.start();
    key = UploadKey.generate();
    client = UploadClient(
      site.uri,
      key,
      clock: () => _now,
      retryBudget: Duration.zero,
    );
  });
  tearDown(() async {
    client.close();
    await site.close();
  });

  test('info is not signed', () async {
    final info = await client.info();
    expect(info.api, 1);
    expect(info.name, 'Fake site');
    expect(info.registration, 'open');
    expect(site.calls.single.headers, isNot(contains('memories-key')));
  });

  test('every signed request carries the 4 headers of the protocol', () async {
    await client.register();
    await client.me();
    expect(site.calls, hasLength(2));
    for (final c in site.calls) {
      expect(c.headers['memories-key'], key.publicKey);
      expect(
        c.headers['memories-time'],
        '${_now.millisecondsSinceEpoch ~/ 1000}',
      );
      expect(unb64(c.headers['memories-nonce']!), hasLength(16));
      expect(unb64(c.headers['memories-signature']!), hasLength(64));
    }
    expect(
      site.calls[0].headers['memories-nonce'],
      isNot(site.calls[1].headers['memories-nonce']),
    );
  });

  test('register sends the invite and tells new from known keys', () async {
    site.invite = 'CODE';
    await expectLater(client.register(), _fails('invite_invalid', status: 403));
    await expectLater(
      client.register(invite: 'WRONG'),
      _fails('invite_invalid'),
    );
    expect(await client.register(invite: 'CODE'), isTrue);
    expect((site.calls.last.json as Map)['invite'], 'CODE');
    expect(await client.register(invite: 'CODE'), isFalse);
    expect(site.calls.first.json, <String, Object?>{});
  });

  test('me, requestScreenshots, upload and delete', () async {
    await expectLater(client.me(), _fails('not_registered', status: 401));
    await client.register();
    final dir = Directory('$expectedDir/eu-brumamar-nandu');
    final out = await client.uploadCharacter(dir);
    expect(out.path, 'wow/eu/brumamar/nandu');
    expect(out.url, '${site.uri}/wow/eu/brumamar/nandu/');
    expect(out.steps, 15);
    expect(out.added, 15);

    final upload = site.callsTo('POST /api/v1/characters').single;
    expect(upload.headers['content-encoding'], 'gzip');
    expect(upload.headers['content-type'], 'application/json');
    expect(upload.uploadJson.keys, ['character', 'journey', 'trail']);

    final me = await client.me();
    expect(me.screenshots, 'none');
    expect(me.screenshotsApproved, isFalse);
    expect(me.characters.single.path, 'wow/eu/brumamar/nandu');
    expect(me.characters.single.guid, 'Player-1234-0ABCDEF0');
    expect(me.characters.single.steps, 3);

    expect(await client.requestScreenshots(), 'pending');

    await client.deleteCharacter('wow/eu/brumamar/nandu');
    await expectLater(
      client.deleteCharacter('wow/eu/brumamar/nandu'),
      _fails('not_found', status: 404),
    );
    expect(site.characters, isEmpty);
  });

  test('uploadScreenshot sends the raw bytes and tells new from same', () async {
    await client.register();
    site.screenshots = 'approved';
    final file = File(
      '$expectedDir/eu-brumamar-nandu/screenshots/WoWScrnShot_110126_114820.jpg',
    );
    expect(
      await client.uploadScreenshot('wow/eu/brumamar/nandu', file),
      isTrue,
    );
    expect(
      await client.uploadScreenshot('wow/eu/brumamar/nandu', file),
      isFalse,
    );
    final put = site.calls.last;
    expect(
      put.path,
      '/api/v1/characters/wow/eu/brumamar/nandu/screenshots/WoWScrnShot_110126_114820.jpg',
    );
    expect(sha256.convert(put.body), sha256.convert(file.readAsBytesSync()));

    site.screenshots = 'none';
    await expectLater(
      client.uploadScreenshot('wow/eu/brumamar/nandu', file),
      _fails('screenshots_not_approved', status: 403),
    );
    await expectLater(
      client.uploadScreenshot('wow/eu/brumamar/nandu', File('missing.jpg')),
      _fails('bad_files'),
    );
  });

  test('the signature covers the path as sent, percent-encoded', () async {
    await client.register();
    site.screenshots = 'approved';
    final tmp = Directory.systemTemp.createTempSync('memories-shot-');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final file = File(p.join(tmp.path, 'a b.jpg'))..writeAsBytesSync([1, 2]);
    expect(await client.uploadScreenshot('wow/eu/r/n', file), isTrue);
    expect(
      site.calls.last.path,
      '/api/v1/characters/wow/eu/r/n/screenshots/a%20b.jpg',
    );
  });

  test(
    'a path that is not a character path is refused before any call',
    () async {
      final file = File('x.jpg');
      for (final bad in [
        '',
        'wow/eu/r',
        'wow/eu/r/n/x',
        'wow/EU/r/n',
        '../a/b/c',
      ]) {
        await expectLater(client.deleteCharacter(bad), throwsArgumentError);
        await expectLater(
          client.uploadScreenshot(bad, file),
          throwsArgumentError,
        );
      }
      expect(site.calls, isEmpty);
    },
  );

  group('error mapping', () {
    Future<void> register() => client.register();

    test('a 422 keeps the problems', () async {
      site.overrides['POST /api/v1/register'] = Reply.error(
        422,
        'invalid',
        'The upload has data that this website does not accept.',
        problems: [
          {'file': 'journey', 'line': 3, 'field': 'x', 'reason': 'is too big'},
          {'file': 'character', 'line': 0, 'field': '', 'reason': 'is empty'},
          'junk',
        ],
      );
      await expectLater(
        register(),
        throwsA(
          isA<UploadException>()
              .having((e) => e.code, 'code', 'invalid')
              .having((e) => e.message, 'message', contains('does not accept'))
              .having((e) => e.problems.map((p) => '$p').toList(), 'problems', [
                'journey, line 3, field x: is too big',
                'character: is empty',
              ]),
        ),
      );
    });

    test('a 429 keeps Retry-After', () async {
      site.overrides['POST /api/v1/register'] = Reply.error(
        429,
        'rate_limited',
        'Too many requests. Wait 17 seconds, then try again.',
      );
      site.overrides['GET /api/v1/me'] = const Reply(
        429,
        '{"error":"rate_limited","message":"Wait."}',
        {'Retry-After': '17'},
      );
      await expectLater(register(), _fails('rate_limited', status: 429));
      await expectLater(
        client.me(),
        throwsA(isA<UploadException>().having((e) => e.retryAfter, 'wait', 17)),
      );
    });

    test('409, 401 and 500 give the message of the server', () async {
      for (final (status, code) in [
        (409, 'claimed'),
        (401, 'bad_signature'),
        (507, 'quota'),
      ]) {
        site.overrides['POST /api/v1/register'] = Reply.error(
          status,
          code,
          'Plain words for $code.',
        );
        await expectLater(
          register(),
          throwsA(
            isA<UploadException>()
                .having((e) => e.code, 'code', code)
                .having((e) => e.status, 'status', status)
                .having((e) => e.message, 'message', 'Plain words for $code.'),
          ),
        );
      }
    });

    test('an answer that is not the API is a generic error', () async {
      site.overrides['POST /api/v1/register'] = const Reply(502, '<html>');
      await expectLater(
        register(),
        throwsA(
          isA<UploadException>()
              .having((e) => e.code, 'code', 'http_502')
              .having((e) => e.message, 'message', contains('status 502')),
        ),
      );
      site.overrides['GET /api/v1/me'] = const Reply(200, 'not json');
      await expectLater(client.me(), _fails('bad_response', status: 200));
      site.overrides['GET /api/v1/me'] = const Reply(200, '[]');
      await expectLater(client.me(), _fails('bad_response'));
    });

    test('a site that is down says to check the connection', () async {
      final dead = UploadClient(
        site.uri,
        key,
        client: http.Client(),
        timeout: const Duration(seconds: 2),
        sleep: (_) async {},
      );
      await site.close();
      await expectLater(
        dead.register(),
        throwsA(
          isA<UploadException>()
              .having((e) => e.code, 'code', 'network')
              .having(
                (e) => e.message,
                'message',
                'Could not reach 127.0.0.1. Check the internet connection and '
                    'the website address.',
              ),
        ),
      );
      dead.close();
    });

    test('a site that does not answer in time is unreachable', () async {
      final slow = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final hold = Completer<void>();
      slow.listen((r) async {
        await hold.future;
        await r.response.close();
      });
      final c = UploadClient(
        Uri.parse('http://127.0.0.1:${slow.port}'),
        key,
        timeout: const Duration(milliseconds: 200),
        sleep: (_) async {},
      );
      await expectLater(c.me(), _fails('network'));
      hold.complete();
      c.close();
      await slow.close(force: true);
    });
  });

  test('a clock far off is the message of the server', () async {
    site.overrides['GET /api/v1/me'] = Reply.error(
      401,
      'bad_signature',
      'The time of your computer is off. Check the computer clock.',
    );
    await expectLater(
      client.me(),
      throwsA(
        isA<UploadException>().having(
          (e) => e.message,
          'message',
          contains('computer clock'),
        ),
      ),
    );
  });

  test('uploadCharacter on a missing folder is bad_files', () async {
    await expectLater(
      client.uploadCharacter(Directory(p.join(expectedDir, 'nope'))),
      _fails('bad_files'),
    );
    expect(site.calls, isEmpty);
  });

  test('the default client and clock work', () async {
    final c = UploadClient(site.uri, key);
    expect((await c.info()).api, 1);
    c.close();
  });
}
