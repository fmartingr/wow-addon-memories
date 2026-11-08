import 'dart:convert';

import 'package:memories_core/src/gather/json.dart';
import 'package:test/test.dart';

void main() {
  group('encodeJson', () {
    test('sorts map keys by their UTF-8 bytes', () {
      expect(
        encodeJson({'b': 1, 'a': 2, '\uffff': 3, '\u{1f600}': 4, 'Z': 5}),
        '{"Z":5,"a":2,"b":1,"\uffff":3,"\u{1f600}":4}\n',
      );
    });

    test('keeps the field order of a struct', () {
      expect(
        encodeJson(const Ordered({'s': null, 't': 1, 'm': 2})),
        '{"s":null,"t":1,"m":2}\n',
      );
    });

    test('escapes text as Go does with HTML escaping off', () {
      expect(
        encodeJson('a"b\\c\n\r\t\b\f\x00\x01\x1f\x7f<>&\u2028\u2029é\ufffd😀'),
        r'"a\"b\\c\n\r\t\b\f\u0000\u0001\u001f'
        '\x7f<>&'
        r'\u2028\u2029'
        'é\ufffd😀"\n',
      );
    });

    test('writes a lone surrogate as U+FFFD', () {
      expect(encodeJson('a\ud800b\udc00'), '"a\ufffdb\ufffd"\n');
      expect(encodeJson('\ud83d'), '"\ufffd"\n');
    });

    test('formats floats as Go does', () {
      final cases = {
        1e21: '1e+21',
        1e20: '100000000000000000000',
        1e-7: '1e-7',
        1e-6: '0.000001',
        0.000001234: '0.000001234',
        1.23456789e-7: '1.23456789e-7',
        1.5: '1.5',
        5.0: '5',
        -2.0: '-2',
        1e100: '1e+100',
        1e-100: '1e-100',
        123456789012345678901.0: '123456789012345680000',
        2.5e-10: '2.5e-10',
        0.1: '0.1',
        1.7976931348623157e308: '1.7976931348623157e+308',
        5e-324: '5e-324',
        1234567.125: '1234567.125',
      };
      cases.forEach((v, want) => expect(formatGoFloat(v), want, reason: '$v'));
      expect(formatGoFloat(-0.0), '-0');
      expect(formatGoFloat(0.0), '0');
      expect(encodeJson([1.0, 2]), '[1,2]\n');
    });

    test('refuses NaN, infinities and unknown types', () {
      expect(() => formatGoFloat(double.nan), throwsArgumentError);
      expect(() => formatGoFloat(double.infinity), throwsArgumentError);
      expect(() => encodeJson(Object()), throwsArgumentError);
      expect(() => encodeJson({1: 2}), throwsArgumentError);
    });

    test('indents with one space and keeps empty values short', () {
      expect(
        encodeJson({
          'a': <Object?>[],
          'b': <String, Object?>{},
          'c': [
            1,
            {'x': null},
          ],
          'd': true,
          'e': false,
        }, indent: true),
        '{\n "a": [],\n "b": {},\n "c": [\n  1,\n  {\n   "x": null\n  }\n ],'
        '\n "d": true,\n "e": false\n}\n',
      );
      expect(encodeJson(const Ordered({})), '{}\n');
    });

    test('writes UTF-8 bytes', () {
      expect(utf8.decode(encodeJsonBytes('ñ')), '"ñ"\n');
    });
  });

  group('compareUtf8', () {
    test('orders by code point', () {
      expect(compareUtf8('a', 'b'), lessThan(0));
      expect(compareUtf8('ab', 'a'), greaterThan(0));
      expect(compareUtf8('\u{1f600}', '\uffff'), greaterThan(0));
      expect(compareUtf8('\ue000', '\ud800'), lessThan(0));
      expect(compareUtf8('x', 'x'), 0);
    });
  });
}
