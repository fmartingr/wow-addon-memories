import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:wow_journey/src/viewer/viewer_files.dart';
import 'package:wow_journey/src/viewer/viewer_server.dart';

const _shot = 'WoWScrnShot_110726_225120.jpg';

class _Reply {
  _Reply(this.status, this.headers, this.body);

  final int status;
  final HttpHeaders? headers;
  final List<int> body;

  String get text => utf8.decode(body);
}

void main() {
  late Directory tmp;
  late Directory latest;
  late ViewerServer server;
  late Uri base;
  late HttpClient client;

  void write(String path, String text) {
    final file = File(p.join(latest.path, path));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(text);
  }

  void writeIndex(List<Map<String, Object?>> characters) =>
      write('index.json', jsonEncode({'characters': characters}));

  Future<_Reply> rawGet(String method, String path, String host) async {
    final socket = await Socket.connect(base.host, base.port);
    socket.write(
      '$method $path HTTP/1.1\r\nHost: $host\r\nConnection: close\r\n\r\n',
    );
    final bytes = <int>[];
    await for (final chunk in socket) {
      bytes.addAll(chunk);
    }
    socket.destroy();
    final text = latin1.decode(bytes);
    return _Reply(int.parse(text.split(' ')[1]), null, utf8.encode(text));
  }

  Future<_Reply> get(String path, {String? host, String method = 'GET'}) async {
    if (host != null) return rawGet(method, path, host);
    final request = await client.openUrl(method, base.resolve(path));
    request.followRedirects = false;
    final response = await request.close();
    final body = <int>[];
    await for (final chunk in response) {
      body.addAll(chunk);
    }
    return _Reply(response.statusCode, response.headers, body);
  }

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('viewer_server_test');
    latest = Directory(p.join(tmp.path, 'latest'))..createSync();
    File(p.join(tmp.path, 'secret.txt')).writeAsStringSync('outside');
    write(
      'eu-test-pyron/character.json',
      '{"name":"Pyron","realm":"Test","realmLabel":"Realm <4> & Co"}',
    );
    write('eu-test-pyron/journey.jsonl', '{"a":1}\n');
    write('eu-test-pyron/trail.jsonl', '{"b":2}\n');
    write('eu-test-pyron/screenshots/$_shot', 'jpegbytes');
    write('eu-test-pyron/screenshots/other.jpg', 'x');
    writeIndex([
      {
        'id': 'eu-test-pyron',
        'path': 'eu-test-pyron',
        'name': 'Pyron',
        'realm': 'Test',
      },
      {'id': 'eu-out', 'path': '../', 'name': 'Out', 'realm': 'X'},
      {'id': 'eu-abs', 'path': tmp.path, 'name': 'Abs', 'realm': 'X'},
      {'id': 'eu-link', 'path': 'eu-link', 'name': 'Link', 'realm': 'X'},
    ]);
    Link(p.join(latest.path, 'eu-link')).createSync(tmp.path);
    server = ViewerServer(
      files: DirectoryViewerFiles(Directory('../web')),
      latestDir: () => latest.path,
    );
    base = await server.start();
    client = HttpClient();
  });

  tearDown(() async {
    client.close(force: true);
    await server.close();
    tmp.deleteSync(recursive: true);
  });

  group('the page', () {
    test(
      'has the language, the title, data-entry and the page policy',
      () async {
        final r = await get('/eu-test-pyron/?lang=de');
        expect(r.status, 200);
        expect(r.headers!.contentType?.mimeType, 'text/html');
        expect(r.text, contains('<html lang="de" data-lang-from="query">'));
        expect(
          r.text,
          contains(
            '<title>Pyron — Realm &lt;4&gt; &amp; Co — Memories</title>',
          ),
        );
        expect(r.text, contains('<body data-entry="data/entry.json"'));
        final csp = r.headers!.value('content-security-policy')!;
        expect(csp, contains('https://nether.wowhead.com'));
        expect(csp, contains('https://wow.zamimg.com'));
      },
    );

    test(
      'uses English and "default" without ?lang or with an unknown one',
      () async {
        for (final path in ['/eu-test-pyron/', '/eu-test-pyron/?lang=xx']) {
          final r = await get(path);
          expect(r.text, contains('<html lang="en" data-lang-from="default">'));
        }
      },
    );

    test(
      'falls back to the index names when character.json is damaged',
      () async {
        write('eu-test-pyron/character.json', 'not json');
        final r = await get('/eu-test-pyron/');
        expect(r.text, contains('<title>Pyron — Test — Memories</title>'));
      },
    );

    test('escapes a name with markup', () async {
      writeIndex([
        {'id': 'eu-x', 'path': 'eu-x', 'name': '<b>&', 'realm': 'R'},
      ]);
      write('eu-x/journey.jsonl', '');
      final r = await get('/eu-x/');
      expect(r.text, contains('<title>&lt;b&gt;&amp; — R — Memories</title>'));
    });

    test('/<id> redirects with the query', () async {
      final r = await get('/eu-test-pyron?lang=fr');
      expect(r.status, 301);
      expect(r.headers!.value('location'), '/eu-test-pyron/?lang=fr');
    });

    test('/<id> of an unknown character gives 404, not a redirect', () async {
      expect((await get('/eu-nobody')).status, 404);
    });

    test('HEAD answers with no body', () async {
      final r = await get('/eu-test-pyron/', method: 'HEAD');
      expect(r.status, 200);
      expect(r.body, isEmpty);
      expect(r.headers!.contentLength, greaterThan(0));
    });
  });

  group('the data', () {
    test('entry.json has the form of the website', () async {
      final r = await get('/eu-test-pyron/data/entry.json');
      expect(r.status, 200);
      expect(jsonDecode(r.text), {
        'path': '.',
        'character': 'character.json',
        'journey': 'journey.jsonl',
        'trail': 'trail.jsonl',
      });
    });

    test('the data files have their bytes and types', () async {
      var r = await get('/eu-test-pyron/data/character.json');
      expect(r.status, 200);
      expect(r.headers!.contentType?.mimeType, 'application/json');
      expect(r.text, contains('"Pyron"'));
      r = await get('/eu-test-pyron/data/journey.jsonl');
      expect(r.headers!.contentType?.mimeType, 'application/x-ndjson');
      expect(r.text, '{"a":1}\n');
      r = await get('/eu-test-pyron/data/trail.jsonl');
      expect(r.text, '{"b":2}\n');
    });

    test('a screenshot has its type; another name gives 404', () async {
      var r = await get('/eu-test-pyron/data/screenshots/$_shot');
      expect(r.status, 200);
      expect(r.headers!.contentType?.mimeType, 'image/jpeg');
      expect(r.text, 'jpegbytes');
      r = await get('/eu-test-pyron/data/screenshots/other.jpg');
      expect(r.status, 404);
    });

    test('a missing data file gives 404', () async {
      write('eu-x/character.json', '{}');
      writeIndex([
        {'id': 'eu-x', 'path': 'eu-x', 'name': 'X', 'realm': 'R'},
      ]);
      expect((await get('/eu-x/data/journey.jsonl')).status, 404);
    });
  });

  group('the viewer files', () {
    test('serve the code, fonts and map art with their types', () async {
      for (final (path, type) in [
        ('/_/app.mjs', 'text/javascript'),
        ('/_/base.css', 'text/css'),
        ('/_/fonts/Cinzel-Variable.woff2', 'font/woff2'),
        ('/_/map/world.js', 'text/javascript'),
        ('/_/icon.png', 'image/png'),
      ]) {
        final r = await get(path);
        expect(r.status, 200, reason: path);
        expect(r.headers!.contentType?.mimeType, type, reason: path);
      }
    });

    test('refuse the tests, the notes and the page template', () async {
      for (final path in [
        '/_/test/viewer.test.mjs',
        '/_/map/README.md',
        '/_/fonts/README.md',
        '/_/index.html',
        '/_/',
        '/_',
        '/_/nothing.mjs',
      ]) {
        expect((await get(path)).status, 404, reason: path);
      }
    });
  });

  group('the request rules', () {
    test('every answer has the security headers', () async {
      for (final path in [
        '/eu-test-pyron/',
        '/_/app.mjs',
        '/nothing/',
        '/eu-test-pyron',
      ]) {
        final r = await get(path);
        expect(
          r.headers!.value('x-content-type-options'),
          'nosniff',
          reason: path,
        );
        expect(
          r.headers!.value('referrer-policy'),
          'no-referrer',
          reason: path,
        );
        expect(r.headers!.value('x-frame-options'), 'DENY', reason: path);
        expect(r.headers!.value('cache-control'), 'no-cache', reason: path);
        expect(
          r.headers!.value('content-security-policy'),
          contains("frame-ancestors 'none'"),
          reason: path,
        );
      }
      final other = await get('/_/app.mjs');
      expect(
        other.headers!.value('content-security-policy'),
        isNot(contains('wowhead')),
      );
    });

    test('a Host other than 127.0.0.1:<port> gives 404', () async {
      for (final host in [
        'localhost:${base.port}',
        '127.0.0.1',
        'evil.example',
        'evil.example:${base.port}',
      ]) {
        expect(
          (await get('/eu-test-pyron/', host: host)).status,
          404,
          reason: host,
        );
        expect((await get('/_/app.mjs', host: host)).status, 404, reason: host);
      }
    });

    test('a method other than GET and HEAD gives 404', () async {
      for (final m in ['POST', 'PUT', 'DELETE', 'OPTIONS', 'PATCH']) {
        expect(
          (await get('/eu-test-pyron/', method: m)).status,
          404,
          reason: m,
        );
      }
    });

    test('an unknown path or id gives 404', () async {
      for (final path in [
        '/',
        '/robots.txt',
        '/eu-nobody/',
        '/eu-nobody',
        '/eu-test-pyron/other',
        '/eu-test-pyron/data/',
        '/eu-test-pyron/data/index.json',
        '/eu-test-pyron/data/entry.json/',
        '/EU-TEST-PYRON/',
      ]) {
        expect((await get(path)).status, 404, reason: path);
      }
    });

    test('a path that leaves its folder gives 404 and reads nothing', () async {
      for (final path in [
        '/eu-test-pyron/data/../../secret.txt',
        '/eu-test-pyron/data/%2e%2e/%2e%2e/secret.txt',
        '/eu-test-pyron/data/screenshots/..%2f..%2fsecret.txt',
        '/eu-test-pyron/data/..%2fcharacter.json',
        '/_/../secret.txt',
        '/_/%2e%2e/secret.txt',
        '/_/..%2fsecret.txt',
        '/_/fonts/..%5c..%5csecret.txt',
        '/_//app.mjs',
        '/_/.git/config',
      ]) {
        final r = await get(path);
        expect(r.status, 404, reason: path);
        expect(r.text, isNot(contains('outside')), reason: path);
      }
    });

    test('an index entry that leaves latest/ gives 404', () async {
      write('../secret/character.json', 'outside');
      for (final id in ['eu-out', 'eu-abs']) {
        expect((await get('/$id/')).status, 404, reason: id);
        expect((await get('/$id/data/character.json')).status, 404, reason: id);
      }
    });

    test('a link that points outside latest/ gives 404', () async {
      File(p.join(tmp.path, 'character.json')).writeAsStringSync('outside');
      final r = await get('/eu-link/data/character.json');
      expect(r.status, 404);
      expect(r.text, isNot(contains('outside')));
      expect((await get('/eu-link/')).status, 404);
    });

    test(
      'a character.json link that points outside is not in the title',
      () async {
        final outside = File(p.join(tmp.path, 'other.json'))
          ..writeAsStringSync('{"name":"Secret","realmLabel":"Hidden"}');
        final file = File(
          p.join(latest.path, 'eu-test-pyron', 'character.json'),
        )..deleteSync();
        Link(file.path).createSync(outside.path);
        final r = await get('/eu-test-pyron/');
        expect(r.status, 200);
        expect(r.text, contains('<title>Pyron — Test — Memories</title>'));
        expect(r.text, isNot(contains('Secret')));
      },
    );

    test('a screenshot link that points outside gives 404', () async {
      Link(
        p.join(
          latest.path,
          'eu-test-pyron',
          'screenshots',
          'WoWScrnShot_000000_000000.png',
        ),
      ).createSync(p.join(tmp.path, 'secret.txt'));
      final r = await get(
        '/eu-test-pyron/data/screenshots/WoWScrnShot_000000_000000.png',
      );
      expect(r.status, 404);
      expect(r.text, isNot(contains('outside')));
    });
  });

  group('a damaged latest/', () {
    test(
      'a missing latest/ gives 404 and the next good request works',
      () async {
        latest.renameSync('${latest.path}.away');
        expect((await get('/eu-test-pyron/')).status, 404);
        expect((await get('/eu-test-pyron/data/entry.json')).status, 404);
        expect((await get('/_/app.mjs')).status, 200);
        Directory('${latest.path}.away').renameSync(latest.path);
        expect((await get('/eu-test-pyron/')).status, 200);
      },
    );

    test('an index that is not JSON gives 404, then recovers', () async {
      final index = File(p.join(latest.path, 'index.json'));
      final good = index.readAsStringSync();
      index.writeAsStringSync('{"characters": [');
      expect((await get('/eu-test-pyron/')).status, 404);
      index.writeAsStringSync(good);
      expect((await get('/eu-test-pyron/')).status, 200);
    });

    test('characters that is not a list gives 404', () async {
      write('index.json', '{"characters": {"id": "eu-test-pyron"}}');
      expect((await get('/eu-test-pyron/')).status, 404);
    });

    test('a null latest folder gives 404', () async {
      final none = ViewerServer(
        files: DirectoryViewerFiles(Directory('../web')),
        latestDir: () => null,
      );
      final url = await none.start();
      final request = await client.getUrl(url.resolve('/eu-test-pyron/'));
      final response = await request.close();
      await response.drain<void>();
      expect(response.statusCode, 404);
      await none.close();
    });
  });

  group('the life of the server', () {
    test('binds to 127.0.0.1 and start() twice gives one port', () async {
      expect(base.host, '127.0.0.1');
      expect(base.port, isNonZero);
      expect(await server.start(), base);
    });

    test('pageUrl has the id and the language', () {
      expect(
        server.pageUrl('eu-test-pyron', 'de').toString(),
        'http://127.0.0.1:${base.port}/eu-test-pyron/?lang=de',
      );
    });

    test('after close() a connection fails', () async {
      await server.close();
      await expectLater(
        get('/eu-test-pyron/'),
        throwsA(isA<SocketException>()),
      );
    });

    test('close() during start() leaves no server', () async {
      final early = ViewerServer(
        files: DirectoryViewerFiles(Directory('../web')),
        latestDir: () => latest.path,
      );
      final starting = early.start();
      await early.close();
      final port = (await starting).port;
      await expectLater(
        Socket.connect(InternetAddress.loopbackIPv4, port),
        throwsA(isA<SocketException>()),
      );
    });

    test('start() works again after close()', () async {
      await server.close();
      base = await server.start();
      expect((await get('/eu-test-pyron/')).status, 200);
    });

    test('the changed backup folder is read at the next request', () async {
      final other = Directory(p.join(tmp.path, 'other'))..createSync();
      File(p.join(other.path, 'index.json'))
          .writeAsStringSync('{"characters":[]}');
      var dir = latest.path;
      final moving = ViewerServer(
        files: DirectoryViewerFiles(Directory('../web')),
        latestDir: () => dir,
      );
      final url = await moving.start();
      Future<int> status() async {
        final r = await (await client.getUrl(url.resolve('/eu-test-pyron/')))
            .close();
        await r.drain<void>();
        return r.statusCode;
      }

      expect(await status(), 200);
      dir = other.path;
      expect(await status(), 404);
      await moving.close();
    });
  });
}
