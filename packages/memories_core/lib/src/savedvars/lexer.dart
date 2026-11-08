import 'dart:convert';
import 'dart:typed_data';

import 'parser.dart' show SavedVarsException;

enum TokenKind { eof, ident, string, number, symbol }

class Token {
  const Token(this.kind, this.text, this.line, this.col, [this.num]);

  final TokenKind kind;
  final String text;

  /// An `int` for a literal with no dot or exponent that fits 64 bits, else a
  /// `double`.
  final Object? num;
  final int line;
  final int col;
}

const int _tab = 9;
const int _lf = 10;
const int _cr = 13;
const int _space = 32;
const int _dquote = 34;
const int _squote = 39;
const int _plus = 43;
const int _minus = 45;
const int _dot = 46;
const int _zero = 48;
const int _backslash = 92;

bool _isDigit(int c) => c >= 48 && c <= 57;

bool _isIdentStart(int c) =>
    c == 95 || (c >= 97 && c <= 122) || (c >= 65 && c <= 90);

bool _isSymbol(int c) => switch (c) {
  123 || 125 || 91 || 93 || 61 || 44 || 59 => true,
  _ => false,
};

/// Splits the bytes of a saved file into tokens. Line and column count bytes.
class Lexer {
  Lexer(this._src);

  final Uint8List _src;
  int _pos = 0;
  int _line = 1;
  int _col = 1;

  SavedVarsException errorAt(int line, int col, String message) =>
      SavedVarsException(message, line: line, column: col);

  int _peek(int offset) =>
      _pos + offset >= _src.length ? 0 : _src[_pos + offset];

  int _advance() {
    final c = _src[_pos++];
    if (c == _lf) {
      _line++;
      _col = 1;
    } else {
      _col++;
    }
    return c;
  }

  void _skipSpace() {
    while (_pos < _src.length) {
      final c = _src[_pos];
      if (c == _space || c == _tab || c == _cr || c == _lf) {
        _advance();
      } else if (c == _minus && _peek(1) == _minus) {
        while (_pos < _src.length && _src[_pos] != _lf) {
          _advance();
        }
      } else {
        return;
      }
    }
  }

  Token next() {
    _skipSpace();
    final line = _line;
    final col = _col;
    if (_pos >= _src.length) {
      return Token(TokenKind.eof, '', line, col);
    }
    final c = _src[_pos];
    if (_isIdentStart(c)) {
      final start = _pos;
      while (_pos < _src.length &&
          (_isIdentStart(_src[_pos]) || _isDigit(_src[_pos]))) {
        _advance();
      }
      return Token(
        TokenKind.ident,
        String.fromCharCodes(_src, start, _pos),
        line,
        col,
      );
    }
    if (c == _dquote || c == _squote) {
      return _lexString(c, line, col);
    }
    if (_isDigit(c) || c == _minus || (c == _dot && _isDigit(_peek(1)))) {
      return _lexNumber(line, col);
    }
    if (_isSymbol(c)) {
      _advance();
      return Token(TokenKind.symbol, String.fromCharCode(c), line, col);
    }
    throw errorAt(line, col, 'unexpected character ${quoteByte(c)}');
  }

  Token _lexNumber(int line, int col) {
    final start = _pos;
    if (_src[_pos] == _minus) {
      _advance();
      if (!_isDigit(_peek(0)) && (_peek(0) != _dot || !_isDigit(_peek(1)))) {
        throw errorAt(line, col, 'invalid number');
      }
    }
    var isFloat = false;
    while (_isDigit(_peek(0))) {
      _advance();
    }
    if (_peek(0) == _dot) {
      isFloat = true;
      _advance();
      while (_isDigit(_peek(0))) {
        _advance();
      }
    }
    final e = _peek(0);
    if (e == 101 || e == 69) {
      isFloat = true;
      _advance();
      final sign = _peek(0);
      if (sign == _plus || sign == _minus) {
        _advance();
      }
      if (!_isDigit(_peek(0))) {
        throw errorAt(line, col, 'invalid number exponent');
      }
      while (_isDigit(_peek(0))) {
        _advance();
      }
    }
    final text = String.fromCharCodes(_src, start, _pos);
    if (!isFloat) {
      final n = int.tryParse(text);
      if (n != null) {
        return Token(TokenKind.number, text, line, col, n);
      }
    }
    final f = double.tryParse(text);
    if (f == null || f.isInfinite) {
      throw errorAt(line, col, 'invalid number ${goQuote(text)}');
    }
    return Token(TokenKind.number, text, line, col, f);
  }

  Token _lexString(int quote, int line, int col) {
    _advance();
    final bytes = <int>[];
    while (true) {
      if (_pos >= _src.length || _src[_pos] == _lf) {
        throw errorAt(line, col, 'unterminated string');
      }
      final c = _advance();
      if (c == quote) {
        return Token(TokenKind.string, decodeUtf8LikeGo(bytes), line, col);
      }
      if (c != _backslash) {
        bytes.add(c);
        continue;
      }
      if (_pos >= _src.length) {
        throw errorAt(line, col, 'unterminated string');
      }
      final escLine = _line;
      final escCol = _col;
      final e = _advance();
      switch (e) {
        case 110:
          bytes.add(_lf);
        case 114:
          bytes.add(_cr);
        case 116:
          bytes.add(_tab);
        case 97:
          bytes.add(7);
        case 98:
          bytes.add(8);
        case 102:
          bytes.add(12);
        case 118:
          bytes.add(11);
        case _backslash || _dquote || _squote:
          bytes.add(e);
        case _lf || _cr:
          // Lua reads an escaped line break, "\n", "\r", "\r\n" or "\n\r", as one "\n".
          if (_peek(0) == _lf + _cr - e) {
            _advance();
          }
          bytes.add(_lf);
        default:
          if (!_isDigit(e)) {
            throw errorAt(
              escLine,
              escCol,
              'invalid escape \\${String.fromCharCode(e)}',
            );
          }
          var n = e - _zero;
          for (var i = 0; i < 2 && _isDigit(_peek(0)); i++) {
            n = n * 10 + (_advance() - _zero);
          }
          if (n > 255) {
            throw errorAt(escLine, escCol, 'decimal escape too large');
          }
          bytes.add(n);
      }
    }
  }
}

/// Decodes UTF-8 and turns each byte of a bad sequence into one U+FFFD.
///
/// Go keeps the raw bytes and its JSON writer replaces each bad byte on its
/// own. Dart's `allowMalformed` replaces a cut-off sequence with a single
/// U+FFFD, which would give different text for a string that an addon cut in
/// the middle of a character.
String decodeUtf8LikeGo(List<int> bytes) {
  try {
    return utf8.decode(bytes);
  } on FormatException {
    // Fall through to the byte-by-byte decoder.
  }
  final out = StringBuffer();
  var i = 0;
  while (i < bytes.length) {
    final c = bytes[i];
    if (c < 0x80) {
      out.writeCharCode(c);
      i++;
      continue;
    }
    var need = 0;
    var lo = 0x80;
    var hi = 0xbf;
    if (c >= 0xc2 && c <= 0xdf) {
      need = 1;
    } else if (c >= 0xe0 && c <= 0xef) {
      need = 2;
      if (c == 0xe0) lo = 0xa0;
      if (c == 0xed) hi = 0x9f;
    } else if (c >= 0xf0 && c <= 0xf4) {
      need = 3;
      if (c == 0xf0) lo = 0x90;
      if (c == 0xf4) hi = 0x8f;
    }
    var ok = need > 0 && i + need < bytes.length;
    for (var k = 1; ok && k <= need; k++) {
      final b = bytes[i + k];
      ok = k == 1 ? b >= lo && b <= hi : b >= 0x80 && b <= 0xbf;
    }
    if (!ok) {
      out.writeCharCode(0xfffd);
      i++;
      continue;
    }
    var r = c & (0x7f >> (need + 1));
    for (var k = 1; k <= need; k++) {
      r = (r << 6) | (bytes[i + k] & 0x3f);
    }
    out.writeCharCode(r);
    i += need + 1;
  }
  return out.toString();
}

const Map<int, String> _shortEscapes = {
  7: r'\a',
  8: r'\b',
  12: r'\f',
  10: r'\n',
  13: r'\r',
  9: r'\t',
  11: r'\v',
};

String _escapeRune(int r, String quote) {
  final short = _shortEscapes[r];
  if (short != null) return short;
  if (r == _backslash) return r'\\';
  if (String.fromCharCode(r) == quote) return '\\$quote';
  if (r < 0x20 || r == 0x7f) {
    return '\\x${r.toRadixString(16).padLeft(2, '0')}';
  }
  if ((r >= 0x80 && r <= 0xa0) || r == 0xad || r == 0x2028 || r == 0x2029) {
    return '\\u${r.toRadixString(16).padLeft(4, '0')}';
  }
  return String.fromCharCode(r);
}

/// Formats a byte as a quoted character, the way Go prints it with `%q`.
String quoteByte(int c) => "'${_escapeRune(c, "'")}'";

/// Formats a string in double quotes, the way Go prints it with `%q`.
String goQuote(String s) =>
    '"${s.runes.map((r) => _escapeRune(r, '"')).join()}"';
