/// Runs a gather off the UI isolate and keeps its state for the screens.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:memories_core/memories_core.dart';
import 'package:path/path.dart' as p;

/// One character of `latest/index.json`.
@immutable
class CharacterSummary {
  const CharacterSummary({
    required this.id,
    required this.name,
    required this.realm,
    this.path = '',
    this.level,
    this.className,
  });

  final String id;
  final String name;
  final String realm;

  /// The web path `flavor/region/realm/name` that the upload uses for this
  /// character, or empty when `character.json` has none.
  final String path;
  final int? level;

  /// The class token of the game, such as `HUNTER`.
  final String? className;
}

/// What the backup root holds: the gathered characters and their totals, the
/// time of the newest backup and the size on disk.
@immutable
class BackupSnapshot {
  const BackupSnapshot({
    this.characters = const [],
    this.lines = 0,
    this.screenshots = 0,
    this.lastGathered,
    this.sizeBytes = 0,
    this.defaultCharacter,
  });

  final List<CharacterSummary> characters;
  final int lines;
  final int screenshots;

  /// The time of the newest `backups/<stamp>` folder, or null.
  final DateTime? lastGathered;

  final int sizeBytes;

  /// The id of `default_character` in `latest/index.json`, or null.
  final String? defaultCharacter;
}

/// A finished gather and the backup root after it.
typedef GatherReport = ({GatherResult result, BackupSnapshot snapshot});

/// Gathers the data and reads the backup root.
abstract interface class GatherService {
  /// Gathers [flavorDir] into `<backupRoot>/latest` and
  /// `<backupRoot>/backups`. A problem is an issue of the result.
  Future<GatherReport> gather(String flavorDir, String backupRoot);

  /// Reads what [backupRoot] holds. A missing folder gives an empty snapshot.
  Future<BackupSnapshot> inspect(String backupRoot);
}

/// The gather of `memories_core`, each call in a new isolate so that a large
/// saved file does not freeze the window. Only strings go in.
class IsolateGatherService implements GatherService {
  const IsolateGatherService();

  @override
  Future<GatherReport> gather(String flavorDir, String backupRoot) =>
      Isolate.run(() => gatherInto(flavorDir, backupRoot));

  @override
  Future<BackupSnapshot> inspect(String backupRoot) =>
      Isolate.run(() => inspectBackupRoot(backupRoot));
}

/// Gathers into [backupRoot]. It runs on any isolate. The core creates
/// [backupRoot] only after it has refused a root inside WTF or Screenshots,
/// so nothing here creates it first. A root that cannot be written is a
/// `notWritable` issue of the result.
Future<GatherReport> gatherInto(String flavorDir, String backupRoot) async {
  final result = await gather(
    GatherOptions(
      wowDir: Directory(flavorDir),
      dist: Directory(p.join(backupRoot, 'latest')),
      backup: Directory(p.join(backupRoot, 'backups')),
    ),
  );
  return (result: result, snapshot: inspectBackupRoot(backupRoot));
}

String _webPath(String backupRoot, Object? folder) {
  if (folder is! String) return '';
  try {
    return characterPathOf(Directory(p.join(backupRoot, 'latest', folder)));
  } on UploadException {
    return '';
  }
}

final RegExp _stamp = RegExp(r'^(\d{4})(\d\d)(\d\d)T(\d\d)(\d\d)(\d\d)Z$');

/// Reads `latest/index.json`, the newest backup and the size of
/// [backupRoot]. A part that cannot be read is left empty.
BackupSnapshot inspectBackupRoot(String backupRoot) {
  final root = Directory(backupRoot);
  if (!root.existsSync()) return const BackupSnapshot();
  final characters = <CharacterSummary>[];
  var lines = 0;
  var screenshots = 0;
  String? defaultCharacter;
  try {
    final index = jsonDecode(
      File(p.join(backupRoot, 'latest', 'index.json')).readAsStringSync(),
    );
    final map = index is Map<String, Object?>
        ? index
        : const <String, Object?>{};
    final list = map['characters'];
    final chosen = map['default_character'];
    // A gather with no character writes "default_character": "".
    if (chosen is String && chosen.isNotEmpty) defaultCharacter = chosen;
    for (final c in list is List<Object?> ? list : const <Object?>[]) {
      if (c is! Map<String, Object?>) continue;
      characters.add(
        CharacterSummary(
          id: '${c['id'] ?? ''}',
          name: '${c['name'] ?? ''}',
          realm: '${c['realm'] ?? ''}',
          path: _webPath(backupRoot, c['path']),
          level: c['level'] is int ? c['level'] as int : null,
          className: c['class'] is String ? c['class'] as String : null,
        ),
      );
      lines += c['steps'] is int ? c['steps'] as int : 0;
      screenshots += c['screenshots'] is int ? c['screenshots'] as int : 0;
    }
  } on FileSystemException {
    // No gather yet.
  } on FormatException {
    // A gather reports the damaged index; the snapshot shows no characters.
  }
  DateTime? last;
  try {
    for (final e in Directory(p.join(backupRoot, 'backups')).listSync()) {
      final m = _stamp.firstMatch(p.basename(e.path));
      if (e is! Directory || m == null) continue;
      final g = [for (var i = 1; i <= 6; i++) int.parse(m[i]!)];
      final t = DateTime.utc(g[0], g[1], g[2], g[3], g[4], g[5]);
      if (last == null || t.isAfter(last)) last = t;
    }
  } on FileSystemException {
    // No backup yet.
  }
  var size = 0;
  try {
    for (final e in root.listSync(recursive: true, followLinks: false)) {
      if (e is File) size += e.lengthSync();
    }
  } on FileSystemException {
    // A file went away during the walk; the size is a hint only.
  }
  return BackupSnapshot(
    characters: characters,
    lines: lines,
    screenshots: screenshots,
    lastGathered: last?.toLocal(),
    sizeBytes: size,
    defaultCharacter: defaultCharacter,
  );
}

/// The state of [GatherController].
enum GatherState { idle, running, done, failed }

/// Runs one gather at a time and keeps the last result and snapshot.
class GatherController extends ChangeNotifier {
  GatherController(this.service, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final GatherService service;
  final DateTime Function() _clock;

  GatherState _state = GatherState.idle;
  GatherResult? _result;
  BackupSnapshot _snapshot = const BackupSnapshot();
  DateTime? _finishedAt;

  /// The backup root the screen shows. A snapshot or result of another root,
  /// such as a gather that ends after the user chose a new folder, is dropped.
  String? _root;

  /// Orders the reads of the backup root, so that an older read that ends
  /// late does not replace a newer snapshot.
  int _seq = 0;
  int _applied = 0;

  /// Whether [forget] ran during the running gather, whose result is then
  /// of a folder the user no longer uses.
  bool _stale = false;

  GatherState get state => _state;
  bool get running => _state == GatherState.running;

  /// The result of the last gather of this run, or null.
  GatherResult? get result => _result;

  /// The problems of the last gather of this run.
  List<GatherIssue> get issues => _result?.issues ?? const [];

  BackupSnapshot get snapshot => _snapshot;

  /// The end of the last gather that wrote data: this run's, or the newest
  /// backup on disk.
  DateTime? get lastGathered =>
      _state == GatherState.done ? _finishedAt : _snapshot.lastGathered;

  /// Reads what [backupRoot] holds, so the screen shows the earlier data.
  Future<void> refresh(String backupRoot) async {
    _root = backupRoot;
    final seq = ++_seq;
    BackupSnapshot snapshot;
    try {
      snapshot = await service.inspect(backupRoot);
    } on Object {
      snapshot = const BackupSnapshot();
    }
    if (_apply(seq, backupRoot, snapshot)) notifyListeners();
  }

  /// Drops the result of the last gather, such as when the user chose
  /// another folder. A gather that runs now ends without a result.
  void forget() {
    if (running) {
      _stale = true;
      return;
    }
    if (_result == null) return;
    _result = null;
    _finishedAt = null;
    _state = GatherState.idle;
    notifyListeners();
  }

  bool _apply(int seq, String backupRoot, BackupSnapshot snapshot) {
    if (backupRoot != _root || seq < _applied) return false;
    _applied = seq;
    _snapshot = snapshot;
    return true;
  }

  /// Gathers [flavorDir] into [backupRoot]. Returns null and does nothing
  /// while a gather runs. It never throws: an error becomes a fatal issue.
  Future<GatherResult?> gatherNow({
    required String flavorDir,
    required String backupRoot,
  }) async {
    if (running) return null;
    _root = backupRoot;
    final seq = ++_seq;
    _stale = false;
    _state = GatherState.running;
    notifyListeners();
    GatherResult result;
    BackupSnapshot? snapshot;
    try {
      final report = await service.gather(flavorDir, backupRoot);
      result = report.result;
      snapshot = report.snapshot;
    } on Object catch (e) {
      result = GatherResult(
        issues: [GatherIssue(GatherIssueCode.ioError, '$e', fatal: true)],
      );
    }
    if (snapshot != null) _apply(seq, backupRoot, snapshot);
    if (backupRoot != _root || _stale) {
      _stale = false;
      _result = null;
      _finishedAt = null;
      _state = GatherState.idle;
      notifyListeners();
      return result;
    }
    _result = result;
    _finishedAt = _clock();
    _state = result.stop == null ? GatherState.done : GatherState.failed;
    notifyListeners();
    return result;
  }
}
