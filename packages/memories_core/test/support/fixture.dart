import 'dart:io';

import 'package:path/path.dart' as p;

/// The fixture flavor folder, relative to the package root where tests run.
const String fixtureWow = '../../testdata/wow';

/// The golden output of the fixture.
const String expectedDir = '../../testdata/expected';

/// Copies a folder tree; links are not followed.
void copyTree(String from, String to) {
  Directory(to).createSync(recursive: true);
  for (final e in Directory(from).listSync(followLinks: false)) {
    final target = p.join(to, p.basename(e.path));
    if (e is Directory) {
      copyTree(e.path, target);
    } else if (e is File) {
      e.copySync(target);
      File(target).setLastModifiedSync(e.lastModifiedSync());
    }
  }
}

/// Reads every file below [root] as bytes, keyed by its path with "/".
Map<String, List<int>> readTree(String root) {
  final out = <String, List<int>>{};
  if (!Directory(root).existsSync()) return out;
  for (final e in Directory(root).listSync(recursive: true)) {
    if (e is File) {
      out[p.posix.joinAll(p.split(p.relative(e.path, from: root)))] = e
          .readAsBytesSync();
    }
  }
  return out;
}

/// A copy of the fixture as a flavor folder named `_forever_` in a new
/// temporary folder, with the paths of the output folders next to it.
({String root, String wow, String dist, String backup}) copyFixture() {
  final root = Directory.systemTemp.createTempSync('memories-').path;
  final wow = p.join(root, '_forever_');
  copyTree(fixtureWow, wow);
  return (
    root: root,
    wow: wow,
    dist: p.join(root, 'dist'),
    backup: p.join(root, 'backups'),
  );
}
