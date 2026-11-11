/// A read-only HTTP server on 127.0.0.1 that serves the website character page
/// of each character of `latest/index.json`, with its data and the viewer files.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../l10n/app_locale.dart';
import 'viewer_files.dart';

/// The server could not start.
class ViewerServerException implements Exception {
  const ViewerServerException(this.message);

  final String message;

  @override
  String toString() => 'ViewerServerException: $message';
}

// A copy of server/internal/site/headers.go (characterPagePolicy and
// contentSecurityPolicy). Keep them equal.
const String _framePolicy =
    "frame-ancestors 'none'; base-uri 'none'; form-action 'self'";
const String _pagePolicy =
    "default-src 'self'; img-src 'self' data: https://wow.zamimg.com; "
    "script-src 'self' https://wow.zamimg.com https://nether.wowhead.com; "
    "style-src 'self' https://wow.zamimg.com; "
    "connect-src 'self' https://nether.wowhead.com; $_framePolicy";
const String _otherPolicy =
    "default-src 'self'; img-src 'self' data:; script-src 'self'; "
    "style-src 'self'; $_framePolicy";

// The form of a character id: a copy of idPattern in
// packages/memories_core/lib/src/gather/ids.dart:11 (not exported).
final RegExp _idPattern = RegExp(r'^[a-z0-9]+(-[a-z0-9]+)*$');

// The screenshot names of the website (shotName in server/internal/site/pages.go).
final RegExp _shotName = RegExp(r'^WoWScrnShot_[0-9]{6}_[0-9]{6}\.(jpg|png)$');

const Map<String, String> _assetTypes = {
  '.mjs': 'text/javascript; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.png': 'image/png',
  '.webp': 'image/webp',
  '.jpg': 'image/jpeg',
  '.woff2': 'font/woff2',
  '.txt': 'text/plain; charset=utf-8',
};

const Map<String, String> _dataTypes = {
  'character.json': 'application/json',
  'journey.jsonl': 'application/x-ndjson',
  'trail.jsonl': 'application/x-ndjson',
};

const String _entryJson =
    '{"path":".","character":"character.json",'
    '"journey":"journey.jsonl","trail":"trail.jsonl"}';

const int _maxCharacterFile = 1 << 20;

const int _chunkSize = 64 << 10;

final RegExp _htmlLang = RegExp(r'(<html\b[^>]*?)\slang="[^"]*"');
final RegExp _titleTag = RegExp(r'<title>[^<]*</title>');

class _Character {
  const _Character(this.folder, this.name, this.realm);

  final String folder;
  final String name;
  final String realm;
}

class ViewerServer {
  ViewerServer({required this.files, required this.latestDir});

  final ViewerFiles files;

  /// The `latest/` folder of the current backup folder, read at each request.
  final String? Function() latestDir;

  HttpServer? _server;
  Future<Uri>? _starting;

  /// Binds `127.0.0.1` on a port that the system picks, once. Returns the base
  /// URL `http://127.0.0.1:<port>/`.
  Future<Uri> start() => _starting ??= _bind();

  Future<Uri> _bind() async {
    try {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      _server = server;
      server.listen(_serve, onError: (Object e) => debugPrint('viewer: $e'));
      return Uri(
        scheme: 'http',
        host: '127.0.0.1',
        port: server.port,
        path: '/',
      );
    } on Object catch (e) {
      _starting = null;
      throw ViewerServerException('$e');
    }
  }

  /// The page URL of character [id] in language [lang].
  Uri pageUrl(String id, String lang) {
    final server = _server;
    if (server == null) throw StateError('The viewer server is not started.');
    return Uri(
      scheme: 'http',
      host: '127.0.0.1',
      port: server.port,
      pathSegments: [id, ''],
      queryParameters: {'lang': lang},
    );
  }

  Future<void> close() async {
    final starting = _starting;
    _starting = null;
    if (starting != null) {
      try {
        await starting;
      } on ViewerServerException {
        // Nothing was bound.
      }
    }
    final server = _server;
    _server = null;
    await server?.close(force: true);
  }

  Future<void> _serve(HttpRequest request) async {
    try {
      await _route(request);
    } on Object catch (e, s) {
      debugPrint('viewer: $e\n$s');
      try {
        await _send(
          request,
          HttpStatus.internalServerError,
          'text/plain; charset=utf-8',
          utf8.encode('Something went wrong.'),
        );
      } on Object {
        // The connection is gone.
      }
    }
  }

  void _headers(HttpResponse response, {required bool page}) {
    response.headers
      ..set('X-Content-Type-Options', 'nosniff')
      ..set('Referrer-Policy', 'no-referrer')
      ..set('X-Frame-Options', 'DENY')
      ..set('Cache-Control', 'no-cache')
      ..set('Content-Security-Policy', page ? _pagePolicy : _otherPolicy);
  }

  Future<void> _send(
    HttpRequest request,
    int status,
    String type,
    List<int> body, {
    bool page = false,
  }) async {
    final response = request.response;
    _headers(response, page: page);
    response
      ..statusCode = status
      ..headers.contentType = ContentType.parse(type)
      ..contentLength = body.length;
    if (request.method != 'HEAD') response.add(body);
    await response.close();
  }

  Future<void> _notFound(HttpRequest request) => _send(
    request,
    HttpStatus.notFound,
    'text/plain; charset=utf-8',
    utf8.encode('Not found.'),
  );

  Future<void> _route(HttpRequest request) async {
    final server = _server;
    if (server == null ||
        request.headers.value('host') != '127.0.0.1:${server.port}') {
      return _notFound(request);
    }
    if (request.method != 'GET' && request.method != 'HEAD') {
      return _notFound(request);
    }
    var segments = request.uri.pathSegments;
    if (segments.isEmpty) return _notFound(request);
    final trailing = segments.last.isEmpty;
    if (trailing) segments = segments.sublist(0, segments.length - 1);
    if (segments.isEmpty ||
        segments.any(
          (s) =>
              s.isEmpty ||
              s.startsWith('.') ||
              s.contains('/') ||
              s.contains(r'\') ||
              s.contains('\u0000'),
        )) {
      return _notFound(request);
    }
    if (segments.first == '_') {
      if (trailing || segments.length < 2) return _notFound(request);
      return _asset(request, segments.sublist(1));
    }
    final id = segments.first;
    if (!_idPattern.hasMatch(id)) return _notFound(request);
    if (segments.length == 1 && !trailing) {
      if (await _character(id) == null) return _notFound(request);
      return _redirect(request);
    }
    if (segments.length == 1) return _page(request, id);
    if (trailing || segments[1] != 'data') return _notFound(request);
    if (segments.length == 3) {
      final name = segments[2];
      if (name == 'entry.json') {
        if (await _character(id) == null) return _notFound(request);
        return _send(
          request,
          HttpStatus.ok,
          'application/json',
          utf8.encode(_entryJson),
        );
      }
      final type = _dataTypes[name];
      if (type == null) return _notFound(request);
      return _dataFile(request, id, [name], type);
    }
    if (segments.length == 4 &&
        segments[2] == 'screenshots' &&
        _shotName.hasMatch(segments[3])) {
      final type = segments[3].endsWith('.png') ? 'image/png' : 'image/jpeg';
      return _dataFile(request, id, ['screenshots', segments[3]], type);
    }
    return _notFound(request);
  }

  Future<void> _redirect(HttpRequest request) async {
    final response = request.response;
    _headers(response, page: false);
    final query = request.uri.hasQuery ? '?${request.uri.query}' : '';
    response
      ..statusCode = HttpStatus.movedPermanently
      ..headers.set('Location', '${request.uri.path}/$query')
      ..contentLength = 0;
    await response.close();
  }

  Future<void> _asset(HttpRequest request, List<String> path) async {
    final type = _assetTypes[p.posix.extension(path.last)];
    final joined = path.join('/');
    if (type == null || path.first == 'test' || joined == 'index.html') {
      return _notFound(request);
    }
    final bytes = await files.read(joined);
    if (bytes == null) return _notFound(request);
    return _send(request, HttpStatus.ok, type, bytes);
  }

  /// The character [id] of `latest/index.json`, or null.
  Future<_Character?> _character(String id) async {
    final latest = latestDir();
    if (latest == null) return null;
    Object? index;
    try {
      index = jsonDecode(
        await File(p.join(latest, 'index.json')).readAsString(),
      );
    } on FileSystemException {
      return null;
    } on FormatException {
      return null;
    }
    final list = index is Map<String, Object?> ? index['characters'] : null;
    if (list is! List<Object?>) return null;
    for (final c in list) {
      if (c is! Map<String, Object?> || c['id'] != id) continue;
      final path = c['path'];
      if (path is! String || path.isEmpty) return null;
      final folder = await _within(latest, p.normalize(p.join(latest, path)));
      if (folder == null) return null;
      return _Character(
        folder,
        c['name'] is String ? c['name'] as String : id,
        c['realm'] is String ? c['realm'] as String : '',
      );
    }
    return null;
  }

  /// The resolved [path] when it is inside the resolved [root], else null.
  Future<String?> _within(String root, String path) async {
    if (!p.isWithin(root, path)) return null;
    try {
      final realRoot = await File(root).resolveSymbolicLinks();
      final real = await File(path).resolveSymbolicLinks();
      return p.isWithin(realRoot, real) ? real : null;
    } on FileSystemException {
      return null;
    }
  }

  Future<void> _dataFile(
    HttpRequest request,
    String id,
    List<String> path,
    String type,
  ) async {
    final character = await _character(id);
    if (character == null) return _notFound(request);
    final real = await _within(
      character.folder,
      p.joinAll([character.folder, ...path]),
    );
    if (real == null) return _notFound(request);
    // One open handle gives both the length and the bytes: a gather replaces
    // the file by a rename, and the handle keeps the file it opened.
    final RandomAccessFile file;
    final int length;
    try {
      file = await File(real).open();
    } on FileSystemException {
      return _notFound(request);
    }
    try {
      try {
        length = await file.length();
      } on FileSystemException {
        return await _notFound(request);
      }
      final response = request.response;
      _headers(response, page: false);
      response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.parse(type)
        ..contentLength = length;
      if (request.method != 'HEAD') {
        await response.addStream(_chunks(file, length));
      }
      await response.close();
    } finally {
      await file.close();
    }
  }

  static Stream<List<int>> _chunks(RandomAccessFile file, int length) async* {
    var left = length;
    while (left > 0) {
      final bytes = await file.read(left < _chunkSize ? left : _chunkSize);
      if (bytes.isEmpty) return;
      left -= bytes.length;
      yield bytes;
    }
  }

  Future<void> _page(HttpRequest request, String id) async {
    final character = await _character(id);
    if (character == null) return _notFound(request);
    final template = await files.read('index.html');
    if (template == null) return _notFound(request);
    final lang = request.uri.queryParameters['lang'];
    final known = lang != null && appLanguageCodes.contains(lang);
    final langAttrs = known
        ? ' lang="$lang" data-lang-from="query"'
        : ' lang="en" data-lang-from="default"';
    final (name, realm) = await _titleParts(character);
    final title = const HtmlEscape(HtmlEscapeMode.attribute)
        .convert('$name — $realm — Memories');
    var html = utf8.decode(template);
    html = html.replaceFirstMapped(_htmlLang, (m) => '${m[1]}$langAttrs');
    html = html.replaceFirstMapped(_titleTag, (_) => '<title>$title</title>');
    html = html.replaceFirst('<body', '<body data-entry="data/entry.json"');
    return _send(
      request,
      HttpStatus.ok,
      'text/html; charset=utf-8',
      utf8.encode(html),
      page: true,
    );
  }

  Future<(String, String)> _titleParts(_Character c) async {
    var name = c.name;
    var realm = c.realm;
    final real = await _within(c.folder, p.join(c.folder, 'character.json'));
    if (real == null) return (name, realm);
    try {
      final file = File(real);
      if (await file.length() <= _maxCharacterFile) {
        final data = jsonDecode(await file.readAsString());
        if (data is Map<String, Object?>) {
          if (data['name'] is String && (data['name'] as String).isNotEmpty) {
            name = data['name'] as String;
          }
          for (final key in ['realmLabel', 'realm']) {
            final v = data[key];
            if (v is String && v.isNotEmpty) {
              realm = v;
              break;
            }
          }
        }
      }
    } on FileSystemException {
      // The index entry names are enough.
    } on FormatException {
      // A damaged file: the page still opens.
    }
    return (name, realm);
  }
}
