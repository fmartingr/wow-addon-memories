import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:memories_core/memories_core.dart';
import 'package:memories_core/src/savedvars/lexer.dart' show decodeUtf8LikeGo;
import 'package:memories_core/src/savedvars/parser.dart' show formatFloatG;
import 'package:test/test.dart';

Map<String, Object?> parse(String src) => parseSavedVars(utf8.encode(src));

String parseError(String src) {
  try {
    parse(src);
  } on SavedVarsException catch (e) {
    return e.toString();
  }
  fail('expected an error for ${jsonEncode(src)}');
}

void main() {
  group('values', () {
    final cases = <String, (String, Map<String, Object?>)>{
      'empty': ('', {}),
      'header comment only': ('-- header\n', {}),
      'string': ('A = "hi"', {'A': 'hi'}),
      'single quote': ("A = 'hi'", {'A': 'hi'}),
      'integer': ('A = 42', {'A': 42}),
      'negative': ('A = -7', {'A': -7}),
      'float': ('A = 1.5', {'A': 1.5}),
      'leading dot float': ('A = .5', {'A': 0.5}),
      'negative leading dot float': ('A = -.5', {'A': -0.5}),
      'trailing dot float': ('A = 5.', {'A': 5.0}),
      'exponent': ('A = 1e3', {'A': 1000.0}),
      'signed exponent': ('A = 2E-1', {'A': 0.2}),
      'big integer becomes float': ('A = 99999999999999999999', {'A': 1e20}),
      'smallest int64': (
        'A = -9223372036854775808',
        {'A': -9223372036854775808},
      ),
      'booleans and nil': (
        'A = true B = false C = nil',
        {'A': true, 'B': false, 'C': null},
      ),
      'empty table': ('A = {}', {'A': <String, Object?>{}}),
      'named fields': (
        'A = { x = 1, ["y"] = 2; z = "s", }',
        {
          'A': {'x': 1, 'y': 2, 'z': 's'},
        },
      ),
      'array': (
        'A = { 10, 20, 30, -- [3]\n}',
        {
          'A': [10, 20, 30],
        },
      ),
      'explicit index array': (
        'A = { [1] = "a", [2] = "b" }',
        {
          'A': ['a', 'b'],
        },
      ),
      'float index array': (
        'A = { [1.0] = "a" }',
        {
          'A': ['a'],
        },
      ),
      'sparse array becomes map': (
        'A = { [1] = "a", [3] = "c" }',
        {
          'A': {'1': 'a', '3': 'c'},
        },
      ),
      'mixed keys become map': (
        'A = { "a", x = 1 }',
        {
          'A': {'1': 'a', 'x': 1},
        },
      ),
      'fractional key': (
        'A = { [1.5] = "a" }',
        {
          'A': {'1.5': 'a'},
        },
      ),
      'number string key and number key': (
        'A = { ["1"] = "s", [1] = "n" }',
        {
          'A': {'1': 'n'},
        },
      ),
      'nested': (
        'A = { { x = { 1 } } }',
        {
          'A': [
            {
              'x': [1],
            },
          ],
        },
      ),
      'several assignments': ('A = 1\nB = 2', {'A': 1, 'B': 2}),
      'duplicate assignment, last wins': ('A = 1\nA = 2', {'A': 2}),
      'duplicate field, last wins': (
        'A = { x = 1, x = 2 }',
        {
          'A': {'x': 2},
        },
      ),
      'nil positional': (
        'A = { nil, 2 }',
        {
          'A': [null, 2],
        },
      ),
      'trailing separators': (
        'A = { 1, 2, }\nB = { x = 1; }',
        {
          'A': [1, 2],
          'B': {'x': 1},
        },
      ),
      'CRLF line ends': ('A = 1\r\n-- c\r\nB = 2\r\n', {'A': 1, 'B': 2}),
      'comment with no line end': ('A = 1 -- end', {'A': 1}),
    };
    cases.forEach((name, c) {
      test(name, () => expect(parse(c.$1), c.$2));
    });

    test('whole numbers are int and others are double', () {
      final out = parse('A = 42 B = 1.0 C = 1e3 D = 99999999999999999999');
      expect(out['A'], isA<int>());
      expect(out['B'], isA<double>());
      expect(out['C'], isA<double>());
      expect(out['D'], isA<double>());
    });

    test('a table with keys 1..n is a list and other tables are maps', () {
      final out = parse('A = { 1, 2 } B = { [2] = 1 } C = {}');
      expect(out['A'], isA<List<Object?>>());
      expect(out['B'], isA<Map<String, Object?>>());
      expect(out['C'], isA<Map<String, Object?>>());
    });

    test(
      'a bad UTF-8 byte reads as U+FFFD and a valid pair as one character',
      () {
        expect(
          parseSavedVars(latin1.encode('A = "a\xffb"'))['A'],
          'a\u{fffd}b',
        );
        expect(parse(r'A = "\195\177"')['A'], 'ñ');
        expect(parse('A = "Ñandú"')['A'], 'Ñandú');
      },
    );

    test('each byte of a cut-off UTF-8 sequence reads as one U+FFFD', () {
      expect(parse(r'A = "a\226\130b"')['A'], 'a\u{fffd}\u{fffd}b');
      expect(parse(r'A = "\240\159\152"')['A'], '\u{fffd}' * 3);
    });

    test('accepts a list of ints that is not a Uint8List', () {
      expect(parseSavedVars('A = 1'.codeUnits.toList()), {'A': 1});
    });
  });

  group('decodeUtf8LikeGo matches the Go JSON writer', () {
    final cases = <List<int>, String>{
      [0xe2, 0x82, 0x62]: '\u{fffd}\u{fffd}b',
      [0xf0, 0x9f, 0x98]: '\u{fffd}' * 3,
      [0xed, 0xa0, 0x80]: '\u{fffd}' * 3,
      [0xc0, 0x80]: '\u{fffd}' * 2,
      [0xf4, 0x90, 0x80, 0x80]: '\u{fffd}' * 4,
      [0xe0, 0x80, 0x80]: '\u{fffd}' * 3,
      [0xff]: '\u{fffd}',
      [0x61, 0xff, 0xc3, 0xb1, 0xf0, 0x9f, 0x98, 0x80, 0xe2, 0x82, 0xac]:
          'a\u{fffd}ñ😀€',
      [0xef, 0xbf, 0xbf, 0xf4, 0x8f, 0xbf, 0xbf, 0xed, 0x9f, 0xbf]:
          '\u{ffff}\u{10ffff}\u{d7ff}',
    };
    cases.forEach((bytes, want) {
      test('$bytes', () => expect(decodeUtf8LikeGo(bytes), want));
    });
  });

  group('escapes', () {
    final cases = <String, String>{
      r'A = "a\\b"': r'a\b',
      r'A = "a\"b"': 'a"b',
      r"A = 'a\'b'": "a'b",
      r'A = "a\nb"': 'a\nb',
      r'A = "a\rb"': 'a\rb',
      r'A = "a\tb"': 'a\tb',
      r'A = "\a\b\f\v"': '\x07\x08\x0c\x0b',
      r'A = "\65\066\0067"': 'AB\x067',
      'A = "a\\\nb"': 'a\nb',
      'A = "a\\\r\nb"': 'a\nb',
      'A = "a\\\rb"': 'a\nb',
      'A = "a\\\n\rb"': 'a\nb',
      r'A = "\255"': '\u{fffd}',
    };
    cases.forEach((src, want) {
      test(src, () => expect(parse(src)['A'], want));
    });
  });

  group('errors', () {
    final cases = <String, (String, String)>{
      'unterminated string': (
        'A = 1\nB = "abc',
        'line 2, column 5: unterminated string',
      ),
      'newline in string': (
        'A = "ab\ncd"',
        'line 1, column 5: unterminated string',
      ),
      'escape too large': (r'A = "\256"', 'decimal escape too large'),
      'invalid escape': (r'A = "\q"', 'line 1, column 7: invalid escape \\q'),
      'trailing backslash': (r'A = "\', 'unterminated string'),
      'inf': ('A = inf', 'unexpected'),
      'negative inf': ('A = -inf', 'invalid number'),
      'nan': ('A = nan', 'unexpected'),
      'bad exponent': ('A = 1e', 'invalid number exponent'),
      'number out of range': ('A = 1e999', 'invalid number "1e999"'),
      'missing equals': ('A 1', 'unexpected "1"'),
      'missing value': ('A =', 'unexpected "end of input"'),
      'unclosed table': ('A = { 1,', 'unexpected'),
      'missing comma': ('A = { 1 2 }', 'unexpected "2"'),
      'bad key': ('A = { [true] = 1 }', 'unexpected'),
      'missing bracket': ('A = { ["x" = 1 }', 'unexpected'),
      'bad field equals': ('A = { x 1 }', 'unexpected'),
      'unexpected char': (
        'A = @',
        "line 1, column 5: unexpected character '@'",
      ),
      'statement start': ('1 = 2', 'unexpected'),
      'name as value': ('A = B', 'unexpected'),
      'hex number': ('A = 0x10', 'unexpected "end of input"'),
      'long comment is a line comment': ('--[[ a\n]] A = 1', 'unexpected "]"'),
    };
    cases.forEach((name, c) {
      test(name, () => expect(parseError(c.$1), contains(c.$2)));
    });

    test('a BOM at the start is an unexpected character', () {
      final bytes = [0xef, 0xbb, 0xbf, ...utf8.encode('A = 1')];
      expect(
        () => parseSavedVars(bytes),
        throwsA(
          isA<SavedVarsException>().having(
            (e) => e.toString(),
            'message',
            "line 1, column 1: unexpected character 'ï'",
          ),
        ),
      );
    });

    test('a syntax error has a line, a column and the syntax flag', () {
      try {
        parse('A = 1\nB = @');
        fail('expected an error');
      } on SavedVarsException catch (e) {
        expect(e.isSyntax, isTrue);
        expect(e.line, 2);
        expect(e.column, 5);
      }
    });
  });

  group('limits', () {
    String nest(int n) => 'A = ${'{' * n}${'}' * n}';

    test('depth $maxDepth is read', () {
      expect(parse(nest(maxDepth)), contains('A'));
    });

    test('depth ${maxDepth + 1} is refused', () {
      expect(parseError(nest(maxDepth + 1)), contains('nested deeper'));
    });

    test('$maxTables tables are read', () {
      final src = 'A = {${'{},' * (maxTables - 1)}}';
      expect(parse(src)['A'], hasLength(maxTables - 1));
    });

    test('${maxTables + 1} tables are refused', () {
      final src = 'A = {${'{},' * maxTables}}';
      expect(parseError(src), contains('tables'));
    });

    test('an input of $maxInputSize bytes is read', () {
      final bytes = Uint8List(maxInputSize)..fillRange(0, maxInputSize, 32);
      expect(parseSavedVars(bytes), isEmpty);
    });

    test('an input of ${maxInputSize + 1} bytes is refused', () {
      final bytes = Uint8List(maxInputSize + 1)
        ..fillRange(0, maxInputSize + 1, 32);
      expect(
        () => parseSavedVars(bytes),
        throwsA(
          isA<SavedVarsException>()
              .having((e) => e.isSyntax, 'isSyntax', isFalse)
              .having((e) => e.toString(), 'message', contains('larger than')),
        ),
      );
    });
  });

  group('formatFloatG', () {
    final cases = <double, String>{
      1.5: '1.5',
      -2.5: '-2.5',
      0.0001: '0.0001',
      0.00001: '1e-05',
      123456.5: '123456.5',
      1234567.5: '1.2345675e+06',
      1e300: '1e+300',
      9007199254740992.0: '9.007199254740992e+15',
      0.1: '0.1',
      1e21: '1e+21',
      0.0: '0',
    };
    cases.forEach((value, want) {
      test('$value', () => expect(formatFloatG(value), want));
    });
  });

  test('every prefix of the Go fuzz seeds parses or throws a syntax error', () {
    const seeds = [
      '',
      'A = 1',
      'A = { "x", y = { [1] = 2 }, } -- c',
      r'A = "\65\n"',
      'A = {{{{',
      'A = -',
      'A = 1e',
      "A = '\\",
      'PaparazziDB = { ["captures"] = { { ["file"] = "x", }, -- [1]\n}, }',
    ];
    for (final seed in seeds) {
      final bytes = utf8.encode(seed);
      for (var n = 0; n <= bytes.length; n++) {
        try {
          parseSavedVars(bytes.sublist(0, n));
        } on SavedVarsException catch (e) {
          expect(e.isSyntax, isTrue, reason: '$e');
        }
      }
    }
  });

  test('parses the account and character files of the fixture', () {
    const root = '../../testdata/wow/WTF/Account/TESTACCOUNT';
    final account = parseSavedVars(
      File('$root/SavedVariables/Memories.lua').readAsBytesSync(),
    );
    expect(account.keys, ['MemoriesDB']);
    final character = parseSavedVars(
      File('$root/Brumamar/Ñandú/SavedVariables/Memories.lua')
          .readAsBytesSync(),
    );
    expect(character.keys, ['MemoriesCharDB']);
    final combat = parseSavedVars(
      File('$root/Brumamar/Ñandú/SavedVariables/Memories_Combat.lua')
          .readAsBytesSync(),
    );
    expect(combat.keys, ['MemoriesCombatCharDB']);
  });
}
