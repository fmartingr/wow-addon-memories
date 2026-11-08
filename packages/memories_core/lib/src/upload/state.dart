/// What the upload remembers between runs, one record for each website.
library;

import 'dart:convert';
import 'dart:io';

import '../gather/files.dart' show writeAtomic;

/// What one website has received from this computer.
class SiteState {
  SiteState({
    this.registered = false,
    this.screenshotsApproved = false,
    Map<String, String>? sent,
    Map<String, Map<String, String>>? shots,
  }) : sent = sent ?? {},
       shots = shots ?? {};

  /// Reads one site record, and falls back to the default of each field that
  /// is missing or of another type.
  factory SiteState.fromJson(Object? json) {
    if (json is! Map<String, Object?>) return SiteState();
    final shots = <String, Map<String, String>>{};
    final rawShots = json['shots'];
    if (rawShots is Map<String, Object?>) {
      for (final e in rawShots.entries) {
        shots[e.key] = _stringMap(e.value);
      }
    }
    return SiteState(
      registered: json['registered'] == true,
      screenshotsApproved: json['screenshotsApproved'] == true,
      sent: _stringMap(json['sent']),
      shots: shots,
    );
  }

  /// Whether this key registered on the site.
  bool registered;

  /// Whether the site had approved screenshots when the characters were last
  /// sent. A site stores the screenshot field of a record only for an
  /// approved key, so an approval that comes later makes every character go
  /// out again.
  bool screenshotsApproved;

  /// The SHA-256 of the last body sent for each character path.
  final Map<String, String> sent;

  /// The SHA-256 of each screenshot file sent, by character path and file.
  final Map<String, Map<String, String>> shots;

  /// Forgets what was sent for the character at [path].
  void forget(String path) {
    sent.remove(path);
    shots.remove(path);
  }

  Map<String, Object?> toJson() => {
    'registered': registered,
    'screenshotsApproved': screenshotsApproved,
    'sent': sent,
    'shots': shots,
  };
}

Map<String, String> _stringMap(Object? v) => {
  if (v is Map<String, Object?>)
    for (final e in v.entries)
      if (e.value is String) e.key: e.value! as String,
};

/// The state file. Each site address has its own [SiteState].
class UploadState {
  UploadState._(this._sites, this.warning);

  /// A state with no site.
  UploadState.empty() : this._({}, null);

  /// Reads [file]. A missing file gives an empty state. A damaged file gives
  /// an empty state with a [warning], and the next [save] replaces it.
  factory UploadState.load(File file) {
    if (!file.existsSync()) return UploadState.empty();
    try {
      final json = jsonDecode(utf8.decode(file.readAsBytesSync()));
      if (json is Map<String, Object?> &&
          json['v'] == 1 &&
          json['sites'] is Map<String, Object?>) {
        final sites = <String, SiteState>{};
        for (final e in (json['sites']! as Map<String, Object?>).entries) {
          sites[e.key] = SiteState.fromJson(e.value);
        }
        return UploadState._(sites, null);
      }
    } on FormatException {
      // Falls through to the warning below.
    }
    return UploadState._(
      {},
      'The state file ${file.path} is damaged, so every character will be '
      'sent again.',
    );
  }

  final Map<String, SiteState> _sites;

  /// A plain message when [UploadState.load] had to start fresh.
  final String? warning;

  /// The record of [site], made on the first use.
  SiteState site(Uri site) =>
      _sites.putIfAbsent(site.toString(), SiteState.new);

  /// Writes the state through a temporary file and a rename.
  void save(File file) {
    final json = {
      'v': 1,
      'sites': {for (final e in _sites.entries) e.key: e.value.toJson()},
    };
    writeAtomic(file.path, utf8.encode('${jsonEncode(json)}\n'));
  }
}
