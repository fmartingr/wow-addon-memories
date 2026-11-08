/// Gathers the Memories saved files of a WoW flavor folder into the folder
/// layout that the website reads, and backs up the raw files.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import '../journal/journal.dart';
import '../journal/trail.dart';
import '../savedvars/lexer.dart' show goQuote;
import '../savedvars/parser.dart';
import 'files.dart';
import 'ids.dart';
import 'issues.dart';
import 'json.dart';
import 'match.dart';
import 'merge.dart';
import 'notes.dart';

/// The addon whose saved file holds the character, its sessions and its trail.
const String coreAddon = 'Memories';

final RegExp _subAddonFile = RegExp(r'^Memories_([A-Za-z0-9]+)\.lua$');
final RegExp _underscores = RegExp(r'^_+|_+$');

/// The options of one gather.
class GatherOptions {
  GatherOptions({
    required this.wowDir,
    required this.dist,
    required this.backup,
    this.defaultId = '',
    DateTime? now,
    this.onEvent,
  }) : now = now ?? DateTime.now();

  /// The flavor folder, such as `.../World of Warcraft/_forever_`.
  final Directory wowDir;

  /// The converted data, `<root>/latest` in the app.
  final Directory dist;

  /// The timestamped raw copies, `<root>/backups` in the app.
  final Directory backup;

  /// The id of the character the website opens first, or "".
  final String defaultId;

  /// The time that names the backup folder.
  final DateTime now;

  /// Receives each log line.
  final void Function(GatherEvent event)? onEvent;
}

/// What a gather did.
class GatherResult {
  const GatherResult({
    this.characters = 0,
    this.lines = 0,
    this.screenshots = 0,
    this.files = 0,
    this.damaged = 0,
    this.failedCharacters = 0,
    this.skippedAccounts = 0,
    this.issues = const [],
  });

  /// The characters written to the output.
  final int characters;

  /// The journal lines of the written characters.
  final int lines;

  /// The screenshots linked to the written characters.
  final int screenshots;

  /// The saved files read.
  final int files;

  /// The saved files that could not be read.
  final int damaged;

  final int failedCharacters;
  final int skippedAccounts;
  final List<GatherIssue> issues;

  /// The problem that stopped the gather, or null.
  GatherIssue? get stop {
    for (final i in issues) {
      if (i.fatal) return i;
    }
    return null;
  }

  /// Why the gather failed, or null when it passed.
  String? get error {
    final s = stop;
    if (s != null) return s.message;
    if (failedCharacters > 0 || skippedAccounts > 0) {
      return '$failedCharacters characters and $skippedAccounts accounts failed';
    }
    return null;
  }
}

/// Reads every Memories saved file of [o.wowDir], merges it with the earlier
/// output in [o.dist] and writes the result there, with raw copies in
/// `<o.backup>/<UTC stamp>`. It reads the saved files and the screenshots and
/// never writes below WTF or Screenshots. Two processes never gather on one
/// backup root at the same time; within one process, the caller runs one
/// gather at a time, since the OS lock is per process and isolates do not
/// share memory.
Future<GatherResult> gather(GatherOptions o) async => _Gather(o).run();

class _Character {
  _Character(this.guid, this.realm, this.char);

  final String guid;
  final String realm;
  final Map<String, Object?> char;
  String id = '';
  String name = '';
  final Map<String, Map<String, Object?>> addons = {};
  List<String> addonNames = const [];
  final List<String> damagedAddons = [];
  List<JournalRecord> records = [];
  List<Chunk> trail = [];
  List<Map<String, Object?>> sessions = [];
  int last = 0;
}

class _IndexEntry {
  _IndexEntry(this.id, this.guid, this.last, this.fields);

  final String id;
  final String guid;
  int last;
  final Map<String, Object?> fields;
}

class _Stop implements Exception {
  const _Stop();
}

String _describe(FileSystemException e) {
  final os = e.osError?.message;
  final detail = os == null || os.isEmpty ? e.message : os;
  return e.path == null ? detail : '${e.path}: $detail';
}

class _Gather {
  _Gather(this.o)
    : wow = p.normalize(p.absolute(o.wowDir.path)),
      dist = p.normalize(p.absolute(o.dist.path)),
      backup = p.normalize(p.absolute(o.backup.path));

  final GatherOptions o;
  final String wow;
  final String dist;
  final String backup;
  String flavor = '';
  String region = 'xx';
  String backupDir = '';
  Map<String, Object?>? earlier;
  final List<GatherIssue> issues = [];
  int files = 0;
  int damaged = 0;
  int badLines = 0;
  int badChunks = 0;
  int joined = 0;
  int failed = 0;
  int skipped = 0;

  void _info(String message) => o.onEvent?.call(GatherEvent(message));

  void _warn(String message, [GatherIssueCode? code, String? path]) {
    o.onEvent?.call(GatherEvent(message, warning: true));
    if (code != null) issues.add(GatherIssue(code, message, path: path));
  }

  Never _fail(GatherIssueCode code, String message, [String? path]) {
    issues.add(GatherIssue(code, message, path: path, fatal: true));
    throw const _Stop();
  }

  GatherResult _result({List<_IndexEntry> index = const []}) => GatherResult(
    characters: index.length,
    lines: index.fold(0, (n, e) => n + (e.fields['steps']! as int)),
    screenshots: index.fold(0, (n, e) => n + (e.fields['screenshots']! as int)),
    files: files,
    damaged: damaged,
    failedCharacters: failed,
    skippedAccounts: skipped,
    issues: List.unmodifiable(issues),
  );

  Future<GatherResult> run() async {
    final GatherLock lock;
    try {
      _check();
      lock = _lock();
    } on _Stop {
      return _result();
    }
    try {
      return _gather();
    } on _Stop {
      return _result();
    } on FileSystemException catch (e) {
      issues.add(
        GatherIssue(
          GatherIssueCode.ioError,
          _describe(e),
          path: e.path,
          fatal: true,
        ),
      );
      return _result();
    } finally {
      lock.release();
    }
  }

  void _check() {
    for (final out in [dist, backup]) {
      for (final src in const ['WTF', 'Screenshots']) {
        // An output folder that holds the source folder would let a character
        // id such as "wtf" name it.
        final s = p.join(wow, src);
        if (inside(out, s) || inside(s, out)) {
          _fail(
            GatherIssueCode.overlap,
            '$out overlaps $src, which the converter never writes',
            out,
          );
        }
      }
    }
    if (!FileSystemEntity.isDirectorySync(p.join(wow, 'WTF', 'Account'))) {
      _fail(
        GatherIssueCode.noWtf,
        '$wow has no WTF/Account folder; pass a flavor folder such as '
        '.../World of Warcraft/_forever_',
        wow,
      );
    }
  }

  /// Takes the lock in the parent of the resolved backup folder, so a backup
  /// path that is a link below WTF never puts the lock file there.
  GatherLock _lock() {
    final root = p.dirname(resolveLinks(backup));
    final GatherLock? lock;
    try {
      lock = GatherLock.acquire(root);
    } on FileSystemException catch (e) {
      _fail(
        GatherIssueCode.notWritable,
        '$root cannot be written: ${_describe(e)}',
        root,
      );
    }
    return lock ??
        _fail(
          GatherIssueCode.lockHeld,
          'another gather is running on $root; wait until it ends',
          root,
        );
  }

  void _checkWritable(String dir) {
    try {
      Directory(dir).createSync(recursive: true);
      final probe = File(p.join(dir, '.memories-write-check.tmp'));
      probe.writeAsBytesSync(const [], flush: true);
      probe.deleteSync();
    } on FileSystemException catch (e) {
      _fail(
        GatherIssueCode.notWritable,
        '$dir cannot be written: ${_describe(e)}',
        dir,
      );
    }
  }

  GatherResult _gather() {
    final indexPath = p.join(dist, 'index.json');
    try {
      // Writing over an index that cannot be read would drop the entries and
      // the default that it keeps.
      earlier = readJson(indexPath);
    } on OutputFileException catch (e) {
      _fail(GatherIssueCode.badIndex, '$e; fix or remove it', indexPath);
    } on FileSystemException catch (e) {
      _fail(
        GatherIssueCode.badIndex,
        '${_describe(e)}; fix or remove it',
        indexPath,
      );
    }
    _checkWritable(backup);
    _checkWritable(dist);
    flavor = p.basename(wow);
    try {
      region = regionOf(File(p.join(wow, 'WTF', 'Config.wtf')));
    } on FileSystemException {
      region = 'xx';
    }
    backupDir = p.join(backup, _stamp(o.now));

    final chars = _scan();
    if (chars.isEmpty) {
      _fail(
        GatherIssueCode.noData,
        'no character with Memories data under $wow; log out of the game or '
        '/reload first',
        wow,
      );
    }
    _assignIds(chars);
    if (o.defaultId.isNotEmpty && !chars.any((c) => c.id == o.defaultId)) {
      _fail(
        GatherIssueCode.badDefault,
        '--default ${goQuote(o.defaultId)} is not a character id',
      );
    }

    final ready = <_Character>[];
    for (final c in chars) {
      try {
        _mergeEarlier(c);
      } on OutputFileException catch (e) {
        _characterFailed(c, '$e');
        continue;
      } on FileSystemException catch (e) {
        _characterFailed(c, _describe(e));
        continue;
      }
      ready.add(c);
    }
    final shots = _screenshots(ready);
    final index = <_IndexEntry>[];
    for (final c in ready) {
      final e = _write(c);
      index.add(e);
      final f = e.fields;
      _info(
        '${c.id}: ${f['steps']} records, ${f['trailPoints']} trail points, '
        '${f['sessions']} sessions, ${f['screenshots']} screenshots, '
        'addons ${c.addonNames.join(', ')}',
      );
    }
    _writeIndex(index);
    _info(
      'read $files files ($damaged damaged), skipped $badLines lines and '
      '$badChunks trail chunks, joined $joined notes',
    );
    _info(
      'copied ${shots.copied} screenshots, ${shots.unmatched} not found; '
      'backup in $backupDir',
    );
    _info('wrote ${index.length} characters to $dist');
    return _result(index: index);
  }

  void _characterFailed(_Character c, String why) {
    _warn(
      '${c.id}: $why; its folder is left as it was',
      GatherIssueCode.characterFailed,
      p.join(dist, c.id),
    );
    failed++;
  }

  List<String> _dirs(String path) {
    final out = <String>[];
    for (final e in Directory(path).listSync(followLinks: false)) {
      final name = p.basename(e.path);
      if (e is Directory && name != 'SavedVariables') out.add(name);
    }
    return out..sort(compareUtf8);
  }

  /// Backs up a saved file, then parses its copy in memory. A damaged file is
  /// reported and gives null.
  Map<String, Object?>? _read(String path, String global) {
    files++;
    final List<int> src;
    try {
      src = File(path).readAsBytesSync();
    } on FileSystemException catch (e) {
      _warn('$path: ${_describe(e)}', GatherIssueCode.damagedFile, path);
      damaged++;
      return null;
    }
    final rel = p.relative(path, from: p.join(wow, 'WTF', 'Account'));
    try {
      writeAtomic(p.join(backupDir, 'savedvariables', flavor, rel), src);
    } on FileSystemException catch (e) {
      _warn(
        'backup of $path: ${_describe(e)}',
        GatherIssueCode.backupFailed,
        path,
      );
    }
    final Map<String, Object?> vars;
    try {
      vars = parseSavedVars(src);
    } on SavedVarsException catch (e) {
      _warn('$path: $e; file skipped', GatherIssueCode.damagedFile, path);
      damaged++;
      return null;
    }
    final data = vars[global];
    if (data is! Map<String, Object?>) {
      _warn(
        '$path has no $global table; file skipped',
        GatherIssueCode.skippedFile,
        path,
      );
      return null;
    }
    return data;
  }

  void _skipAccount(String message, String path) {
    _warn(message, GatherIssueCode.accountSkipped, path);
    skipped++;
  }

  List<_Character> _scan() {
    final accountsDir = p.join(wow, 'WTF', 'Account');
    final byGuid = <String, _Character>{};
    accounts:
    for (final acc in _dirs(accountsDir)) {
      // Without the kinds every field lands in "extra", so no record would
      // match its copy of an earlier run and the journal would hold each
      // record twice. An account without the file and without character data
      // is not an error.
      Kinds? kinds;
      final accFile = p.join(
        accountsDir,
        acc,
        'SavedVariables',
        'Memories.lua',
      );
      if (isFile(accFile)) {
        final db = _read(accFile, 'MemoriesDB');
        if (db == null) {
          _skipAccount(
            'account $acc: its characters are skipped until its Memories.lua '
            'can be read',
            accFile,
          );
          continue;
        }
        kinds = parseKinds(db['kinds']);
        if (kinds.isEmpty) {
          _skipAccount(
            'account $acc: its Memories.lua has no kinds; its characters are '
            'skipped',
            accFile,
          );
          continue;
        }
      }
      for (final realm in _dirs(p.join(accountsDir, acc))) {
        for (final name in _dirs(p.join(accountsDir, acc, realm))) {
          final sv = p.join(accountsDir, acc, realm, name, 'SavedVariables');
          if (kinds == null) {
            if (isFile(p.join(sv, 'Memories.lua'))) {
              _skipAccount(
                'account $acc has character data but no Memories.lua; its '
                'characters are skipped',
                p.join(accountsDir, acc),
              );
              continue accounts;
            }
            continue;
          }
          final folder = charFolder(realm, name);
          final c = _load(sv, folder.realm, folder.name, kinds);
          if (c == null) continue;
          final old = byGuid[c.guid];
          if (old != null) {
            _warn(
              '${c.name}-${c.realm} has the GUID of ${old.name}-${old.realm}; '
              'the one played last is kept',
              GatherIssueCode.duplicateGuid,
              sv,
            );
            if (c.last < old.last) continue;
          }
          byGuid[c.guid] = c;
        }
      }
    }
    return byGuid.values.toList();
  }

  _Character? _load(String sv, String realm, String folder, Kinds kinds) {
    final corePath = p.join(sv, 'Memories.lua');
    if (!isFile(corePath)) return null;
    final db = _read(corePath, 'MemoriesCharDB');
    if (db == null) return null;
    final charValue = db['char'];
    final char = charValue is Map<String, Object?> ? charValue : null;
    final guidValue = char?['guid'];
    final guid = guidValue is String ? guidValue : '';
    if (char == null || guid.isEmpty) {
      _info('$folder-$realm: no character GUID in Memories.lua, skipped');
      return null;
    }
    final c = _Character(guid, realm, char);
    c.addons[coreAddon] = db;
    final name = char['name'];
    c.name = name is String && name.isNotEmpty ? name : folder;

    final names = <String>[];
    try {
      for (final e in Directory(sv).listSync(followLinks: false)) {
        names.add(p.basename(e.path));
      }
    } on FileSystemException {
      // The core file was read, so a folder that cannot be listed has no
      // sub-addon files to add.
    }
    names.sort(compareUtf8);
    for (final file in names) {
      final m = _subAddonFile.firstMatch(file);
      final path = p.join(sv, file);
      if (m == null || !isFile(path)) continue;
      final addon = 'Memories_${m[1]}';
      final damagedBefore = damaged;
      final data = _read(path, 'Memories${m[1]}CharDB');
      if (data == null) {
        if (damaged > damagedBefore) c.damagedAddons.add(addon);
        continue;
      }
      // A sub-addon turned off for this character keeps a file that the game
      // never rewrites, such as one copied from another character's folder;
      // the addon itself moves such data to the orphans when it loads.
      final subChar = data['char'];
      final g = subChar is Map<String, Object?> ? subChar['guid'] : null;
      if (g is String && g.isNotEmpty && g != guid) {
        _warn(
          '$path belongs to the character with GUID $g; file skipped',
          GatherIssueCode.skippedFile,
          path,
        );
        continue;
      }
      c.addons[addon] = data;
    }
    c.addonNames = _addonNames(c.addons);

    final records = <JournalRecord>[];
    for (final addon in c.addonNames) {
      for (final line in journalLines(c.addons[addon]!['log'])) {
        final JournalRecord rec;
        try {
          rec = decodeLine(line, kinds);
        } on ShortLineException {
          badLines++;
          continue;
        } on BadTimeException {
          badLines++;
          continue;
        }
        rec['addon'] = addon;
        records.add(rec);
      }
    }
    final notes = joinNotes(records);
    c.records = notes.records;
    joined += notes.joined;
    final t = trail(db['trail']);
    c.trail = [...t.chunks];
    badChunks += t.bad;
    c.sessions = mergeSessions([asList(db['sessions'])]);
    for (final s in c.sessions) {
      final l = lastOf(s);
      if (l > c.last) c.last = l;
    }
    return c;
  }

  /// Keeps the id of an earlier run while the character's name and realm
  /// still give it, so a folder never changes owner. A new character gets an
  /// id in the order the characters were played, so the one played first
  /// keeps the plain id.
  void _assignIds(List<_Character> chars) {
    chars.sort((a, b) {
      if (a.last != b.last) return a.last.compareTo(b.last);
      return compareUtf8(a.guid, b.guid);
    });
    final taken = <String, String>{};
    final earlierIds = <String, String>{};
    for (final v in _earlierEntries()) {
      final e = _entryOf(v);
      if (idPattern.hasMatch(e.id) && e.guid.isNotEmpty) {
        taken[e.id] = e.guid;
        earlierIds[e.guid] = e.id;
      }
    }
    // A folder that left the index, such as the one of a renamed character,
    // still belongs to its GUID.
    final folders = <FileSystemEntity>[];
    try {
      folders.addAll(Directory(dist).listSync(followLinks: false));
    } on FileSystemException {
      // No earlier output.
    }
    folders.sort((a, b) => compareUtf8(a.path, b.path));
    for (final e in folders) {
      final name = p.basename(e.path);
      if (taken.containsKey(name) ||
          e is! Directory ||
          !idPattern.hasMatch(name)) {
        continue;
      }
      Map<String, Object?>? old;
      try {
        old = readJson(p.join(dist, name, 'character.json'));
      } on Exception {
        old = null;
      }
      final guid = old?['guid'];
      if (guid is String && guid.isNotEmpty) taken[name] = guid;
    }
    for (final c in chars) {
      final base = baseId(region, c.realm, c.name, c.guid);
      final id = earlierIds[c.guid];
      if (id != null && isCandidate(id, base, flavor, c.guid)) {
        c.id = id;
        continue;
      }
      c.id = assignId(taken, base, flavor, c.guid);
    }
    chars.sort((a, b) => compareUtf8(a.id, b.id));
  }

  List<Object?> _earlierEntries() {
    final list = earlier?['characters'];
    return list is List<Object?> ? list : const [];
  }

  void _mergeEarlier(_Character c) {
    final folder = p.join(dist, c.id);
    // A link would send the writes of this character, and its screenshot
    // copies, to its target, which may be inside WTF or Screenshots.
    for (final dir in [folder, p.join(folder, 'screenshots')]) {
      if (FileSystemEntity.isLinkSync(dir)) {
        throw OutputFileException('$dir is a link; replace it with a folder');
      }
    }
    final oldRecords = readJsonl(p.join(folder, 'journey.jsonl'), (row) {
      if (row is! Map<String, Object?>) {
        throw const FormatException('a journal row is not an object');
      }
      return JournalRecord(row);
    });
    final oldTrail = readJsonl(p.join(folder, 'trail.jsonl'), Chunk.fromJson);
    final oldChar = readJson(p.join(folder, 'character.json'));
    final guid = oldChar?['guid'];
    if (guid is String && guid != c.guid) {
      throw OutputFileException(
        'the folder holds the character with GUID $guid',
      );
    }
    // A damaged sub-addon file keeps the addon entry of the earlier run, so the
    // damage does not change the output; its earlier records stay through the
    // merge.
    final oldAddons = oldChar?['addons'];
    if (c.damagedAddons.isNotEmpty && oldAddons is Map<String, Object?>) {
      for (final a in c.damagedAddons) {
        final kept = oldAddons[a];
        if (kept is Map<String, Object?>) c.addons[a] = kept;
      }
      c.addonNames = _addonNames(c.addons);
    }
    c.records = mergeRecords(oldRecords, c.records);
    c.trail = mergeTrail(oldTrail, c.trail);
    final oldSessions = oldChar?['sessions'];
    c.sessions = mergeSessions([
      oldSessions is List<Object?> ? oldSessions : const [],
      c.sessions,
    ]);
    for (final rec in c.records) {
      final i = sessionAt(c.sessions, rec.time).index;
      rec['session'] = i > 0 ? i : null;
    }
  }

  List<String> _listScreenshots(String dir) {
    if (FileSystemEntity.typeSync(dir) == FileSystemEntityType.notFound) {
      return const [];
    }
    final names = <String>[];
    for (final e in Directory(dir).listSync(followLinks: false)) {
      final name = p.basename(e.path);
      if (e is File && fileNamePattern.hasMatch(name)) names.add(name);
    }
    return names..sort(compareUtf8);
  }

  ({int copied, int unmatched}) _screenshots(List<_Character> chars) {
    final src = p.join(wow, 'Screenshots');
    final files = _listScreenshots(src);
    final claimed = <String>{};
    final shots = <Shot>[];
    final refs = <(_Character, JournalRecord)>[];
    for (final c in chars) {
      for (final rec in c.records) {
        final s = rec.text('screenshot');
        if (s.isNotEmpty) {
          claimed.add(
            s.startsWith('screenshots/')
                ? s.substring('screenshots/'.length)
                : s,
          );
          continue;
        }
        final k = rec.text('k');
        final file = rec.text('file');
        if ((k != 'ss' && k != 'sn') ||
            file.isEmpty ||
            rec.text('result') == 'failed') {
          continue;
        }
        final at = sessionAt(c.sessions, rec.time);
        shots.add(Shot(file: file, t: rec.time, tz: at.tz, hasTz: at.hasTz));
        refs.add((c, rec));
      }
    }
    var copied = 0;
    var unmatched = 0;
    final matched = matchShots(shots, files, claimed);
    for (var i = 0; i < matched.length; i++) {
      final j = matched[i];
      if (j < 0) {
        unmatched++;
        continue;
      }
      final name = files[j];
      final from = p.join(src, name);
      final dst = p.join(dist, refs[i].$1.id, 'screenshots', name);
      try {
        if (copyFile(from, dst)) copied++;
      } on FileSystemException catch (e) {
        _warn(
          '$from: ${_describe(e)}; screenshot skipped',
          GatherIssueCode.screenshotFailed,
          from,
        );
        continue;
      }
      try {
        copyFile(dst, p.join(backupDir, 'screenshots', name));
      } on FileSystemException catch (e) {
        _warn(
          'backup of $from: ${_describe(e)}',
          GatherIssueCode.backupFailed,
          from,
        );
      }
      refs[i].$2['screenshot'] = 'screenshots/$name';
    }
    return (copied: copied, unmatched: unmatched);
  }

  _IndexEntry _write(_Character c) {
    final folder = p.join(dist, c.id);
    writeJsonl(p.join(folder, 'journey.jsonl'), c.records);
    writeJsonl(
      p.join(folder, 'trail.jsonl'),
      c.trail.map((ch) => Ordered(ch.toJson())),
    );
    final flavorName = flavor.replaceAll(_underscores, '');
    final regionName = region.toUpperCase();
    final core = c.addons[coreAddon]!;
    final doc = <String, Object?>{
      ...c.char,
      'region': regionName,
      'realm': c.realm,
      'realmLabel': c.char['realm'],
      'flavor': flavorName,
      'sessions': c.sessions,
      'flags': core['flags'],
      'addons': {
        for (final a in c.addonNames)
          a: Ordered({
            'counts': c.addons[a]!['counts'],
            'snap': byLevel(c.addons[a]!['snap']),
            'schema': c.addons[a]!['schema'],
            'writtenBy': c.addons[a]!['writtenBy'],
          }),
      },
    };
    writeAtomic(
      p.join(folder, 'character.json'),
      encodeJsonBytes(doc, indent: true),
    );

    var trailPoints = 0;
    for (final ch in c.trail) {
      trailPoints += ch.n;
    }
    var screenshots = 0;
    for (final rec in c.records) {
      if (rec.text('screenshot').isNotEmpty) screenshots++;
    }
    int? start;
    int? end;
    var last = c.last;
    if (c.records.isNotEmpty) {
      start = c.records.first.time;
      end = c.records.last.time;
      if (end > last) last = end;
    }
    return _IndexEntry(c.id, c.guid, last, {
      'id': c.id,
      'guid': c.guid,
      'name': c.name,
      'region': regionName,
      'realm': c.realm,
      'flavor': flavorName,
      'class': c.char['class'],
      'race': c.char['race'],
      'sex': c.char['sex'],
      'faction': c.char['faction'],
      'level': c.char['level'],
      'path': c.id,
      'journey': '${c.id}/journey.jsonl',
      'trail': '${c.id}/trail.jsonl',
      'character': '${c.id}/character.json',
      'steps': c.records.length,
      'sessions': c.sessions.length,
      'trailPoints': trailPoints,
      'screenshots': screenshots,
      'addons': c.addonNames,
      'start': start,
      'end': end,
    });
  }

  /// Lists the characters of this run and keeps every earlier entry whose
  /// character this run did not write, so a character whose run failed, or
  /// whose saved files are gone, stays on the website with its folder.
  void _writeIndex(List<_IndexEntry> index) {
    final rows = <(String, Object?)>[];
    final ids = <String>{};
    final guids = <String>{};
    for (final e in index) {
      rows.add((e.id, Ordered(e.fields)));
      ids.add(e.id);
      guids.add(e.guid);
    }
    for (final v in _earlierEntries()) {
      final e = _entryOf(v);
      if (idPattern.hasMatch(e.id) &&
          !ids.contains(e.id) &&
          !guids.contains(e.guid)) {
        rows.add((e.id, e.entry));
        ids.add(e.id);
      }
    }
    sortStable(rows, (a, b) => compareUtf8(a.$1, b.$1));

    var def = o.defaultId;
    if (def.isNotEmpty && !ids.contains(def)) {
      _warn(
        '--default ${goQuote(def)} has no entry in index.json; the earlier or '
        'latest character is used',
        GatherIssueCode.badDefault,
      );
      def = '';
    }
    final kept = earlier?['default_character'];
    if (def.isEmpty && kept is String && ids.contains(kept)) def = kept;
    if (def.isEmpty) {
      var best = -1;
      for (final e in index) {
        if (e.last > best) {
          best = e.last;
          def = e.id;
        }
      }
    }
    writeAtomic(
      p.join(dist, 'index.json'),
      encodeJsonBytes({
        'default_character': def,
        'characters': [for (final r in rows) r.$2],
      }, indent: true),
    );
  }
}

({String id, String guid, Map<String, Object?>? entry}) _entryOf(Object? v) {
  final e = v is Map<String, Object?> ? v : null;
  final id = e?['id'];
  final guid = e?['guid'];
  return (
    id: id is String ? id : '',
    guid: guid is String ? guid : '',
    entry: e,
  );
}

/// The core addon, then the sub-addons in byte order.
List<String> _addonNames(Map<String, Object?> addons) => [
  coreAddon,
  ...addons.keys.where((a) => a != coreAddon).toList()..sort(compareUtf8),
];

String _two(int n) => n.toString().padLeft(2, '0');

/// The name of a backup folder: the UTC time as yyyyMMddTHHmmssZ.
String _stamp(DateTime t) {
  final u = t.toUtc();
  return '${u.year.toString().padLeft(4, '0')}${_two(u.month)}${_two(u.day)}'
      'T${_two(u.hour)}${_two(u.minute)}${_two(u.second)}Z';
}

/// Reads the region from WTF/Config.wtf.
String regionOf(File config) =>
    region(String.fromCharCodes(config.readAsBytesSync()));

/// The name and realm of a character folder. The Forever client names it
/// `<Name>-<Realm>` inside a realm id folder such as "93"; other clients name
/// it `<Name>` inside a `<Realm>` folder. A name never holds a "-", so the
/// realm is all the text after the first one.
({String name, String realm}) charFolder(String parent, String folder) {
  final i = folder.indexOf('-');
  if (i > 0 && i < folder.length - 1) {
    return (name: folder.substring(0, i), realm: folder.substring(i + 1));
  }
  return (name: folder, realm: parent);
}

/// Keeps the snapshots keyed by level. The parser turns a gap-free table of
/// levels 1..n into a list.
Object? byLevel(Object? v) {
  if (v is! List<Object?>) return v;
  return {for (var i = 0; i < v.length; i++) '${i + 1}': v[i]};
}
