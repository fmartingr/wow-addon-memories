import 'dart:typed_data';

import 'lexer.dart';

/// Limits protect against hostile or corrupt input.
const int maxInputSize = 64 << 20;
const int maxDepth = 64;
const int maxTables = 1 << 20;

/// A saved file that cannot be parsed. A syntax error has a line and a column.
class SavedVarsException implements Exception {
  SavedVarsException(this.message, {this.line, this.column});

  final String message;
  final int? line;
  final int? column;

  bool get isSyntax => line != null;

  @override
  String toString() =>
      line == null ? message : 'line $line, column $column: $message';
}

/// Reads a saved file and returns its top-level assignments.
///
/// Tables with the keys 1..n become `List<Object?>`. Other tables become
/// `Map<String, Object?>`. The parser never runs the Lua code.
Map<String, Object?> parseSavedVars(List<int> bytes) {
  if (bytes.length > maxInputSize) {
    throw SavedVarsException('input is larger than $maxInputSize bytes');
  }
  final src = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
  return _Parser(Lexer(src)).parse();
}

class _Parser {
  _Parser(this._lex) : _tok = const Token(TokenKind.eof, '', 0, 0);

  final Lexer _lex;
  Token _tok;
  int _depth = 0;
  int _count = 0;

  Map<String, Object?> parse() {
    _step();
    final out = <String, Object?>{};
    while (_tok.kind != TokenKind.eof) {
      if (_tok.kind != TokenKind.ident) throw _unexpected();
      final name = _tok.text;
      _step();
      _expect('=');
      out[name] = _value();
    }
    return out;
  }

  void _step() => _tok = _lex.next();

  SavedVarsException _unexpected() {
    final what = _tok.kind == TokenKind.eof ? 'end of input' : _tok.text;
    return _lex.errorAt(_tok.line, _tok.col, 'unexpected ${goQuote(what)}');
  }

  bool _isSymbol(String s) => _tok.kind == TokenKind.symbol && _tok.text == s;

  void _expect(String s) {
    if (!_isSymbol(s)) throw _unexpected();
    _step();
  }

  Object? _value() {
    final tok = _tok;
    switch (tok.kind) {
      case TokenKind.string:
        _step();
        return tok.text;
      case TokenKind.number:
        _step();
        return tok.num;
      case TokenKind.ident:
        switch (tok.text) {
          case 'true':
            _step();
            return true;
          case 'false':
            _step();
            return false;
          case 'nil':
            _step();
            return null;
        }
      case TokenKind.symbol:
        if (tok.text == '{') return _table();
      case TokenKind.eof:
    }
    throw _unexpected();
  }

  Object _table() {
    _depth++;
    _count++;
    try {
      if (_count > maxTables) {
        throw _lex.errorAt(_tok.line, _tok.col, 'more than $maxTables tables');
      }
      if (_depth > maxDepth) {
        throw _lex.errorAt(
          _tok.line,
          _tok.col,
          'tables are nested deeper than $maxDepth levels',
        );
      }
      _expect('{');
      final b = _TableBuilder();
      while (!_isSymbol('}')) {
        _field(b);
        if (_isSymbol(',') || _isSymbol(';')) {
          _step();
          continue;
        }
        if (!_isSymbol('}')) throw _unexpected();
      }
      _expect('}');
      return b.result();
    } finally {
      _depth--;
    }
  }

  void _field(_TableBuilder b) {
    if (_isSymbol('[')) {
      _step();
      final Object? key;
      switch (_tok.kind) {
        case TokenKind.string:
          key = _tok.text;
        case TokenKind.number:
          key = _tok.num;
        default:
          throw _unexpected();
      }
      _step();
      _expect(']');
      _expect('=');
      b.setKey(key, _value());
      return;
    }
    if (_tok.kind == TokenKind.ident &&
        _tok.text != 'true' &&
        _tok.text != 'false' &&
        _tok.text != 'nil') {
      final name = _tok.text;
      _step();
      _expect('=');
      b.named[name] = _value();
      return;
    }
    final value = _value();
    b.next++;
    b.numeric[b.next] = value;
  }
}

class _TableBuilder {
  final Map<int, Object?> numeric = {};
  final Map<String, Object?> named = {};
  int next = 0;

  void setKey(Object? key, Object? value) {
    switch (key) {
      case int k:
        numeric[k] = value;
      case double k:
        if (k == k.truncateToDouble() && k.abs() < 9007199254740992.0) {
          numeric[k.toInt()] = value;
        } else {
          named[formatFloatG(k)] = value;
        }
      case String k:
        named[k] = value;
    }
  }

  Object result() {
    if (named.isEmpty && numeric.isNotEmpty) {
      var isArray = true;
      for (var i = 1; i <= numeric.length && isArray; i++) {
        isArray = numeric.containsKey(i);
      }
      if (isArray) {
        return List<Object?>.generate(numeric.length, (i) => numeric[i + 1]);
      }
    }
    final out = <String, Object?>{...named};
    for (final k in numeric.keys.toList()..sort()) {
      out['$k'] = numeric[k];
    }
    return out;
  }
}

/// Formats a double like Go's `strconv.FormatFloat(f, 'g', -1, 64)`.
String formatFloatG(double f) {
  if (f == 0) return f.isNegative ? '-0' : '0';
  final sci = f.abs().toStringAsExponential();
  final parts = sci.split('e');
  final digits = parts[0].replaceAll('.', '');
  final exp = int.parse(parts[1]);
  final sign = f < 0 ? '-' : '';
  if (exp < -4 || exp >= 6) {
    final mantissa = digits.length > 1
        ? '${digits[0]}.${digits.substring(1)}'
        : digits;
    final e = exp.abs().toString().padLeft(2, '0');
    return '$sign${mantissa}e${exp < 0 ? '-' : '+'}$e';
  }
  if (exp < 0) return '${sign}0.${'0' * (-exp - 1)}$digits';
  if (digits.length <= exp + 1) {
    return '$sign$digits${'0' * (exp + 1 - digits.length)}';
  }
  return '$sign${digits.substring(0, exp + 1)}.${digits.substring(exp + 1)}';
}
