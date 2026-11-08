import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:memories_core/memories_core.dart';
import 'package:path/path.dart' as p;
import 'package:wow_journey/src/upload/upload_service.dart';

/// The golden `latest/` folder, relative to `app/` where the tests run.
const String fixtureLatest = '../testdata/expected';

/// A website on a loopback port that records each request line.
class _Site {
  final List<String> requests = [];

  /// The status of each DELETE answer.
  int deleteStatus = 204;
  late final HttpServer server;

  String get address => 'http://127.0.0.1:${server.port}';

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      await request.drain<void>();
      requests.add('${request.method} ${request.uri.path}');
      final path = request.uri.path;
      final response = request.response;
      if (request.method == 'DELETE') {
        response.statusCode = deleteStatus;
        if (deleteStatus == 404) {
          response.headers.contentType = ContentType.json;
          response.write(
            '{"error":"not_found","message":"No such character."}',
          );
        }
      } else {
        response.headers.contentType = ContentType.json;
        if (path.endsWith('/info')) {
          response.write(
            jsonEncode({'api': 1, 'name': 'Test Site', 'registration': 'open'}),
          );
        } else if (path.endsWith('/register')) {
          response.statusCode = 201;
          response.write('{"registered":true}');
        } else if (path.endsWith('/me')) {
          // The sync skips a character only when the site holds it.
          response.write(
            jsonEncode({
              'screenshots': 'none',
              'characters': [
                for (final path in [
                  'wow/eu/brumamar/nandu',
                  'wow/eu/los-errantes/nandu',
                ])
                  {
                    'path': path,
                    'url': 'http://x/$path/',
                    'guid': 'g',
                    'steps': 1,
                    'updated': 1,
                  },
              ],
            }),
          );
        } else if (path.endsWith('/screenshots/request')) {
          response.write('{"screenshots":"pending"}');
        } else {
          response.write(
            jsonEncode({
              'path': 'wow/eu/x/y',
              'url': 'http://x/',
              'steps': 1,
              'added': 1,
            }),
          );
        }
      }
      await response.close();
    });
  }
}

void main() {
  late Directory support;
  late _Site site;
  late CoreUploadService service;

  setUp(() async {
    support = Directory.systemTemp.createTempSync('wow_journey_upload_');
    site = _Site();
    await site.start();
    service = CoreUploadService(() async => support.path);
  });

  tearDown(() async {
    await site.server.close(force: true);
    support.deleteSync(recursive: true);
  });

  File keyFile() => File(p.join(support.path, 'upload-key.json'));

  test('status makes no key and says unregistered', () async {
    final status = await service.status(site.address);
    expect(status.registered, isFalse);
    expect(status.fingerprint, isNull);
    expect(keyFile().existsSync(), isFalse);
  });

  test('info needs no key and saves none', () async {
    final info = await service.info(site.address);
    expect(info.name, 'Test Site');
    expect(info.registration, 'open');
    expect(keyFile().existsSync(), isFalse);
  });

  test('register saves the key and the state for this site only', () async {
    await service.register(site.address, null);
    expect(keyFile().existsSync(), isTrue);
    final status = await service.status(site.address);
    expect(status.registered, isTrue);
    expect(status.fingerprint, matches(RegExp(r'^[0-9a-f]{16}$')));
    expect((await service.status('http://localhost:1')).registered, isFalse);
    expect(site.requests, ['POST /api/v1/register']);
  });

  test('sync uploads each character, then skips what it sent', () async {
    await service.register(site.address, null);
    final first = await service.sync(site.address, fixtureLatest);
    expect(first.characters.map((c) => c.status), [
      SyncStatus.uploaded,
      SyncStatus.uploaded,
    ]);
    final second = await service.sync(site.address, fixtureLatest);
    expect(second.characters.map((c) => c.status), [
      SyncStatus.unchanged,
      SyncStatus.unchanged,
    ]);
    expect(
      site.requests.where((r) => r == 'POST /api/v1/characters'),
      hasLength(2),
    );
  });

  test('a failure inside the isolate keeps its type and message', () async {
    await service.register(site.address, null);
    await expectLater(
      service.sync(site.address, p.join(support.path, 'no-such-folder')),
      throwsA(isA<UploadException>().having((e) => e.code, 'code', 'no_index')),
    );
  });

  test('sync without a key says to register first', () async {
    await expectLater(
      service.sync(site.address, fixtureLatest),
      throwsA(
        isA<UploadException>().having((e) => e.code, 'code', 'not_registered'),
      ),
    );
    expect(keyFile().existsSync(), isFalse);
  });

  test('a damaged key file does not block a check', () async {
    keyFile().writeAsStringSync('not json');
    expect((await service.info(site.address)).name, 'Test Site');
    expect(keyFile().readAsStringSync(), 'not json');
  });

  test('a damaged key file is never replaced', () async {
    keyFile().writeAsStringSync('not json');
    await expectLater(
      service.register(site.address, null),
      throwsA(isA<UploadException>().having((e) => e.code, 'code', 'bad_key')),
    );
    expect(keyFile().readAsStringSync(), 'not json');
  });

  test('an address the app does not accept is a plain message', () async {
    await expectLater(
      service.info('http://example.com'),
      throwsA(
        isA<UploadException>()
            .having((e) => e.code, 'code', 'bad_site')
            .having((e) => e.message, 'message', contains('https://')),
      ),
    );
  });

  test('me, delete and requestScreenshots reach the site', () async {
    await service.register(site.address, null);
    expect((await service.me(site.address)).characters, hasLength(2));
    expect(await service.requestScreenshots(site.address), 'pending');
    await service.delete(site.address, 'wow/eu/brumamar/nandu');
    expect(site.requests.skip(1), [
      'GET /api/v1/me',
      'POST /api/v1/screenshots/request',
      'DELETE /api/v1/characters/wow/eu/brumamar/nandu',
    ]);
  });

  test('a removed character stays removed until resendRemoved', () async {
    await service.register(site.address, null);
    await service.sync(site.address, fixtureLatest);
    await service.delete(site.address, 'wow/eu/brumamar/nandu');
    final auto = await service.sync(site.address, fixtureLatest);
    expect(auto.characters.map((c) => c.status), [
      SyncStatus.removed,
      SyncStatus.unchanged,
    ]);
    final explicit = await service.sync(
      site.address,
      fixtureLatest,
      resendRemoved: true,
    );
    expect(explicit.characters.map((c) => c.status), [
      SyncStatus.uploaded,
      SyncStatus.unchanged,
    ]);
    final after = await service.sync(site.address, fixtureLatest);
    expect(after.characters.first.status, SyncStatus.unchanged);
  });

  test('a delete that gets 404 still marks the character removed', () async {
    await service.register(site.address, null);
    site.deleteStatus = 404;
    await expectLater(
      service.delete(site.address, 'wow/eu/brumamar/nandu'),
      throwsA(
        isA<UploadException>().having((e) => e.code, 'code', 'not_found'),
      ),
    );
    final auto = await service.sync(site.address, fixtureLatest);
    expect(auto.characters.first.status, SyncStatus.removed);
  });

  test('a delete whose state cannot be saved says so', () async {
    await service.register(site.address, null);
    final state = File(p.join(support.path, 'upload-state.json'));
    state.deleteSync();
    Directory(state.path).createSync();
    await expectLater(
      service.delete(site.address, 'wow/eu/brumamar/nandu'),
      throwsA(
        isA<UploadException>()
            .having((e) => e.code, 'code', 'bad_state')
            .having((e) => e.message, 'message', contains('removed')),
      ),
    );
  });

  test('an unreachable site says so in plain words', () async {
    final address = site.address;
    await site.server.close(force: true);
    await expectLater(
      service.info(address),
      throwsA(
        isA<UploadException>().having(
          (e) => e.message,
          'message',
          startsWith('Could not reach'),
        ),
      ),
    );
  });
}
