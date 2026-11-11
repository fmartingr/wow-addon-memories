// Copies the viewer files of web/ into app/assets/viewer/ and checks the copy.
// Run from app/: `fvm dart run tool/viewer_assets.dart [--check]`.
import 'dart:io';

import 'package:path/path.dart' as p;

const _keptDocs = {'map/README.md', 'fonts/README.md'};
final _pubspecEntry = RegExp(
  r'''^\s*-\s*(["']?)(assets/viewer/[^\s"'#]*)\1\s*(#.*)?$''',
);

File _file(Directory root, String path) =>
    File(p.joinAll([root.path, ...path.split('/')]));

/// Relative paths (with `/`) of every file in [dir], sorted.
Future<List<String>> _relativeFiles(Directory dir) async {
  final files = <String>[];
  await for (final entity in dir.list(recursive: true, followLinks: false)) {
    if (entity is File) {
      files.add(p.split(p.relative(entity.path, from: dir.path)).join('/'));
    }
  }
  files.sort();
  return files;
}

/// Relative paths (with `/`) of the files of [web] that the app ships.
Future<List<String>> viewerSourceFiles(Directory web) async {
  return (await _relativeFiles(web)).where((path) {
    final segments = path.split('/');
    if (segments.any((s) => s.startsWith('.'))) return false;
    if (segments.first == 'test') return false;
    if (path == 'map/cover.jpg') return false;
    return !path.endsWith('.md') || _keptDocs.contains(path);
  }).toList();
}

/// Replaces [copy] with the viewer files of [web].
Future<void> copyViewer(Directory web, Directory copy) async {
  if (await copy.exists()) await copy.delete(recursive: true);
  for (final path in await viewerSourceFiles(web)) {
    final target = _file(copy, path);
    await target.parent.create(recursive: true);
    await _file(web, path).copy(target.path);
  }
}

/// Folders with `assets/viewer/` entries in the text of a pubspec.yaml.
Set<String> pubspecViewerFolders(String pubspec) {
  final folders = <String>{};
  for (final line in pubspec.split('\n')) {
    final m = _pubspecEntry.firstMatch(line.trimRight());
    if (m != null) folders.add(m.group(2)!);
  }
  return folders;
}

/// One line for each difference between [web] and [copy], or for each folder
/// of [copy] that [pubspec] does not list. An empty list means no difference.
Future<List<String>> viewerDiff(
  Directory web,
  Directory copy,
  String pubspec,
) async {
  final diff = <String>[];
  final source = await viewerSourceFiles(web);
  final copied = await copy.exists()
      ? await viewerCopyFiles(copy)
      : const <String>[];
  final copiedSet = copied.toSet();
  final sourceSet = source.toSet();
  for (final path in source) {
    if (!copiedSet.contains(path)) {
      diff.add('missing in the copy: $path');
      continue;
    }
    if (!await _sameFile(_file(web, path), _file(copy, path))) {
      diff.add('different bytes: $path');
    }
  }
  for (final path in copied) {
    if (!sourceSet.contains(path)) diff.add('only in the copy: $path');
  }
  final listed = pubspecViewerFolders(pubspec);
  // Flutter asset folders are not recursive: every folder with files needs its
  // own entry, while a listed folder only has to exist.
  final folders = <String>{};
  final existing = <String>{'assets/viewer/'};
  for (final path in copied) {
    var dir = p.posix.dirname(path);
    folders.add(dir == '.' ? 'assets/viewer/' : 'assets/viewer/$dir/');
    while (dir != '.') {
      existing.add('assets/viewer/$dir/');
      dir = p.posix.dirname(dir);
    }
  }
  for (final folder in folders.toList()..sort()) {
    if (!listed.contains(folder)) {
      diff.add('folder not listed in pubspec.yaml: $folder');
    }
  }
  for (final folder in listed.toList()..sort()) {
    if (folder.endsWith('/') &&
        (copied.isEmpty || !existing.contains(folder))) {
      diff.add('pubspec.yaml lists a folder that is not in the copy: $folder');
    }
  }
  return diff;
}

/// Relative paths (with `/`) of every file in [copy].
Future<List<String>> viewerCopyFiles(Directory copy) => _relativeFiles(copy);

Future<bool> _sameFile(File a, File b) async {
  if (await a.length() != await b.length()) return false;
  final x = await a.readAsBytes();
  final y = await b.readAsBytes();
  for (var i = 0; i < x.length; i++) {
    if (x[i] != y[i]) return false;
  }
  return true;
}

Future<void> main(List<String> args) async {
  final check = args.contains('--check');
  final pubspecFile = File('pubspec.yaml');
  final web = Directory('../web');
  if (!await pubspecFile.exists() || !await web.exists()) {
    stderr.writeln('viewer_assets: run from app/ in the repository.');
    exitCode = 2;
    return;
  }
  final copy = Directory('assets/viewer');
  if (!check) {
    await copyViewer(web, copy);
    return;
  }
  final diff = await viewerDiff(web, copy, await pubspecFile.readAsString());
  if (diff.isEmpty) return;
  diff.forEach(stderr.writeln);
  stderr.writeln(
    'viewer_assets: run `make app-viewer` and update pubspec.yaml.',
  );
  exitCode = 1;
}
