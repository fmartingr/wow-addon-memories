/// Uploads the changed characters of a `latest/` folder.
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../gather/ids.dart' show idPattern;
import 'client.dart';
import 'state.dart';

/// What happened to one character.
enum SyncStatus { uploaded, unchanged, failed }

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

  bool get failed => characters.any(
    (c) => c.status == SyncStatus.failed || c.shots.errors.isNotEmpty,
  );
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
/// A failure of one character does not stop the others, except a failure that
/// every next request would get too (a rate limit, a busy website, the network,
/// the key or the clock): the characters after it are then reported as failed
/// with the same error, unsent. A failure of the first request to the website,
/// or a missing `index.json`, throws an [UploadException].
Future<SyncReport> syncLatest(
  Directory latest,
  UploadClient client,
  UploadState state,
) async {
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
  final results = <CharacterResult>[];
  UploadException? stop;
  for (final entry in entries) {
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
    );
    results.add(result);
    final error = result.error;
    if (error != null && _stopsRun(error)) stop = error;
    stop ??= result.shots.stop;
  }
  return SyncReport(screenshots: me.screenshots, characters: results);
}

/// Whether [e] fails every next request of the run too (rate limit, busy
/// server, network, key or clock), so the rest of the characters are not sent.
bool _stopsRun(UploadException e) =>
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

Future<CharacterResult> _syncCharacter(
  Directory latest,
  String id,
  UploadClient client,
  SiteState site,
  bool approved,
  Set<String> held,
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
      return CharacterResult(
        id: id,
        path: prepared.path,
        status: SyncStatus.failed,
        error: e,
      );
    }
    site.sent[prepared.path] = prepared.sha256;
    status = SyncStatus.uploaded;
  }
  final shots = approved
      ? await _syncShots(dir, prepared, client, site)
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
) async {
  if (prepared.screenshots.isEmpty) return const ShotsResult();
  final sent = site.shots.putIfAbsent(prepared.path, () => {});
  var uploaded = 0;
  var unchanged = 0;
  final errors = <String>[];
  UploadException? stop;
  for (final name in prepared.screenshots) {
    final file = File(p.join(dir.path, 'screenshots', name));
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
      errors.add('$name: ${e.message}');
      if (_stopsRun(e)) stop = e;
      if (!_perFileCodes.contains(e.code)) break;
    } on FileSystemException {
      errors.add('$name: the file cannot be read.');
    }
  }
  return ShotsResult(
    uploaded: uploaded,
    unchanged: unchanged,
    errors: errors,
    stop: stop,
  );
}
