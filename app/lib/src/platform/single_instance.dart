/// One running copy of the app: a later start shows the window of the first
/// one and ends.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

/// What [SingleInstance.claim] found.
sealed class InstanceClaim {
  const InstanceClaim();
}

/// This is the only copy. [showRequests] fires when a later copy asks for
/// the window; it takes one listener and keeps the requests until then.
abstract class FirstInstance extends InstanceClaim {
  const FirstInstance();

  Stream<void> get showRequests;

  /// Gives up the lock, so that a later copy runs.
  Future<void> release();
}

/// Another copy runs. [answered] tells whether it took the request to show
/// its window.
class OtherInstance extends InstanceClaim {
  const OtherInstance({required this.answered});

  final bool answered;
}

/// Finds out whether another copy of the app runs.
abstract interface class SingleInstance {
  Future<InstanceClaim> claim();
}

/// An exclusive lock on `instance.lock` in [directory]. The first copy
/// listens on a loopback port and writes the port and a random token into
/// the lock file; a later copy sends `show <token>` there and waits for `ok`.
class FileSingleInstance implements SingleInstance {
  FileSingleInstance(
    this.directory, {
    this.timeout = const Duration(seconds: 2),
  });

  /// The folder of the lock file, such as the application support folder.
  final Future<String> Function() directory;

  /// How long a later copy waits for the first one to answer.
  final Duration timeout;

  // The OS lock is per process on Linux and macOS, so a second claim in this
  // process would get it again; this set closes that gap.
  static final Set<String> _held = {};

  // Windows locks are mandatory, so the lock covers a byte past the port
  // and token, which a later copy must still read.
  static const int _lockStart = 4096;

  /// The longest line that either side reads.
  static const int _maxLine = 256;

  @override
  Future<InstanceClaim> claim() async {
    final dir = await directory();
    await Directory(dir).create(recursive: true);
    final path = p.join(dir, 'instance.lock');
    if (_held.contains(path)) return _askFirst(path);
    // Append does not cut the file, which the first copy may still use.
    final file = await File(path).open(mode: FileMode.append);
    try {
      await file.lock(FileLock.exclusive, _lockStart, _lockStart + 1);
    } on FileSystemException catch (e) {
      await file.close();
      if (_heldElsewhere(e)) return _askFirst(path);
      rethrow;
    }
    _held.add(path);
    try {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final token = _token();
      await file.truncate(0);
      await file.setPosition(0);
      await file.writeString('${server.port} $token\n');
      await file.flush();
      return _First(path, file, server, token, timeout);
    } catch (_) {
      _held.remove(path);
      await file.close();
      rethrow;
    }
  }

  // EACCES and EAGAIN (11 on Linux, 35 on macOS) from fcntl, and
  // ERROR_LOCK_VIOLATION from LockFileEx, mean another holder.
  static bool _heldElsewhere(FileSystemException e) {
    final code = e.osError?.errorCode;
    if (code == null) return false;
    if (Platform.isWindows) return code == 33;
    return code == 13 || code == (Platform.isMacOS ? 35 : 11);
  }

  static String _token() {
    final random = Random.secure();
    return [for (var i = 0; i < 16; i++) random.nextInt(256).toRadixString(16)]
        .map((h) => h.padLeft(2, '0'))
        .join();
  }

  /// Asks the copy that holds the lock to show its window. The first copy
  /// may not have written its port yet, so this reads the file again until
  /// [timeout].
  Future<OtherInstance> _askFirst(String path) async {
    final deadline = DateTime.now().add(timeout);
    while (true) {
      final left = deadline.difference(DateTime.now());
      if (left <= Duration.zero) return const OtherInstance(answered: false);
      final target = await _readTarget(path);
      if (target != null && await _send(target.$1, target.$2, left)) {
        return const OtherInstance(answered: true);
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  static Future<(int, String)?> _readTarget(String path) async {
    try {
      final text = await File(path).readAsString();
      final m = RegExp(r'^(\d{1,5}) ([0-9a-f]{32})\n').firstMatch(text);
      if (m == null) return null;
      final port = int.parse(m[1]!);
      return port > 0 && port < 65536 ? (port, m[2]!) : null;
    } on FileSystemException {
      return null;
    }
  }

  static Future<bool> _send(int port, String token, Duration left) async {
    Socket? socket;
    try {
      socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        port,
        timeout: left,
      );
      socket.write('show $token\n');
      await socket.flush();
      return await readLine(socket, left) == 'ok';
    } on Object {
      return false;
    } finally {
      socket?.destroy();
    }
  }

  /// The first line that [socket] sends, or null when it sends none within
  /// [limit], closes first, or sends more than [_maxLine] bytes.
  static Future<String?> readLine(Socket socket, Duration limit) {
    final done = Completer<String?>();
    final bytes = <int>[];
    void finish(String? line) {
      if (!done.isCompleted) done.complete(line);
    }

    final sub = socket.listen(
      (data) {
        bytes.addAll(data);
        final end = bytes.indexOf(10);
        if (end >= 0 && end <= _maxLine) {
          finish(utf8.decode(bytes.sublist(0, end), allowMalformed: true));
        } else if (bytes.length > _maxLine) {
          finish(null);
        }
      },
      onError: (Object _) => finish(null),
      onDone: () => finish(null),
      cancelOnError: true,
    );
    return done.future
        .timeout(limit, onTimeout: () => null)
        .whenComplete(sub.cancel);
  }
}

class _First extends FirstInstance {
  _First(this._path, this._file, this._server, this._token, this._timeout) {
    _server.listen(_serve);
  }

  final String _path;
  final RandomAccessFile _file;
  final ServerSocket _server;
  final String _token;
  final Duration _timeout;
  // A single-subscription stream keeps a request that arrives before the app
  // listens, between claim and the first build, as the later copy already
  // got `ok` and ended.
  final StreamController<void> _show = StreamController();
  bool _released = false;

  @override
  Stream<void> get showRequests => _show.stream;

  Future<void> _serve(Socket socket) async {
    try {
      final line = await FileSingleInstance.readLine(socket, _timeout);
      if (line != 'show $_token' || _released) return;
      _show.add(null);
      socket.write('ok\n');
      await socket.flush();
    } on Object {
      // A peer that went away gets no answer.
    } finally {
      socket.destroy();
    }
  }

  @override
  Future<void> release() async {
    if (_released) return;
    _released = true;
    await _server.close();
    // The close of a stream that nobody listens to never completes.
    unawaited(_show.close());
    FileSingleInstance._held.remove(_path);
    try {
      await _file.unlock(
        FileSingleInstance._lockStart,
        FileSingleInstance._lockStart + 1,
      );
    } finally {
      await _file.close();
    }
  }
}
