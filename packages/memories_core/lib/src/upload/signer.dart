/// The signature headers of a request, as the Protocol of the upload backend
/// defines them.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'key.dart';

/// Builds the 4 headers of a signed request. [pathAndQuery] is the request
/// path with its query, exactly as sent. [nonce] is 16 random bytes.
Map<String, String> signRequest(
  UploadKey key,
  String method,
  String pathAndQuery,
  List<int> body,
  DateTime now,
  List<int> nonce,
) {
  final time = (now.millisecondsSinceEpoch ~/ 1000).toString();
  final nonceText = b64(nonce);
  final signed = [
    'memories-v1',
    method.toUpperCase(),
    pathAndQuery,
    time,
    nonceText,
    sha256.convert(body).toString(),
  ].join('\n');
  return {
    'Memories-Key': key.publicKey,
    'Memories-Time': time,
    'Memories-Nonce': nonceText,
    'Memories-Signature': b64(key.sign(utf8.encode(signed))),
  };
}
