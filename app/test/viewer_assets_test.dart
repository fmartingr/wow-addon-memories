import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../tool/viewer_assets.dart';

const _pubspec = '''
flutter:
  assets:
    - assets/crest.png
    - assets/viewer/
    - assets/viewer/lib/
    - assets/viewer/map/
''';

void _write(Directory root, String path, [String text = 'x']) {
  final file = File(p.joinAll([root.path, ...path.split('/')]));
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(text);
}

void main() {
  late Directory tmp;
  late Directory web;
  late Directory copy;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('viewer_assets_test');
    web = Directory(p.join(tmp.path, 'web'))..createSync();
    copy = Directory(p.join(tmp.path, 'app', 'assets', 'viewer'));
    _write(web, 'index.html', '<body');
    _write(web, 'app.mjs');
    _write(web, 'lib/data.mjs');
    _write(web, 'map/world.js', 'window.WORLD');
    _write(web, 'map/README.md', 'attribution');
    _write(web, 'map/cover.jpg');
    _write(web, 'fonts/README.md');
    _write(web, 'notes.md');
    _write(web, 'test/data.test.mjs');
    _write(web, '.hidden');
    _write(web, 'lib/.cache/x.mjs');
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  test('the copy skips test/, dot files, cover.jpg and other docs', () async {
    await copyViewer(web, copy);
    expect(await viewerCopyFiles(copy), [
      'app.mjs',
      'fonts/README.md',
      'index.html',
      'lib/data.mjs',
      'map/README.md',
      'map/world.js',
    ]);
  });

  test('the copy drops a file that web/ no longer has', () async {
    await copyViewer(web, copy);
    File(p.join(web.path, 'app.mjs')).deleteSync();
    await copyViewer(web, copy);
    expect(await viewerCopyFiles(copy), isNot(contains('app.mjs')));
  });

  group('viewerDiff', () {
    const full = '''
    - assets/viewer/
    - assets/viewer/fonts/
    - assets/viewer/lib/
    - assets/viewer/map/
''';

    test('reports nothing on a fresh copy', () async {
      await copyViewer(web, copy);
      expect(await viewerDiff(web, copy, full), isEmpty);
    });

    test('reports a changed byte', () async {
      await copyViewer(web, copy);
      _write(copy, 'app.mjs', 'y');
      expect(await viewerDiff(web, copy, full), ['different bytes: app.mjs']);
    });

    test('reports a missing file', () async {
      await copyViewer(web, copy);
      File(p.join(copy.path, 'lib', 'data.mjs')).deleteSync();
      expect(await viewerDiff(web, copy, full), [
        'missing in the copy: lib/data.mjs',
        'pubspec.yaml lists a folder that is not in the copy: assets/viewer/lib/',
      ]);
    });

    test('reports an extra file', () async {
      await copyViewer(web, copy);
      _write(copy, 'extra.mjs');
      expect(await viewerDiff(web, copy, full), [
        'only in the copy: extra.mjs',
      ]);
    });

    test('reports a missing copy', () async {
      final diff = await viewerDiff(web, copy, full);
      expect(diff, contains('missing in the copy: index.html'));
    });

    test('reports a folder without a pubspec entry', () async {
      _write(web, 'ui/view.mjs');
      await copyViewer(web, copy);
      expect(await viewerDiff(web, copy, full), [
        'folder not listed in pubspec.yaml: assets/viewer/ui/',
      ]);
    });

    test('reports a pubspec entry for a missing folder', () async {
      await copyViewer(web, copy);
      expect(await viewerDiff(web, copy, '$full    - assets/viewer/gone/\n'), [
        'pubspec.yaml lists a folder that is not in the copy: assets/viewer/gone/',
      ]);
    });

    test('accepts a pubspec entry for a folder with only subfolders', () async {
      _write(web, 'map/tiles/0/a.webp');
      await copyViewer(web, copy);
      expect(
        await viewerDiff(
          web,
          copy,
          '$full    - assets/viewer/map/tiles/\n'
          '    - assets/viewer/map/tiles/0/\n',
        ),
        isEmpty,
      );
    });
  });

  test('pubspecViewerFolders reads quoted and commented entries', () {
    expect(
      pubspecViewerFolders('''
    - "assets/viewer/"
    - assets/viewer/lib/ # modules
    # - assets/viewer/off/
'''),
      {'assets/viewer/', 'assets/viewer/lib/'},
    );
  });

  test('pubspecViewerFolders reads only the viewer entries', () {
    expect(pubspecViewerFolders(_pubspec), {
      'assets/viewer/',
      'assets/viewer/lib/',
      'assets/viewer/map/',
    });
  });

  group('the asset bundle', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    test('has the viewer page and the map data', () async {
      final page = await rootBundle.loadString('assets/viewer/index.html');
      expect(page, contains('<body'));
      final world = await rootBundle.loadString('assets/viewer/map/world.js');
      expect(world, contains('WORLD'));
    });
  });
}
