/// The Ed25519 key that identifies this computer to a website.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:pinenacl/ed25519.dart';

/// A key file that cannot be read or that holds no valid key.
class UploadKeyException implements Exception {
  const UploadKeyException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Encodes bytes as base64url with no padding, the form of every binary value
/// of the protocol.
String b64(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');

/// Decodes base64url text with or without padding.
Uint8List unb64(String text) =>
    Uint8List.fromList(base64Url.decode(base64Url.normalize(text)));

/// The key pair of this computer. The private seed stays in a file on disk.
class UploadKey {
  UploadKey._(this._seed) : _signing = SigningKey.fromSeed(_seed);

  /// Makes a new key from 32 secure random bytes.
  factory UploadKey.generate() {
    final random = Random.secure();
    return UploadKey._(
      Uint8List.fromList(List<int>.generate(32, (_) => random.nextInt(256))),
    );
  }

  /// Makes the key of a known 32-byte [seed].
  factory UploadKey.fromSeed(List<int> seed) {
    if (seed.length != 32) {
      throw const UploadKeyException('The key seed is not 32 bytes long.');
    }
    return UploadKey._(Uint8List.fromList(seed));
  }

  /// Reads a key file written by [save]. A missing file is a
  /// [FileSystemException]; a damaged one is an [UploadKeyException].
  factory UploadKey.load(File file) {
    final bytes = file.readAsBytesSync();
    try {
      final json = jsonDecode(utf8.decode(bytes));
      if (json is Map<String, Object?> &&
          json['v'] == 1 &&
          json['seed'] is String) {
        return UploadKey.fromSeed(unb64(json['seed']! as String));
      }
    } on FormatException {
      // Falls through to the damaged-file error below.
    } on UploadKeyException {
      // Same message as any other damaged key file.
    }
    throw UploadKeyException(
      'The key file ${file.path} is damaged. Restore it from a copy. It is '
      'never overwritten, because a new key would lose the characters that '
      'the old key owns.',
    );
  }

  final Uint8List _seed;
  final SigningKey _signing;

  /// The public key, base64url with no padding.
  String get publicKey => b64(_signing.verifyKey.asTypedList);

  /// The first 16 hex characters of the SHA-256 of the public key.
  String get fingerprint => sha256
      .convert(_signing.verifyKey.asTypedList)
      .toString()
      .substring(0, 16);

  /// Signs [message] and returns the 64-byte signature.
  Uint8List sign(List<int> message) =>
      Uint8List.fromList(_signing.sign(Uint8List.fromList(message)).signature);

  /// Writes the key file through a temporary file and a rename. The temporary
  /// file sits in a new folder that only the owner can enter (mode 700 on
  /// Linux and macOS), so no other account can open it in the moment before
  /// its own mode becomes 600 and the seed is written.
  void save(File file) {
    final dir = file.parent;
    dir.createSync(recursive: true);
    final tmpDir = dir.createTempSync('.${p.basename(file.path)}.');
    try {
      _ownerOnly('700', tmpDir.path);
      final tmp = File(p.join(tmpDir.path, 'key.json'))
        ..createSync(exclusive: true);
      _ownerOnly('600', tmp.path);
      tmp.writeAsStringSync(
        '${jsonEncode({'v': 1, 'seed': b64(_seed)})}\n',
        flush: true,
      );
      tmp.renameSync(file.path);
    } finally {
      tmpDir.deleteSync(recursive: true);
    }
  }

  static void _ownerOnly(String mode, String path) {
    if (!Platform.isLinux && !Platform.isMacOS) return;
    final ProcessResult r;
    try {
      r = Process.runSync('chmod', [mode, path]);
    } on ProcessException catch (e) {
      throw UploadKeyException(
        'Could not restrict the key file to its owner: ${e.message}',
      );
    }
    if (r.exitCode != 0) {
      throw UploadKeyException(
        'Could not restrict the key file to its owner: ${r.stderr}',
      );
    }
  }
}
