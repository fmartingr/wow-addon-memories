import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:memories_core/memories_core.dart';
import 'package:memories_core/src/upload/key.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/fixture.dart';

void main() {
  group('parseSite', () {
    test('accepts https and loopback http, and drops the trailing slash', () {
      final cases = {
        'https://wowjourney.xyz': 'https://wowjourney.xyz',
        'https://wowjourney.xyz/': 'https://wowjourney.xyz',
        '  HTTPS://Example.COM:8443/ ': 'https://example.com:8443',
        'http://localhost:8080': 'http://localhost:8080',
        'http://127.0.0.1': 'http://127.0.0.1',
        'http://[::1]:9000/': 'http://[::1]:9000',
      };
      cases.forEach((input, want) {
        expect(parseSite(input).toString(), want, reason: input);
      });
    });

    test('rejects the rest with a plain message', () {
      final cases = {
        'http://example.com': 'https://',
        'ftp://example.com': 'https://',
        'example.com': 'scheme',
        '': 'scheme',
        'https://': 'scheme',
        'https://u:p@example.com': 'user name',
        'https://example.com/api': 'path',
        'https://example.com//': 'path',
        'https://example.com?x=1': 'query',
        'https://example.com#top': 'query',
        'https://exa mple.com': 'not valid',
      };
      cases.forEach((input, word) {
        expect(
          () => parseSite(input),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              contains(word),
            ),
          ),
          reason: input,
        );
      });
    });
  });

  group('UploadKey', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('memories-key-'));
    tearDown(() => tmp.deleteSync(recursive: true));

    test('a saved key loads back as the same key', () {
      final key = UploadKey.generate();
      final file = File(p.join(tmp.path, 'sub', 'key.json'));
      key.save(file);
      final back = UploadKey.load(file);
      expect(back.publicKey, key.publicKey);
      expect(back.fingerprint, key.fingerprint);
      expect(key.publicKey, matches(RegExp(r'^[A-Za-z0-9_-]{43}$')));
      expect(key.fingerprint, matches(RegExp(r'^[0-9a-f]{16}$')));
      expect(
        key.fingerprint,
        sha256.convert(unb64(key.publicKey)).toString().substring(0, 16),
      );
      expect(UploadKey.generate().publicKey, isNot(key.publicKey));
      expect(
        tmp.listSync(recursive: true).map((f) => f.path),
        unorderedEquals([file.parent.path, file.path]),
        reason: 'no temporary file or folder stays',
      );
    });

    test('the key file is private on Linux and macOS', () {
      final file = File(p.join(tmp.path, 'key.json'));
      UploadKey.generate().save(file);
      expect(file.statSync().mode & 511, 384);
    }, skip: Platform.isWindows ? 'no POSIX mode' : false);

    test('a damaged key file is an error', () {
      final cases = [
        'not json',
        '{"v": 2, "seed": "AAAA"}',
        '{"v": 1}',
        '{"v": 1, "seed": "AAAA"}',
        '[]',
      ];
      for (final text in cases) {
        final file = File(p.join(tmp.path, 'bad.json'))
          ..writeAsStringSync(text);
        expect(
          () => UploadKey.load(file),
          throwsA(isA<UploadKeyException>()),
          reason: text,
        );
      }
      final binary = File(p.join(tmp.path, 'bin.json'))
        ..writeAsBytesSync([0xff, 0xfe, 0x00]);
      expect(
        () => UploadKey.load(binary),
        throwsA(isA<UploadKeyException>()),
        reason: 'bytes that are not UTF-8',
      );
    });

    test('fromSeed needs 32 bytes', () {
      expect(
        () => UploadKey.fromSeed([1, 2]),
        throwsA(isA<UploadKeyException>()),
      );
    });
  });

  group('signRequest', () {
    final vector = jsonDecode(
      File('../../server/internal/auth/testdata/vector.json')
          .readAsStringSync(),
    ) as Map<String, Object?>;

    test('gives the signature of the shared vector', () {
      final key = UploadKey.fromSeed(unb64(vector['seed']! as String));
      expect(key.publicKey, vector['publicKey']);
      final headers = signRequest(
        key,
        vector['method']! as String,
        vector['path']! as String,
        utf8.encode(vector['body']! as String),
        DateTime.fromMillisecondsSinceEpoch(
          (vector['time']! as int) * 1000,
          isUtc: true,
        ),
        unb64(vector['nonce']! as String),
      );
      expect(headers, vector['headers']);
    });

    test('lower-case method gives the same headers', () {
      final key = UploadKey.fromSeed(unb64(vector['seed']! as String));
      Map<String, String> sign(String m) => signRequest(
        key,
        m,
        '/x',
        const [],
        DateTime.utc(2026),
        List.filled(16, 1),
      );
      expect(sign('get'), sign('GET'));
    });
  });

  group('prepareCharacter', () {
    final dir = Directory(p.join(expectedDir, 'eu-brumamar-nandu'));

    test('the body and its hash are stable across runs', () {
      final a = prepareCharacter(dir);
      final b = prepareCharacter(dir);
      expect(a.body, b.body);
      expect(a.sha256, b.sha256);
      expect(a.sha256, sha256.convert(a.body).toString());
    });

    test('the body holds the three files and the path is derived', () {
      final c = prepareCharacter(dir);
      expect(c.path, 'wow/eu/brumamar/nandu');
      expect(c.screenshots, [
        'WoWScrnShot_110126_114820.jpg',
        'WoWScrnShot_110126_115001.jpg',
      ]);
      final body = jsonDecode(utf8.decode(c.body)) as Map<String, Object?>;
      expect(body.keys, ['character', 'journey', 'trail']);
      expect((body['journey']! as List<Object?>).length, 15);
      expect((body['trail']! as List<Object?>).length, 1);
      expect(
        (body['character']! as Map<String, Object?>)['guid'],
        'Player-1234-0ABCDEF0',
      );
    });

    test('only .jpg and .png names of the gather pattern are screenshots', () {
      final tmp = Directory.systemTemp.createTempSync('memories-prep-');
      addTearDown(() => tmp.deleteSync(recursive: true));
      void put(String name, String text) =>
          File(p.join(tmp.path, name)).writeAsStringSync(text);
      put(
        'character.json',
        '{"flavor":"wow","region":"EU","realm":"R","name":"N"}',
      );
      put('trail.jsonl', '');
      put(
        'journey.jsonl',
        [
          for (final s in [
            'screenshots/WoWScrnShot_110126_114820.png',
            'screenshots/WoWScrnShot_110126_114821.tga',
            'screenshots/../../secret.jpg',
            'screenshots/other.jpg',
          ])
            jsonEncode({'k': 'in', 'screenshot': s}),
        ].join('\n'),
      );
      expect(prepareCharacter(tmp).screenshots, [
        'WoWScrnShot_110126_114820.png',
      ]);
    });

    test('a damaged folder is a bad_files error', () {
      final tmp = Directory.systemTemp.createTempSync('memories-prep-');
      addTearDown(() => tmp.deleteSync(recursive: true));
      void expectBad(String word) => expect(
        () => prepareCharacter(tmp),
        throwsA(
          isA<UploadException>()
              .having((e) => e.code, 'code', 'bad_files')
              .having((e) => e.message, 'message', contains(word)),
        ),
      );
      expectBad('character.json is missing');
      void put(String name, String text) =>
          File(p.join(tmp.path, name)).writeAsStringSync(text);
      put('character.json', '{nope');
      expectBad('not valid JSON');
      put('character.json', '[]');
      expectBad('JSON object');
      put('character.json', '{"flavor":"wow","region":"EU"}');
      put('journey.jsonl', '');
      put('trail.jsonl', '');
      expectBad('no usable');
      put(
        'character.json',
        '{"flavor":"wow","region":"EU","realm":"R","name":"","guid":"Player-1-2"}',
      );
      expect(prepareCharacter(tmp).path, 'wow/eu/r/player-1-2');
      put('journey.jsonl', '{"k":"in"}\n\n{broken\n');
      expectBad('line 3');
      put('journey.jsonl', '{"k":"in"}\n');
      File(p.join(tmp.path, 'trail.jsonl')).writeAsBytesSync([0xff, 0xfe]);
      expectBad('UTF-8');
    });
  });
}
