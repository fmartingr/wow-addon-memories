/// The signature of the Memories saved files of a flavor folder, so that a
/// watcher sees when the game saved them. It reads file metadata only.
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

/// The files that a gather reads: `Memories.lua` and `Memories_<Addon>.lua`.
final RegExp _memoriesFile = RegExp(r'^Memories(_[A-Za-z0-9]+)?\.lua$');

/// A SHA-256 hash of the path, size and modification time of each Memories
/// saved file in `WTF/Account/*/SavedVariables/` and
/// `WTF/Account/*/*/*/SavedVariables/` of [flavorDir].
///
/// It is null when the folder holds no such file, such as when it is gone,
/// or when a folder could not be listed; a caller treats null as no news and
/// asks again later. Like a gather, it skips links, so it never looks outside
/// the folder.
Future<String?> signature(Directory flavorDir) async {
  final wtf = p.join(flavorDir.path, 'WTF');
  final accounts = p.join(wtf, 'Account');
  final entries = <String>[];
  try {
    if (!await _isDirectory(wtf) || !await _isDirectory(accounts)) return null;
    for (final account in await _folders(accounts)) {
      await _addFiles(p.join(account, 'SavedVariables'), entries);
      for (final realm in await _folders(account)) {
        for (final character in await _folders(realm)) {
          await _addFiles(p.join(character, 'SavedVariables'), entries);
        }
      }
    }
  } on FileSystemException {
    return null;
  }
  if (entries.isEmpty) return null;
  entries.sort();
  return sha256.convert(utf8.encode(entries.join('\n'))).toString();
}

Future<bool> _isDirectory(String path) async =>
    await FileSystemEntity.type(path, followLinks: false) ==
    FileSystemEntityType.directory;

/// The folders in [path] that are not links, apart from `SavedVariables`.
Future<List<String>> _folders(String path) async {
  if (!await _isDirectory(path)) return const [];
  return [
    await for (final e in Directory(path).list(followLinks: false))
      if (e is Directory && p.basename(e.path) != 'SavedVariables') e.path,
  ];
}

Future<void> _addFiles(String savedVariables, List<String> entries) async {
  if (!await _isDirectory(savedVariables)) return;
  await for (final e in Directory(savedVariables).list(followLinks: false)) {
    if (e is! File || !_memoriesFile.hasMatch(p.basename(e.path))) continue;
    final stat = await e.stat();
    // A file deleted since the listing is gone, as the next listing shows.
    if (stat.type != FileSystemEntityType.file) continue;
    entries.add(
      '${e.path}|${stat.size}|${stat.modified.millisecondsSinceEpoch}',
    );
  }
}
