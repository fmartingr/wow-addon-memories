import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:memories_core/src/gather/ids.dart';
import 'package:memories_core/src/upload/key.dart';
import 'package:pinenacl/ed25519.dart';

/// One request that the fake site got.
class Call {
  Call(this.method, this.path, this.headers, this.body);

  final String method;
  final String path;
  final Map<String, String> headers;
  final Uint8List body;

  String get label => '$method $path';

  Object? get json => jsonDecode(utf8.decode(body));

  /// The JSON of a gzip upload body.
  Map<String, Object?> get uploadJson =>
      jsonDecode(utf8.decode(gzip.decode(body))) as Map<String, Object?>;
}

class Reply {
  const Reply(this.status, [this.body = '', this.headers = const {}]);

  Reply.json(this.status, Object? json, [this.headers = const {}])
    : body = jsonEncode(json);

  Reply.error(
    this.status,
    String code,
    String message, {
    List<Object?>? problems,
  }) : body = jsonEncode({
         'error': code,
         'message': message,
         'problems': ?problems,
       }),
       headers = const {};

  final int status;
  final String body;
  final Map<String, String> headers;
}

/// A website in a `dart:io` server. It checks the signature of each signed
/// request like the real server, records each call, and answers like the
/// real API unless a test puts a [Reply] in [overrides] for `METHOD path`.
class FakeSite {
  FakeSite._(this._server) {
    _server.listen(_serve);
  }

  static Future<FakeSite> start() async =>
      FakeSite._(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));

  final HttpServer _server;
  final List<Call> calls = [];
  final Map<String, Reply> overrides = {};
  final Set<String> registered = {};
  final Map<String, Map<String, Object?>> characters = {};
  final Map<String, List<String>> shotFiles = {};
  final Map<String, String> _shotHashes = {};

  /// The screenshot state that `GET /me` gives. Any state but `approved`
  /// deletes the stored screenshots, as the real server does.
  String get screenshots => _screenshots;
  set screenshots(String value) {
    _screenshots = value;
    if (value != 'approved') {
      shotFiles.clear();
      _shotHashes.clear();
    }
  }

  String _screenshots = 'none';

  /// The invite code that registration needs, or null in open mode.
  String? invite;

  Uri get uri => Uri.parse('http://127.0.0.1:${_server.port}');

  Future<void> close() => _server.close(force: true);

  List<Call> callsTo(String label) =>
      calls.where((c) => c.label == label).toList();

  Future<void> _serve(HttpRequest req) async {
    final body = Uint8List.fromList(
      await req.fold<List<int>>([], (a, b) => a..addAll(b)),
    );
    final headers = <String, String>{};
    req.headers.forEach((k, v) => headers[k.toLowerCase()] = v.join(','));
    final path = req.uri.toString();
    final call = Call(req.method, path, headers, body);
    calls.add(call);
    final reply = overrides[call.label] ?? _answer(call);
    req.response.statusCode = reply.status;
    reply.headers.forEach(req.response.headers.set);
    req.response.write(reply.body);
    await req.response.close();
  }

  Reply _answer(Call c) {
    if (c.path == '/api/v1/info') {
      return Reply.json(200, {
        'api': 1,
        'name': 'Fake site',
        'registration': invite == null ? 'open' : 'invite',
      });
    }
    final bad = _checkSignature(c);
    if (bad != null) return bad;
    final key = c.headers['memories-key']!;
    if (c.path == '/api/v1/register') {
      final code = (c.json as Map<String, Object?>)['invite'];
      if (invite != null && code != invite && !registered.contains(key)) {
        return Reply.error(
          403,
          'invite_invalid',
          'This invite code is not valid.',
        );
      }
      return Reply.json(registered.add(key) ? 201 : 200, {'registered': true});
    }
    if (!registered.contains(key)) {
      return Reply.error(401, 'not_registered', 'This key is not registered.');
    }
    if (c.method == 'GET' && c.path == '/api/v1/me') {
      return Reply.json(200, {
        'screenshots': screenshots,
        'characters': [
          for (final e in characters.entries)
            {
              'path': e.key,
              'url': '$uri/${e.key}/',
              'guid': e.value['guid'],
              'steps': 3,
              'updated': 1,
            },
        ],
      });
    }
    if (c.path == '/api/v1/screenshots/request') {
      if (screenshots == 'none' || screenshots == 'denied') {
        screenshots = 'pending';
      }
      return Reply.json(200, {'screenshots': screenshots});
    }
    if (c.method == 'POST' && c.path == '/api/v1/characters') {
      if (c.headers['content-encoding'] != 'gzip') {
        return Reply.error(415, 'gzip_required', 'Send gzip.');
      }
      final json = c.uploadJson;
      final ch = json['character']! as Map<String, Object?>;
      final path = [
        slug(ch['flavor']! as String),
        (ch['region']! as String).toLowerCase(),
        slug(ch['realm']! as String),
        slug(ch['name']! as String),
      ].join('/');
      final before = (characters[path]?['steps'] as int?) ?? 0;
      final steps = (json['journey']! as List<Object?>).length;
      characters[path] = {...ch, 'steps': steps};
      return Reply.json(200, {
        'path': path,
        'url': '$uri/$path/',
        'steps': steps,
        'added': steps - before,
      });
    }
    const prefix = '/api/v1/characters/';
    if (c.path.startsWith(prefix)) {
      final rest = c.path.substring(prefix.length);
      if (c.method == 'DELETE') {
        return characters.remove(rest) == null
            ? Reply.error(404, 'not_found', 'No such character.')
            : const Reply(204);
      }
      final i = rest.indexOf('/screenshots/');
      if (c.method == 'PUT' && i > 0) {
        if (screenshots != 'approved') {
          return Reply.error(403, 'screenshots_not_approved', 'Not approved.');
        }
        final files = shotFiles.putIfAbsent(rest.substring(0, i), () => []);
        final file = rest.substring(i + '/screenshots/'.length);
        final sum = sha256.convert(c.body).toString();
        if (_shotHashes[rest] == sum) return Reply.json(200, {'file': file});
        _shotHashes[rest] = sum;
        if (!files.contains(file)) files.add(file);
        return Reply.json(201, {'file': file});
      }
    }
    return Reply.error(404, 'not_found', 'No such route.');
  }

  /// The check of the real server, except for the clock window.
  Reply? _checkSignature(Call c) {
    final h = c.headers;
    Reply fail(String why) => Reply.error(401, 'bad_signature', why);
    final key = h['memories-key'];
    final time = h['memories-time'];
    final nonce = h['memories-nonce'];
    final sig = h['memories-signature'];
    if (key == null || time == null || nonce == null || sig == null) {
      return fail('A signature header is missing.');
    }
    final signed = [
      'memories-v1',
      c.method,
      c.path,
      time,
      nonce,
      sha256.convert(c.body).toString(),
    ].join('\n');
    try {
      if (unb64(nonce).length != 16) return fail('Bad nonce.');
      VerifyKey(unb64(key)).verify(
        signature: Signature(unb64(sig)),
        message: Uint8List.fromList(utf8.encode(signed)),
      );
    } on Object {
      return fail('The signature is wrong.');
    }
    return null;
  }
}
