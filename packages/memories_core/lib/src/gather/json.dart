/// A JSON writer that gives the same text as Go's `encoding/json` encoder with
/// `SetEscapeHTML(false)`, and a reader for the files of an earlier gather.
library;

import 'dart:convert';

/// A value written as a JSON object with its fields in their declared order,
/// as Go writes a struct. A plain [Map] is written with sorted keys.
abstract interface class GoStruct {
  Map<String, Object?> get goFields;
}

/// Wraps an ordered map so that it is written in its insertion order.
class Ordered implements GoStruct {
  const Ordered(this.goFields);

  @override
  final Map<String, Object?> goFields;
}

/// Encodes [value] as one JSON document with a final newline. With [indent]
/// each level is indented by one space.
String encodeJson(Object? value, {bool indent = false}) {
  final out = StringBuffer();
  _write(out, value, indent ? '\n' : null);
  out.write('\n');
  return out.toString();
}

/// [encodeJson] as UTF-8 bytes.
List<int> encodeJsonBytes(Object? value, {bool indent = false}) =>
    utf8.encode(encodeJson(value, indent: indent));

void _write(StringBuffer out, Object? v, String? newline) {
  switch (v) {
    case null:
      out.write('null');
    case bool():
      out.write(v ? 'true' : 'false');
    case int():
      out.write(v);
    case double():
      out.write(formatGoFloat(v));
    case String():
      writeGoString(out, v);
    case GoStruct():
      _writeObject(out, v.goFields.entries.toList(), newline);
    case Map<Object?, Object?>():
      final entries = <MapEntry<String, Object?>>[];
      for (final e in v.entries) {
        final k = e.key;
        if (k is! String) {
          throw ArgumentError('a JSON object key is not text: $k');
        }
        entries.add(MapEntry(k, e.value));
      }
      entries.sort((a, b) => compareUtf8(a.key, b.key));
      _writeObject(out, entries, newline);
    case List<Object?>():
      if (v.isEmpty) {
        out.write('[]');
        return;
      }
      final inner = newline == null ? null : '$newline ';
      out.write('[');
      for (var i = 0; i < v.length; i++) {
        if (i > 0) out.write(',');
        if (inner != null) out.write(inner);
        _write(out, v[i], inner);
      }
      if (newline != null) out.write(newline);
      out.write(']');
    default:
      throw ArgumentError('JSON cannot hold a ${v.runtimeType}');
  }
}

void _writeObject(
  StringBuffer out,
  List<MapEntry<String, Object?>> entries,
  String? newline,
) {
  if (entries.isEmpty) {
    out.write('{}');
    return;
  }
  final inner = newline == null ? null : '$newline ';
  out.write('{');
  for (var i = 0; i < entries.length; i++) {
    if (i > 0) out.write(',');
    if (inner != null) out.write(inner);
    writeGoString(out, entries[i].key);
    out.write(inner == null ? ':' : ': ');
    _write(out, entries[i].value, inner);
  }
  if (newline != null) out.write(newline);
  out.write('}');
}

const String _hex = '0123456789abcdef';

/// Writes [s] as a JSON string the way Go escapes it with HTML escaping off.
/// A lone surrogate cannot be UTF-8, so it becomes U+FFFD, as Go's decoder
/// turns it into U+FFFD when it reads the earlier files.
void writeGoString(StringBuffer out, String s) {
  out.write('"');
  for (var i = 0; i < s.length; i++) {
    final c = s.codeUnitAt(i);
    switch (c) {
      case 0x22:
        out.write(r'\"');
      case 0x5c:
        out.write(r'\\');
      case 0x08:
        out.write(r'\b');
      case 0x0c:
        out.write(r'\f');
      case 0x0a:
        out.write(r'\n');
      case 0x0d:
        out.write(r'\r');
      case 0x09:
        out.write(r'\t');
      case 0x2028:
        out.write('\\u2028');
      case 0x2029:
        out.write('\\u2029');
      default:
        if (c < 0x20) {
          out
            ..write(r'\u00')
            ..write(_hex[c >> 4])
            ..write(_hex[c & 0xf]);
        } else if (c >= 0xd800 && c <= 0xdbff) {
          final paired =
              i + 1 < s.length &&
              s.codeUnitAt(i + 1) >= 0xdc00 &&
              s.codeUnitAt(i + 1) <= 0xdfff;
          if (paired) {
            out
              ..writeCharCode(c)
              ..writeCharCode(s.codeUnitAt(++i));
          } else {
            out.writeCharCode(0xfffd);
          }
        } else if (c >= 0xdc00 && c <= 0xdfff) {
          out.writeCharCode(0xfffd);
        } else {
          out.writeCharCode(c);
        }
    }
  }
  out.write('"');
}

/// Formats a double like Go's JSON encoder: the shortest digits that read
/// back to the same value, in plain notation, unless the value is below 1e-6
/// or at least 1e21. Go writes a whole double with no ".0".
String formatGoFloat(double f) {
  if (f.isNaN || f.isInfinite) {
    throw ArgumentError('JSON cannot hold $f');
  }
  if (f == 0) return f.isNegative ? '-0' : '0';
  final sign = f < 0 ? '-' : '';
  final abs = f.abs();
  final parts = abs.toStringAsExponential().split('e');
  final digits = parts[0].replaceAll('.', '');
  final exp = int.parse(parts[1]);
  if (abs < 1e-6 || abs >= 1e21) {
    final mantissa = digits.length > 1
        ? '${digits[0]}.${digits.substring(1)}'
        : digits;
    return '$sign${mantissa}e${exp < 0 ? '-' : '+'}${exp.abs()}';
  }
  if (exp < 0) return '${sign}0.${'0' * (-exp - 1)}$digits';
  if (digits.length <= exp + 1) {
    return '$sign$digits${'0' * (exp + 1 - digits.length)}';
  }
  return '$sign${digits.substring(0, exp + 1)}.${digits.substring(exp + 1)}';
}

/// Compares two strings by their UTF-8 bytes, the order of Go strings. UTF-16
/// puts the surrogates of U+10000 and above before U+E000 to U+FFFF.
int compareUtf8(String a, String b) {
  final n = a.length < b.length ? a.length : b.length;
  for (var i = 0; i < n; i++) {
    final x = a.codeUnitAt(i);
    final y = b.codeUnitAt(i);
    if (x == y) continue;
    if (x >= 0xd800 && y >= 0xd800) return _fixUp(x) - _fixUp(y);
    return x - y;
  }
  return a.length - b.length;
}

int _fixUp(int c) => c >= 0xe000 ? c - 0x800 : c + 0x2000;
