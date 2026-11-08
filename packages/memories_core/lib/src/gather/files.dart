/// File helpers of the gather: atomic writes, read-only copies, the files of
/// an earlier gather, and path checks.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

import '../savedvars/lexer.dart' show decodeUtf8LikeGo;
import 'json.dart';

/// An earlier output file that cannot be read.
class OutputFileException implements Exception {
  const OutputFileException(this.message);

  final String message;

  @override
  String toString() => message;
}

final Random _random = Random();

/// Writes [data] through a temporary file and a rename, so a reader never
/// sees half a file.
void writeAtomic(String path, List<int> data) {
  _replace(path, null, (out) => out.writeFromSync(data));
}

/// Fills a temporary file next to [path] and renames it to [path]. A null
/// [mtime] keeps the time of the write.
void _replace(
  String path,
  DateTime? mtime,
  void Function(RandomAccessFile out) fill,
) {
  final dir = p.dirname(path);
  Directory(dir).createSync(recursive: true);
  late File tmp;
  while (true) {
    tmp = File(p.join(dir, '.memories-${_random.nextInt(1 << 32)}.tmp'));
    try {
      tmp.createSync(exclusive: true);
      break;
    } on PathExistsException {
      continue;
    }
  }
  try {
    final out = tmp.openSync(mode: FileMode.writeOnly);
    try {
      fill(out);
      out.flushSync();
    } finally {
      out.closeSync();
    }
    if (mtime != null) {
      tmp
        ..setLastModifiedSync(mtime)
        ..setLastAccessedSync(mtime);
    }
    tmp.renameSync(path);
  } catch (_) {
    try {
      tmp.deleteSync();
    } on FileSystemException {
      // The rename may have moved it already; nothing is left to clean.
    }
    rethrow;
  }
}

/// Whether [path] is a regular file, not a link.
bool isFile(String path) =>
    FileSystemEntity.typeSync(path, followLinks: false) ==
    FileSystemEntityType.file;

/// Copies a regular file to [dst] unless [dst] exists, and keeps its
/// modification time. It opens [src] only for reading, and refuses a source
/// that is a link or not a regular file. It returns whether it copied.
bool copyFile(String src, String dst) {
  if (FileSystemEntity.typeSync(dst, followLinks: false) !=
      FileSystemEntityType.notFound) {
    return false;
  }
  switch (FileSystemEntity.typeSync(src, followLinks: false)) {
    case FileSystemEntityType.file:
      break;
    case FileSystemEntityType.notFound:
      throw FileSystemException('no such file', src);
    default:
      throw FileSystemException('$src is not a regular file', src);
  }
  final source = File(src);
  final mtime = source.lastModifiedSync();
  final input = source.openSync();
  try {
    _replace(dst, mtime, (out) {
      final buf = List<int>.filled(64 * 1024, 0);
      while (true) {
        final n = input.readIntoSync(buf);
        if (n == 0) break;
        out.writeFromSync(buf, 0, n);
      }
    });
  } finally {
    input.closeSync();
  }
  return true;
}

/// Writes one JSON line for each row.
void writeJsonl(String path, Iterable<Object?> rows) {
  final out = StringBuffer();
  for (final r in rows) {
    out.write(encodeJson(r));
  }
  writeAtomic(path, utf8.encode(out.toString()));
}

String _readText(String path) => decodeUtf8LikeGo(File(path).readAsBytesSync());

bool _missing(String path) =>
    FileSystemEntity.typeSync(path) == FileSystemEntityType.notFound;

/// Reads the rows of an earlier run and turns each one with [convert], which
/// throws a [FormatException] for a row of the wrong form. A missing file has
/// no rows.
List<T> readJsonl<T>(String path, T Function(Object? row) convert) {
  if (_missing(path)) return [];
  final rows = <T>[];
  final lines = _readText(path).split('\n');
  for (var n = 1; n <= lines.length; n++) {
    final line = lines[n - 1].trim();
    if (line.isEmpty) continue;
    try {
      rows.add(convert(jsonDecode(line)));
    } on FormatException catch (e) {
      throw OutputFileException('$path line $n: ${e.message}');
    }
  }
  return rows;
}

/// Reads a JSON object of an earlier run. A missing file, or the value null,
/// gives null.
Map<String, Object?>? readJson(String path) {
  if (_missing(path)) return null;
  final Object? v;
  try {
    v = jsonDecode(_readText(path));
  } on FormatException catch (e) {
    throw OutputFileException('$path: ${e.message}');
  }
  if (v == null) return null;
  if (v is! Map<String, Object?>) {
    throw OutputFileException('$path: not a JSON object');
  }
  return v;
}

/// An exclusive lock on `<root>/.gather.lock`, so two gathers never write one
/// folder at once.
class GatherLock {
  GatherLock._(this.path, this._file);

  final String path;
  final RandomAccessFile _file;

  // The OS lock is per process on Linux and macOS, so a second gather in the
  // same isolate would get it again; this set closes that gap. It does not
  // reach other isolates of the process.
  static final Set<String> _held = {};

  /// Takes the lock of [root], or returns null when another gather holds it.
  static GatherLock? acquire(String root) {
    Directory(root).createSync(recursive: true);
    // One file reached through two spellings of the root must be one key, or
    // the second holder in this process would pass the OS lock.
    final path = p.join(resolveLinks(root), '.gather.lock');
    if (_held.contains(path)) return null;
    final file = File(path).openSync(mode: FileMode.append);
    try {
      file.lockSync(FileLock.exclusive);
    } on FileSystemException catch (e) {
      file.closeSync();
      if (_heldElsewhere(e)) return null;
      rethrow;
    }
    _held.add(path);
    return GatherLock._(path, file);
  }

  // EACCES and EAGAIN (11 on Linux, 35 on macOS) from fcntl, and
  // ERROR_LOCK_VIOLATION from LockFileEx, mean another holder; any other
  // error, such as a file system without locks, is not contention.
  static bool _heldElsewhere(FileSystemException e) {
    final code = e.osError?.errorCode;
    if (code == null) return false;
    if (Platform.isWindows) return code == 33;
    return code == 13 || code == (Platform.isMacOS ? 35 : 11);
  }

  /// Releases the lock.
  void release() {
    _held.remove(path);
    try {
      _file.unlockSync();
    } finally {
      _file.closeSync();
    }
  }
}

/// Reports whether [path] is [dir] or below it, after links in the existing
/// part of both are resolved. It ignores case, since the game runs on file
/// systems where "wtf" and "WTF" are one folder.
bool inside(String path, String dir) =>
    isWithinIgnoringCase(resolveLinks(path), resolveLinks(dir));

/// The path part of [inside], with a path [style] for tests of other systems.
bool isWithinIgnoringCase(String path, String dir, {p.Context? style}) {
  final ctx = style ?? p.context;
  final a = ctx.normalize(path.toLowerCase());
  final b = ctx.normalize(dir.toLowerCase());
  return ctx.equals(a, b) || ctx.isWithin(b, a);
}

/// Resolves the links of the longest part of [path] that exists, and keeps
/// the rest as it is.
String resolveLinks(String path) {
  var current = p.normalize(p.absolute(path));
  final rest = <String>[];
  while (true) {
    try {
      final real = File(current).resolveSymbolicLinksSync();
      return p.joinAll([real, ...rest]);
    } on FileSystemException {
      final parent = p.dirname(current);
      if (parent == current) return p.joinAll([current, ...rest]);
      rest.insert(0, p.basename(current));
      current = parent;
    }
  }
}
