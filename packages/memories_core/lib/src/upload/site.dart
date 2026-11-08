/// The address of the website that gets the uploads.
library;

final RegExp _hostPattern = RegExp(
  r'^([a-z0-9]([a-z0-9-]*[a-z0-9])?\.)*[a-z0-9]([a-z0-9-]*[a-z0-9])?$|'
  r'^[0-9a-f:.]+$',
);

const Set<String> _loopbackHosts = {'localhost', '127.0.0.1', '::1'};

/// Reads a website address: `https://host[:port]`, or `http://` for
/// `localhost`, `127.0.0.1` and `[::1]` only. A trailing "/" is dropped.
/// Throws a [FormatException] with a plain message for any other address.
Uri parseSite(String text) {
  final trimmed = text.trim();
  final Uri uri;
  try {
    uri = Uri.parse(trimmed);
  } on FormatException {
    throw const FormatException(
      'The website address is not valid. Write it like https://example.com.',
    );
  }
  if (!uri.hasScheme || uri.host.isEmpty) {
    throw const FormatException(
      'The website address needs a scheme and a host, like https://example.com.',
    );
  }
  if (!_hostPattern.hasMatch(uri.host.toLowerCase())) {
    throw const FormatException(
      'The website address is not valid. Write it like https://example.com.',
    );
  }
  final scheme = uri.scheme.toLowerCase();
  if (scheme != 'https' && scheme != 'http') {
    throw const FormatException(
      'The website address must start with https://.',
    );
  }
  final host = uri.host.toLowerCase();
  if (scheme == 'http' && !_loopbackHosts.contains(host)) {
    throw const FormatException(
      'The website address must start with https://. Plain http:// is only '
      'allowed for localhost, 127.0.0.1 and [::1].',
    );
  }
  if (uri.userInfo.isNotEmpty) {
    throw const FormatException(
      'The website address may not hold a user name or a password.',
    );
  }
  if (uri.hasQuery || uri.hasFragment) {
    throw const FormatException(
      'The website address may not hold a query or a fragment.',
    );
  }
  if (uri.path.isNotEmpty && uri.path != '/') {
    throw const FormatException(
      'The website address may not hold a path. Use the address of the site '
      'itself, like https://example.com.',
    );
  }
  return Uri(scheme: scheme, host: host, port: uri.hasPort ? uri.port : null);
}
