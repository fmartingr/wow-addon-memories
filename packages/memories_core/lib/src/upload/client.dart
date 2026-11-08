/// The client of the upload API of a website.
library;

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../gather/ids.dart' show idPattern, slug;
import '../gather/match.dart' show fileNamePattern;
import 'key.dart';
import 'signer.dart';

/// One problem of a rejected upload.
class UploadProblem {
  const UploadProblem({
    required this.file,
    required this.line,
    required this.field,
    required this.reason,
  });

  factory UploadProblem.fromJson(Map<String, Object?> json) => UploadProblem(
    file: '${json['file'] ?? ''}',
    line: json['line'] is int ? json['line']! as int : 0,
    field: '${json['field'] ?? ''}',
    reason: '${json['reason'] ?? ''}',
  );

  final String file;
  final int line;
  final String field;
  final String reason;

  @override
  String toString() {
    final where = [
      if (file.isNotEmpty) file,
      if (line > 0) 'line $line',
      if (field.isNotEmpty) 'field $field',
    ].join(', ');
    return where.isEmpty ? reason : '$where: $reason';
  }
}

/// A failed request. [message] is plain English and says what to do.
class UploadException implements Exception {
  const UploadException(
    this.code,
    this.message, {
    this.problems = const [],
    this.status,
    this.retryAfter,
    this.recoverable = false,
  });

  /// The error code of the server (`invalid`, `claimed`, ...), or `network`,
  /// `bad_files` or `bad_response` for a failure on this side.
  final String code;
  final String message;
  final List<UploadProblem> problems;

  /// The HTTP status, or null when no answer came.
  final int? status;

  /// The seconds of the `Retry-After` header of a `429` or `503`.
  final int? retryAfter;

  /// True when the client waited out a `429` or `503` for its whole retry
  /// budget and gave up. The website was only busy: the next run can send
  /// the rest, so a caller shows no error for it.
  final bool recoverable;

  UploadException asRecoverable() => UploadException(
    code,
    message,
    problems: problems,
    status: status,
    retryAfter: retryAfter,
    recoverable: true,
  );

  @override
  String toString() => message;
}

/// The answer of `GET /api/v1/info`.
class SiteInfo {
  const SiteInfo({
    required this.api,
    required this.name,
    required this.registration,
  });

  final int api;
  final String name;

  /// `invite` or `open`.
  final String registration;
}

/// A character that the website holds for this key.
class RemoteCharacter {
  const RemoteCharacter({
    required this.path,
    required this.url,
    required this.guid,
    required this.steps,
    required this.updated,
  });

  final String path;
  final String url;
  final String guid;
  final int steps;
  final int updated;
}

/// The answer of `GET /api/v1/me`.
class MeInfo {
  const MeInfo({required this.screenshots, required this.characters});

  /// `none`, `pending`, `approved` or `denied`.
  final String screenshots;
  final List<RemoteCharacter> characters;

  bool get screenshotsApproved => screenshots == 'approved';
}

/// The answer to an upload of one character.
class UploadOutcome {
  const UploadOutcome({
    required this.path,
    required this.url,
    required this.steps,
    required this.added,
  });

  final String path;
  final String url;
  final int steps;

  /// The number of records that the website did not have.
  final int added;
}

/// The body of one character upload, before gzip.
class PreparedCharacter {
  const PreparedCharacter({
    required this.path,
    required this.body,
    required this.sha256,
    required this.screenshots,
  });

  /// The web path `<flavor>/<region>/<realm>/<name>` that the website derives
  /// from `character.json`.
  final String path;

  /// The JSON body `{"character", "journey", "trail"}`, built from the text of
  /// the files so that the same files always give the same bytes.
  final Uint8List body;

  /// The lower-case hex SHA-256 of [body].
  final String sha256;

  /// The file names under `screenshots/` that the records name.
  final List<String> screenshots;
}

const String _apiBase = '/api/v1';

/// Whether [path] is a character web path `<flavor>/<region>/<realm>/<name>`.
bool isCharacterPath(String path) {
  final parts = path.split('/');
  return parts.length == 4 && parts.every(idPattern.hasMatch);
}

UploadException _badFiles(String message) =>
    UploadException('bad_files', message);

/// Reads the 3 files of the character folder [dir] and builds the upload body.
/// Throws an [UploadException] with code `bad_files` when a file is missing or
/// is not valid JSON.
PreparedCharacter prepareCharacter(Directory dir) {
  String read(String name) {
    final file = File(p.join(dir.path, name));
    try {
      return utf8.decode(file.readAsBytesSync());
    } on FileSystemException {
      throw _badFiles('${file.path} is missing or cannot be read.');
    } on FormatException {
      throw _badFiles('${file.path} is not valid UTF-8 text.');
    }
  }

  final characterText = read('character.json').trim();
  final Object? character;
  try {
    character = jsonDecode(characterText);
  } on FormatException {
    throw _badFiles('${p.join(dir.path, 'character.json')} is not valid JSON.');
  }
  if (character is! Map<String, Object?>) {
    throw _badFiles(
      '${p.join(dir.path, 'character.json')} does not hold a JSON object.',
    );
  }

  final screenshots = <String>{};
  List<String> lines(String name, {bool journey = false}) {
    final out = <String>[];
    var n = 0;
    for (final raw in const LineSplitter().convert(read(name))) {
      n++;
      final line = raw.trim();
      if (line.isEmpty) continue;
      final Object? record;
      try {
        record = jsonDecode(line);
      } on FormatException {
        throw _badFiles('${p.join(dir.path, name)} line $n is not valid JSON.');
      }
      if (journey && record is Map<String, Object?>) {
        final shot = record['screenshot'];
        if (shot is String && shot.startsWith('screenshots/')) {
          final name = shot.substring('screenshots/'.length);
          // The website takes .jpg and .png only, and a name outside the
          // gather's pattern could point outside the screenshots folder.
          if (fileNamePattern.hasMatch(name) && !name.endsWith('.tga')) {
            screenshots.add(name);
          }
        }
      }
      out.add(line);
    }
    return out;
  }

  final journey = lines('journey.jsonl', journey: true);
  final trail = lines('trail.jsonl');
  final body = Uint8List.fromList(
    utf8.encode(
      '{"character":$characterText,"journey":[${journey.join(',')}],'
      '"trail":[${trail.join(',')}]}',
    ),
  );
  return PreparedCharacter(
    path: _characterPath(character, dir),
    body: body,
    sha256: sha256.convert(body).toString(),
    screenshots: screenshots.toList()..sort(),
  );
}

/// The path that the website derives: the same rules as the character ids.
String _characterPath(Map<String, Object?> c, Directory dir) {
  String text(String key) => c[key] is String ? c[key]! as String : '';
  final name = slug(text('name'));
  final parts = [
    slug(text('flavor')),
    text('region').toLowerCase(),
    slug(text('realm')),
    name.isEmpty ? slug(text('guid')) : name,
  ];
  if (parts.any((s) => !idPattern.hasMatch(s))) {
    throw _badFiles(
      '${p.join(dir.path, 'character.json')} has no usable flavor, region, '
      'realm and name.',
    );
  }
  return parts.join('/');
}

/// The default number of requests that a client sends in any 60 seconds. The
/// server accepts 30 signed requests a minute for a key in a fixed window, so
/// this leaves room for the requests of the app that no run paces.
const int defaultRequestsPerMinute = 25;

/// The default total time that a client waits for a busy or rate limiting
/// website before it gives up.
const Duration defaultRetryBudget = Duration(minutes: 10);

const Duration _defaultRetryAfter = Duration(seconds: 5);
const Duration _maxRetryAfter = Duration(seconds: 70);
const int _networkTries = 3;

/// Talks to the API of one website with the signature of one key.
///
/// It keeps a run below the rate limit of the website: no more than
/// [requestsPerMinute] requests go out in any 60 seconds (the next one waits),
/// and a `429` or `503` is waited out with the `Retry-After` of the answer and
/// sent again, until the waits of this client add up to [retryBudget]. A
/// failed connection is tried [_networkTries] times with a growing pause.
/// Then the failure is thrown, with [UploadException.recoverable] set for a
/// `429` or `503`.
class UploadClient {
  /// [requestsPerMinute] of 0 or null turns the pacing off; a [retryBudget] of
  /// zero turns the waits off. [sleep] and [monotonic] let a test replace the
  /// time. [onWait] is called with the seconds before each wait that the
  /// website asked for.
  UploadClient(
    this.site,
    this.key, {
    http.Client? client,
    DateTime Function()? clock,
    this.timeout = const Duration(minutes: 2),
    this.requestsPerMinute = defaultRequestsPerMinute,
    this.retryBudget = defaultRetryBudget,
    Future<void> Function(Duration)? sleep,
    Duration Function()? monotonic,
    this.onWait,
  }) : _http = client ?? http.Client(),
       _clock = clock ?? DateTime.now,
       _sleep = sleep ?? Future<void>.delayed,
       _monotonic = monotonic ?? _stopwatch();

  final Uri site;
  final UploadKey key;
  final Duration timeout;
  final int? requestsPerMinute;
  final Duration retryBudget;
  final void Function(int seconds)? onWait;
  final http.Client _http;
  final DateTime Function() _clock;
  final Future<void> Function(Duration) _sleep;
  final Duration Function() _monotonic;
  final Random _random = Random.secure();

  /// When each of the last [requestsPerMinute] requests went out.
  final Queue<Duration> _sent = Queue();
  Duration _waited = Duration.zero;

  static Duration Function() _stopwatch() {
    final watch = Stopwatch()..start();
    return () => watch.elapsed;
  }

  /// Closes the HTTP client.
  void close() => _http.close();

  /// Asks the website about itself. This request is not signed.
  Future<SiteInfo> info() async {
    final json = await _json(
      await _send('GET', '$_apiBase/info', signed: false),
    );
    return SiteInfo(
      api: _int(json, 'api'),
      name: '${json['name'] ?? ''}',
      registration: '${json['registration'] ?? ''}',
    );
  }

  /// Registers the key, with an [invite] code when the website asks for one.
  /// Returns true when the key is new and false when it was registered.
  Future<bool> register({String? invite}) async {
    final body = utf8.encode(
      jsonEncode({if (invite != null && invite.isNotEmpty) 'invite': invite}),
    );
    final res = await _send(
      'POST',
      '$_apiBase/register',
      body: body,
      expect: {200, 201},
    );
    return res.statusCode == 201;
  }

  /// The screenshot state of the key and the characters that it owns.
  Future<MeInfo> me() async {
    final json = await _json(await _send('GET', '$_apiBase/me'));
    final list = json['characters'];
    return MeInfo(
      screenshots: '${json['screenshots'] ?? 'none'}',
      characters: [
        if (list is List<Object?>)
          for (final c in list)
            if (c is Map<String, Object?>)
              RemoteCharacter(
                path: '${c['path'] ?? ''}',
                url: '${c['url'] ?? ''}',
                guid: '${c['guid'] ?? ''}',
                steps: _int(c, 'steps'),
                updated: _int(c, 'updated'),
              ),
      ],
    );
  }

  /// Asks for the approval to upload screenshots. Returns the new state.
  Future<String> requestScreenshots() async {
    final json = await _json(
      await _send('POST', '$_apiBase/screenshots/request'),
    );
    return '${json['screenshots'] ?? ''}';
  }

  /// Uploads the character of the folder [charDir].
  Future<UploadOutcome> uploadCharacter(Directory charDir) async =>
      uploadPrepared(prepareCharacter(charDir));

  /// Uploads a body made by [prepareCharacter], as gzip.
  Future<UploadOutcome> uploadPrepared(PreparedCharacter prepared) async {
    final res = await _send(
      'POST',
      '$_apiBase/characters',
      body: GZipCodec().encode(prepared.body),
      headers: {'Content-Type': 'application/json', 'Content-Encoding': 'gzip'},
    );
    final json = await _json(res);
    return UploadOutcome(
      path: '${json['path'] ?? prepared.path}',
      url: '${json['url'] ?? ''}',
      steps: _int(json, 'steps'),
      added: _int(json, 'added'),
    );
  }

  /// Uploads the screenshot [file] of the character at [path]. [bytes], when
  /// given, are the content of [file] that the caller already read. Returns
  /// true when the website stored it and false when it already held the same
  /// file.
  Future<bool> uploadScreenshot(
    String path,
    File file, {
    Uint8List? bytes,
  }) async {
    final checked = _checkedPath(path);
    try {
      bytes ??= await file.readAsBytes();
    } on FileSystemException {
      throw _badFiles('${file.path} is missing or cannot be read.');
    }
    final res = await _send(
      'PUT',
      '$_apiBase/characters/$checked/screenshots/'
          '${p.basename(file.path)}',
      body: bytes,
      headers: {'Content-Type': 'application/octet-stream'},
      expect: {200, 201},
    );
    return res.statusCode == 201;
  }

  /// Removes the character at [path] from the website.
  Future<void> deleteCharacter(String path) async {
    await _send(
      'DELETE',
      '$_apiBase/characters/${_checkedPath(path)}',
      expect: {204},
    );
  }

  String _checkedPath(String path) {
    if (!isCharacterPath(path)) {
      throw ArgumentError.value(
        path,
        'path',
        'A character path looks like wow/eu/realm-name/character-name.',
      );
    }
    return path;
  }

  Future<http.Response> _send(
    String method,
    String path, {
    List<int> body = const [],
    Map<String, String> headers = const {},
    Set<int> expect = const {200},
    bool signed = true,
  }) async {
    final uri = site.replace(path: path);
    var tries = 0;
    while (true) {
      await _pace();
      // Each try is signed again: the server remembers the nonce of a request
      // it answered, so a repeated nonce would be refused as a replay.
      final request = http.Request(method, uri)
        ..bodyBytes = body
        ..headers.addAll(headers);
      if (signed) {
        request.headers.addAll(
          signRequest(
            key,
            method,
            uri.path,
            body,
            _clock().toUtc(),
            List<int>.generate(16, (_) => _random.nextInt(256)),
          ),
        );
      }
      http.Response? got;
      try {
        got = await http.Response.fromStream(
          await _http.send(request).timeout(timeout),
        ).timeout(timeout);
      } on http.ClientException catch (_) {
        // Falls through to the retry below.
      } on IOException catch (_) {
        // Falls through to the retry below.
      } on TimeoutException catch (_) {
        // Falls through to the retry below.
      }
      if (got == null) {
        if (++tries >= _networkTries) throw _unreachable();
        await _sleep(Duration(seconds: 1 << (tries - 1)) + _jitter());
        continue;
      }
      final res = got;
      if (expect.contains(res.statusCode)) return res;
      final failure = _failure(res);
      if (res.statusCode != 429 && res.statusCode != 503) throw failure;
      final wait = _retryWait(failure);
      if (_waited + wait > retryBudget) throw failure.asRecoverable();
      _waited += wait;
      onWait?.call(wait.inSeconds);
      await _sleep(wait);
    }
  }

  Duration _retryWait(UploadException e) {
    final seconds = e.retryAfter;
    final base = seconds == null || seconds < 1
        ? _defaultRetryAfter
        : Duration(seconds: seconds);
    return (base > _maxRetryAfter ? _maxRetryAfter : base) + _jitter();
  }

  Duration _jitter() => Duration(milliseconds: _random.nextInt(1000));

  /// Waits until a request fits in the rate limit, and notes it.
  Future<void> _pace() async {
    final limit = requestsPerMinute;
    if (limit == null || limit <= 0) return;
    const window = Duration(minutes: 1);
    if (_sent.length >= limit) {
      final ready = _sent.removeFirst() + window;
      final wait = ready - _monotonic();
      if (wait > Duration.zero) await _sleep(wait);
    }
    _sent.add(_monotonic());
  }

  UploadException _unreachable() => UploadException(
    'network',
    'Could not reach ${site.host}. Check the internet connection and the '
        'website address.',
  );
}

int _int(Map<String, Object?> json, String key) {
  final v = json[key];
  return v is int ? v : 0;
}

Future<Map<String, Object?>> _json(http.Response res) async {
  try {
    final json = jsonDecode(utf8.decode(res.bodyBytes));
    if (json is Map<String, Object?>) return json;
  } on FormatException {
    // Falls through to the error below.
  }
  throw UploadException(
    'bad_response',
    'The website sent an answer that this program does not understand. Check '
        'the website address.',
    status: res.statusCode,
  );
}

UploadException _failure(http.Response res) {
  final retry = int.tryParse(res.headers['retry-after'] ?? '');
  String code = 'http_${res.statusCode}';
  String message =
      'The website answered with status ${res.statusCode}. Try again later, '
      'and check the website address.';
  var problems = <UploadProblem>[];
  try {
    final json = jsonDecode(utf8.decode(res.bodyBytes));
    if (json is Map<String, Object?> && json['error'] is String) {
      code = json['error']! as String;
      if (json['message'] is String) message = json['message']! as String;
      final list = json['problems'];
      if (list is List<Object?>) {
        problems = [
          for (final e in list)
            if (e is Map<String, Object?>) UploadProblem.fromJson(e),
        ];
      }
    }
  } on FormatException {
    // A proxy page or an empty body keeps the generic message.
  }
  return UploadException(
    code,
    message,
    problems: problems,
    status: res.statusCode,
    retryAfter: retry,
  );
}
