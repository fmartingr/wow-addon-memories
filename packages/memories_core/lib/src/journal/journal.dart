/// Unpacks and decodes the journal and trail data of the Memories saved files.
library;

import '../savedvars/lexer.dart' show goQuote;

/// One named field of a kind. A numeric field holds a number.
class Field {
  const Field(this.name, {required this.numeric});

  final String name;
  final bool numeric;
}

/// The fields of one journal kind.
class Kind {
  const Kind(this.addon, this.group, [this.fields = const []]);

  final String addon;
  final String group;
  final List<Field> fields;
}

/// Maps a kind to its description.
typedef Kinds = Map<String, Kind>;

/// One decoded journal line. Dart has its own `Record` type, so this one has another name.
extension type JournalRecord(Map<String, Object?> fields)
    implements Map<String, Object?> {
  /// The time of the record, or 0 when it has none.
  int get time => asInt(this['t']) ?? 0;

  /// A text field, or "" when it is missing or not text.
  String text(String key) {
    final v = this[key];
    return v is String ? v : '';
  }
}

/// A line with fewer than 6 columns.
class ShortLineException implements Exception {
  const ShortLineException();

  @override
  String toString() => 'fewer than 6 columns';
}

/// A line whose time column is not a whole number.
class BadTimeException implements Exception {
  const BadTimeException(this.text);

  final String text;

  @override
  String toString() => 'the time is not a whole number: ${goQuote(text)}';
}

/// A trail chunk that cannot be decoded.
class BadChunkException implements Exception {
  const BadChunkException([this.detail]);

  final String? detail;

  @override
  String toString() =>
      detail == null ? 'bad trail chunk' : 'bad trail chunk: $detail';
}

final RegExp _numberPattern = RegExp(
  r'^-?[0-9]+(\.[0-9]+)?([eE][-+]?[0-9]+)?$',
);
final RegExp _wholePattern = RegExp(r'^[-+]?[0-9]+$');

/// The keys of a record that are not fields of its kind. The addon reserves only
/// the fixed columns, so a field with another of these names goes into "extra".
const Set<String> _reserved = {
  't', 'p', 'm', 'x', 'y', 'k', //
  'extra', 'addon', 'session', 'screenshot', 'notes',
};

/// Reads a decimal whole number of 64 bits, with an optional sign. Dart's own
/// parser also reads spaces and hex, which the saved files never hold.
int? parseInt64(String s) => _wholePattern.hasMatch(s) ? int.tryParse(s) : null;

/// Reads MemoriesDB.kinds, where each value is "addon;group;f1,#f2,...".
Kinds parseKinds(Object? v) {
  final out = <String, Kind>{};
  if (v is! Map<String, Object?>) return out;
  v.forEach((kind, raw) {
    if (raw is! String) return;
    final first = raw.indexOf(';');
    final second = first < 0 ? -1 : raw.indexOf(';', first + 1);
    if (second < 0) return;
    final spec = raw.substring(second + 1);
    final fields = <Field>[];
    if (spec.isNotEmpty) {
      for (final f in spec.split(',')) {
        final name = f.startsWith('#') ? f.substring(1) : f;
        fields.add(Field(name, numeric: name != f));
      }
    }
    out[kind] = Kind(
      raw.substring(0, first),
      raw.substring(first + 1, second),
      fields,
    );
  });
  return out;
}

/// Returns the values of a Lua list. The parser turns an empty table, or one with gaps, into a map.
List<Object?> asList(Object? v) {
  if (v is List<Object?>) return v;
  if (v is Map<String, Object?>) {
    final keys = <int>[];
    for (final k in v.keys) {
      final n = parseInt64(k);
      if (n != null) keys.add(n);
    }
    keys.sort();
    return [for (final k in keys) v['$k']];
  }
  return const [];
}

/// Returns the lines of a journal log: every chunk split on "\n", then the open lines.
List<String> journalLines(Object? log) {
  if (log is! Map<String, Object?>) return const [];
  final out = <String>[];
  for (final c in asList(log['chunks'])) {
    if (c is String && c.isNotEmpty) out.addAll(c.split('\n'));
  }
  for (final l in asList(log['open'])) {
    if (l is String) out.add(l);
  }
  return out;
}

/// Parses the text of a numeric field: an `int` when it fits 64 bits, else a
/// `double`. It refuses hex, NaN, infinities and other forms that JSON cannot hold.
num? parseNumber(String s) {
  if (!_numberPattern.hasMatch(s)) return null;
  final n = int.tryParse(s);
  if (n != null) return n;
  final f = double.tryParse(s);
  if (f == null || f.isInfinite) return null;
  return f;
}

/// Reads a whole number from a saved-file value or a JSON value.
int? asInt(Object? v) {
  if (v is int) return v;
  if (v is double &&
      v == v.truncateToDouble() &&
      v.abs() < 9007199254740992.0) {
    return v.toInt();
  }
  return null;
}

/// Turns a line "t|p|m|x|y|kind|f1|..." into a record. Named fields come from
/// [kinds]; an empty field is left out; a value past the known fields, or text
/// in a numeric field, goes into "extra" under its 1-based field number.
JournalRecord decodeLine(String line, Kinds kinds) {
  final cols = line.split('|');
  if (cols.length < 6) throw const ShortLineException();
  final t = parseInt64(cols[0]);
  if (t == null) throw BadTimeException(cols[0]);
  final rec = <String, Object?>{'t': t, 'k': cols[5]};
  const fixedNames = ['p', 'm', 'x', 'y'];
  for (var i = 0; i < fixedNames.length; i++) {
    rec[fixedNames[i]] = _fixed(cols[i + 1]);
  }
  final fields = kinds[cols[5]]?.fields ?? const <Field>[];
  Map<String, Object?>? extra;
  for (var i = 0; i < cols.length - 6; i++) {
    final v = cols[6 + i];
    if (v.isEmpty) continue;
    if (i >= fields.length || _reserved.contains(fields[i].name)) {
      (extra ??= {})['${i + 1}'] = v;
      continue;
    }
    final f = fields[i];
    if (!f.numeric) {
      rec[f.name] = v;
      continue;
    }
    final n = parseNumber(v);
    if (n != null) {
      rec[f.name] = n;
    } else {
      (extra ??= {})['${i + 1}'] = v;
    }
  }
  if (extra != null) rec['extra'] = extra;
  return JournalRecord(rec);
}

Object? _fixed(String s) {
  if (s.isEmpty) return null;
  return parseNumber(s) ?? s;
}
