/// Character ids: the slug of the region, realm and name, kept unique.
library;

import 'package:unorm_dart/unorm_dart.dart' as unorm;

final RegExp _nonSlug = RegExp('[^a-z0-9]+');
final RegExp _portalPattern = RegExp(r'SET portal "(\w+)"');
final RegExp _dashes = RegExp(r'^-+|-+$');

/// The form of every character id, so an id is always safe as a folder name.
final RegExp idPattern = RegExp(r'^[a-z0-9]+(-[a-z0-9]+)*$');

/// Returns the NFKD-normalized ASCII text in lower case, with each run of
/// other characters replaced by "-".
String slug(String s) {
  final ascii = String.fromCharCodes(
    unorm.nfkd(s).runes.where((r) => r < 0x80),
  );
  return ascii.toLowerCase().replaceAll(_nonSlug, '-').replaceAll(_dashes, '');
}

/// Reads the region from the text of WTF/Config.wtf, or "xx" when it has none.
String region(String config) {
  final m = _portalPattern.firstMatch(config);
  if (m != null && slug(m[1]!).isNotEmpty) return slug(m[1]!);
  return 'xx';
}

/// `<region>-<realm slug>-<name slug>`, or `<region>-<guid slug>` when the
/// name has no slug.
String baseId(String region, String realm, String name, String guid) {
  if (slug(name).isEmpty) return _joinNonEmpty([region, slug(guid)]);
  return _joinNonEmpty([region, slug(realm), slug(name)]);
}

String _joinNonEmpty(List<String> parts) =>
    parts.where((s) => s.isNotEmpty).join('-');

/// The ids that [assignId] tries first, in order. After them it tries the
/// GUID id with a number from 2.
({String withGuid, List<String> ids}) _candidates(
  String base,
  String flavor,
  String guid,
) {
  final withGuid = _joinNonEmpty([base, slug(guid)]);
  return (
    withGuid: withGuid,
    ids: [
      base,
      _joinNonEmpty([base, slug(flavor)]),
      withGuid,
    ],
  );
}

final RegExp _counter = RegExp(r'^[1-9][0-9]*$');

/// Reports whether [assignId] could give [id] to a character with this base
/// id, flavor and GUID.
bool isCandidate(String id, String base, String flavor, String guid) {
  final c = _candidates(base, flavor, guid);
  if (c.ids.contains(id)) return true;
  final prefix = '${c.withGuid}-';
  if (!id.startsWith(prefix)) return false;
  final n = id.substring(prefix.length);
  final i = _counter.hasMatch(n) ? int.tryParse(n) : null;
  return i != null && i >= 2;
}

/// Gives a character its id: the base id, else the base id with the flavor,
/// else with the GUID. [taken] maps each id given so far to its GUID. Two
/// GUIDs with the same slug get a number after the GUID.
String assignId(
  Map<String, String> taken,
  String base,
  String flavor,
  String guid,
) {
  final c = _candidates(base, flavor, guid);
  var ids = c.ids;
  for (var n = 2; ; n++) {
    for (final id in ids) {
      final owner = taken[id];
      if (owner == null || owner == guid) {
        taken[id] = guid;
        return id;
      }
    }
    ids = ['${c.withGuid}-$n'];
  }
}
