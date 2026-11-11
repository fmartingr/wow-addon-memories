import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:wow_journey/src/platform/browser.dart';
import 'package:wow_journey/src/viewer/viewer_files.dart';
import 'package:wow_journey/src/viewer/viewer_launcher.dart';

class _Browser implements Browser {
  bool result = true;
  final List<Uri> opened = [];

  @override
  Future<bool> open(Uri url) async {
    opened.add(url);
    return result;
  }
}

void main() {
  late Directory tmp;
  late _Browser browser;
  late ViewerLauncher launcher;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('viewer_launcher_test');
    final dir = Directory(p.join(tmp.path, 'latest', 'eu-a-one'))
      ..createSync(recursive: true);
    File(p.join(dir.path, 'character.json')).writeAsStringSync('{}');
    File(p.join(tmp.path, 'latest', 'index.json')).writeAsStringSync(
      jsonEncode({
        'characters': [
          {'id': 'eu-a-one', 'path': 'eu-a-one', 'name': 'One', 'realm': 'A'},
        ],
      }),
    );
    browser = _Browser();
    launcher = ViewerLauncher(
      files: DirectoryViewerFiles(Directory('../web')),
      browser: browser,
    )..backupRoot = tmp.path;
  });

  tearDown(() async {
    await launcher.close();
    tmp.deleteSync(recursive: true);
  });

  test('open gives the browser the page address of the character', () async {
    final result = await launcher.open('eu-a-one', 'de');
    expect(result, isA<ViewerOpened>());
    final url = browser.opened.single;
    expect(url.host, '127.0.0.1');
    expect(url.path, '/eu-a-one/');
    expect(url.queryParameters, {'lang': 'de'});
    expect(url.toString(), 'http://127.0.0.1:${url.port}/eu-a-one/?lang=de');
  });

  test('the address answers with the page of the backup folder', () async {
    await launcher.open('eu-a-one', 'en');
    final client = HttpClient();
    final response = await (await client.getUrl(browser.opened.single)).close();
    final body = await utf8.decodeStream(response);
    client.close();
    expect(response.statusCode, 200);
    expect(body, contains('<title>One — A — Memories</title>'));
  });

  test('two opens use one server', () async {
    await launcher.open('eu-a-one', 'en');
    await launcher.open('eu-a-one', 'fr');
    expect(browser.opened.map((u) => u.port).toSet(), hasLength(1));
  });

  test(
    'a browser that cannot start gives browserFailed with the address',
    () async {
      browser.result = false;
      final result = await launcher.open('eu-a-one', 'en');
      expect(result, isA<ViewerBrowserFailed>());
      expect((result as ViewerBrowserFailed).url, browser.opened.single);
    },
  );

  test('after close() the address does not answer', () async {
    await launcher.open('eu-a-one', 'en');
    final url = browser.opened.single;
    await launcher.close();
    final client = HttpClient();
    await expectLater(
      client.getUrl(url).then((r) => r.close()),
      throwsA(isA<SocketException>()),
    );
    client.close(force: true);
  });

  test('a changed backup folder is read at the next request', () async {
    await launcher.open('eu-a-one', 'en');
    launcher.backupRoot = p.join(tmp.path, 'nowhere');
    final client = HttpClient();
    final response = await (await client.getUrl(browser.opened.single)).close();
    await response.drain<void>();
    client.close();
    expect(response.statusCode, 404);
  });
}
