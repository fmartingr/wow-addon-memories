/// Uploads the changed characters of a `latest/` folder.
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../gather/ids.dart' show idPattern;
import 'client.dart';
import 'state.dart';

/// What happened to one character. [notSelected]: the player did not choose it
/// for this site, so it was skipped.
enum SyncStatus { uploaded, unchanged, failed, notSelected }

/// The screenshot step of one character.
class ShotsResult {
  const ShotsResult({
    this.uploaded = 0,
    this.unchanged = 0,
    this.errors = const [],
    this.stop,
  });

  final int uploaded;
  final int unchanged;

  /// One plain message for each file that failed.
  final List<String> errors;

  /// The failure that every next request of the run would get too.
  final UploadException? stop;
}

/// The result for one character of `latest/index.json`.
class CharacterResult {
  const CharacterResult({
    required this.id,
    required this.path,
    required this.status,
    this.outcome,
    this.error,
    this.shots = const ShotsResult(),
  });

  final String id;

  /// The web path of the character, or empty when `character.json` has none.
  final String path;
  final SyncStatus status;

  /// The answer of the website, when the character went out.
  final UploadOutcome? outcome;
  final UploadException? error;
  final ShotsResult shots;
}

/// The result of one [syncLatest] run.
class SyncReport {
  const SyncReport({required this.screenshots, required this.characters});

  /// The screenshot state of the key: `none`, `pending`, `approved` or
  /// `denied`.
  final String screenshots;
  final List<CharacterResult> characters;

  bool get screenshotsApprovedState => screenshots == 'approved';

  /// Whether a character or a screenshot failed for a reason that needs the
  /// player. A [paused] run is not a failure.
  bool get failed => characters.any(
    (c) =>
        (c.status == SyncStatus.failed && !(c.error?.recoverable ?? false)) ||
        c.shots.errors.isNotEmpty,
  );

  /// Whether the run stopped because the website stayed busy or rate limiting
  /// for the whole retry budget. What was not sent goes out in the next run.
  bool get paused => characters.any(
    (c) =>
        (c.error?.recoverable ?? false) || (c.shots.stop?.recoverable ?? false),
  );
}

/// Counts the requests of a run for `onProgress`.
class _Progress {
  _Progress(this.total, this._callback);

  final int total;
  final void Function(int done, int total)? _callback;
  int _done = 0;

  void tick() {
    // A file that changed since the plan can add a request that the plan did
    // not count.
    if (_done < total) _done++;
    _callback?.call(_done, total);
  }
}

/// Codes that belong to one screenshot file. Any other failure stops the
/// screenshots of that character, because the next file would fail the same.
const Set<String> _perFileCodes = {
  'not_referenced',
  'unsupported_image',
  'too_large',
  'bad_files',
};

/// Reads `latest/index.json` and sends each character whose upload body
/// changed since [state] last saw it, or that the website does not hold. When
/// the key is approved for screenshots, it then sends the screenshots that the
/// records name.
/// [state] is changed in place; the caller saves it.
///
/// [selected] holds the character paths to send (see [SiteState.selected]); a
/// character outside it is skipped with [SyncStatus.notSelected], is not
/// counted in the progress and is left as the state has it. Null sends every
/// character.
///
/// A failure of one character does not stop the others, except a failure that
/// every next request would get too (a rate limit, a busy website, the network,
/// the key or the clock): the characters after it are then reported as failed
/// with the same error, unsent. A failure of the first request to the website,
/// or a missing `index.json`, throws an [UploadException].
///
/// [onProgress] gets `(done, total)` once the plan is known, and after each
/// character or screenshot that went out or failed. `total` counts the
/// characters to send and the screenshots that the state does not hold.
Future<SyncReport> syncLatest(
  Directory latest,
  UploadClient client,
  UploadState state, {
  Set<String>? selected,
  void Function(int done, int total)? onProgress,
}) async {
  final entries = _readIndex(latest);
  final site = state.site(client.site);
  final me = await client.me();
  final approved = me.screenshotsApproved;
  if (approved != site.screenshotsApproved) {
    // The website keeps the screenshot field of a record only for an approved
    // key, so each character goes out again after the approval. A revocation
    // deletes the stored images, so the screenshots go out again too.
    if (approved) {
      site.sent.clear();
      site.shots.clear();
    }
    site.screenshotsApproved = approved;
  }

  final held = {for (final c in me.characters) c.path};
  final progress = _Progress(
    _countRequests(latest, entries, site, approved, held, selected),
    onProgress,
  );
  onProgress?.call(0, progress.total);
  final results = <CharacterResult>[];
  UploadException? stop;
  for (final entry in entries) {
    final skipped = _unselectedPath(
      Directory(p.join(latest.path, entry)),
      selected,
    );
    if (skipped != null) {
      results.add(
        CharacterResult(
          id: entry,
          path: skipped,
          status: SyncStatus.notSelected,
        ),
      );
      continue;
    }
    if (stop != null) {
      results.add(
        CharacterResult(
          id: entry,
          path: '',
          status: SyncStatus.failed,
          error: stop,
        ),
      );
      continue;
    }
    final result = await _syncCharacter(
      latest,
      entry,
      client,
      site,
      approved,
      held,
      progress,
    );
    results.add(result);
    final error = result.error;
    if (error != null && stopsRun(error)) stop = error;
    stop ??= result.shots.stop;
  }
  return SyncReport(screenshots: me.screenshots, characters: results);
}

/// Whether [e] fails every next request of the run too (rate limit, busy
/// server, network, key or clock), so the rest of the characters are not sent.
bool stopsRun(UploadException e) =>
    e.status == 429 ||
    e.status == 503 ||
    const {
      'network',
      'not_registered',
      'key_revoked',
      'bad_signature',
    }.contains(e.code);

List<String> _readIndex(Directory latest) {
  final file = File(p.join(latest.path, 'index.json'));
  final noIndex = UploadException(
    'no_index',
    'Could not read ${file.path}. Run the gather first, then try again.',
  );
  final Object? json;
  try {
    json = jsonDecode(file.readAsStringSync());
  } on FileSystemException {
    throw noIndex;
  } on FormatException {
    throw noIndex;
  }
  final list = json is Map<String, Object?> ? json['characters'] : null;
  if (list is! List<Object?>) throw noIndex;
  return [
    for (final e in list)
      if (e is Map<String, Object?>)
        if (e['path'] is String && idPattern.hasMatch(e['path']! as String))
          e['path']! as String,
  ];
}

/// The number of requests that a run will send: the characters whose body
/// changed or that the website lost, and their screenshots that the state does
/// not hold. It reads the files of each character once more than the run does,
/// and no screenshot.
int _countRequests(
  Directory latest,
  List<String> entries,
  SiteState site,
  bool approved,
  Set<String> held,
  Set<String>? selected,
) {
  var total = 0;
  for (final id in entries) {
    final dir = Directory(p.join(latest.path, id));
    if (_unselectedPath(dir, selected) != null) continue;
    final PreparedCharacter prepared;
    try {
      prepared = prepareCharacter(dir);
    } on UploadException {
      continue;
    }
    final lost = !held.contains(prepared.path);
    if (lost || site.sent[prepared.path] != prepared.sha256) total++;
    if (!approved) continue;
    final sent = lost ? null : site.shots[prepared.path];
    total += prepared.screenshots.where((n) => sent?[n] == null).length;
  }
  return total;
}

/// The path of the character folder [dir] when [selected] leaves it out, else
/// null. A folder that cannot be read has no path to compare, so it is not
/// skipped: its failure is reported like any other.
String? _unselectedPath(Directory dir, Set<String>? selected) {
  if (selected == null) return null;
  try {
    final path = characterPathOf(dir);
    return selected.contains(path) ? null : path;
  } on UploadException {
    return null;
  }
}

Future<CharacterResult> _syncCharacter(
  Directory latest,
  String id,
  UploadClient client,
  SiteState site,
  bool approved,
  Set<String> held,
  _Progress progress,
) async {
  final dir = Directory(p.join(latest.path, id));
  final PreparedCharacter prepared;
  try {
    prepared = prepareCharacter(dir);
  } on UploadException catch (e) {
    return CharacterResult(
      id: id,
      path: '',
      status: SyncStatus.failed,
      error: e,
    );
  }
  // A character removed on the website (another computer, the admin, a reset)
  // must go out again with its screenshots, whatever the state remembers.
  if (!held.contains(prepared.path)) site.forget(prepared.path);
  var status = SyncStatus.unchanged;
  UploadOutcome? outcome;
  if (site.sent[prepared.path] != prepared.sha256) {
    try {
      outcome = await client.uploadPrepared(prepared);
    } on UploadException catch (e) {
      progress.tick();
      return CharacterResult(
        id: id,
        path: prepared.path,
        status: SyncStatus.failed,
        error: e,
      );
    }
    progress.tick();
    site.sent[prepared.path] = prepared.sha256;
    status = SyncStatus.uploaded;
  }
  final shots = approved
      ? await _syncShots(dir, prepared, client, site, progress)
      : const ShotsResult();
  return CharacterResult(
    id: id,
    path: prepared.path,
    status: status,
    outcome: outcome,
    shots: shots,
  );
}

Future<ShotsResult> _syncShots(
  Directory dir,
  PreparedCharacter prepared,
  UploadClient client,
  SiteState site,
  _Progress progress,
) async {
  if (prepared.screenshots.isEmpty) return const ShotsResult();
  final sent = site.shots.putIfAbsent(prepared.path, () => {});
  var uploaded = 0;
  var unchanged = 0;
  final errors = <String>[];
  UploadException? stop;
  for (final name in prepared.screenshots) {
    final file = File(p.join(dir.path, 'screenshots', name));
    final planned = sent[name] == null;
    try {
      if (!file.existsSync()) {
        throw UploadException(
          'bad_files',
          '${file.path} is missing, so the screenshot was not uploaded.',
        );
      }
      final bytes = await file.readAsBytes();
      final sha = sha256.convert(bytes).toString();
      if (sent[name] == sha) {
        unchanged++;
        continue;
      }
      final stored = await client.uploadScreenshot(
        prepared.path,
        file,
        bytes: bytes,
      );
      sent[name] = sha;
      if (stored) {
        uploaded++;
      } else {
        unchanged++;
      }
    } on UploadException catch (e) {
      // A paused run is no failure of this file: it goes out next time.
      if (!e.recoverable) errors.add('$name: ${e.message}');
      if (stopsRun(e)) stop = e;
      if (!_perFileCodes.contains(e.code)) break;
    } on FileSystemException {
      errors.add('$name: the file cannot be read.');
    } finally {
      if (planned) progress.tick();
    }
  }
  return ShotsResult(
    uploaded: uploaded,
    unchanged: unchanged,
    errors: errors,
    stop: stop,
  );
}
