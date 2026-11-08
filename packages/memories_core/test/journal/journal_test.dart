import 'dart:convert';
import 'dart:io';

import 'package:memories_core/memories_core.dart';
import 'package:test/test.dart';

final testKinds = parseKinds({
  'ss': 'Memories;Screenshots;why,result,file',
  'lv': 'Memories;Progress;#level',
  'out': 'Memories;Sessions;',
  'bad': 'no separators',
  'num': 5,
});

Map<String, Object?> rec(Map<String, Object?> extra) => {
  'p': null,
  'm': null,
  'x': null,
  'y': null,
  ...extra,
};

void main() {
  group('parseKinds', () {
    test('reads the addon, the group and the fields', () {
      expect(testKinds.keys, unorderedEquals(['ss', 'lv', 'out']));
      final ss = testKinds['ss']!;
      expect(ss.addon, 'Memories');
      expect(ss.group, 'Screenshots');
      expect(ss.fields.map((f) => (f.name, f.numeric)), [
        ('why', false),
        ('result', false),
        ('file', false),
      ]);
      expect(testKinds['lv']!.fields.single.name, 'level');
      expect(testKinds['lv']!.fields.single.numeric, isTrue);
      expect(testKinds['out']!.fields, isEmpty);
    });

    test('skips a value with no separators or with a wrong type', () {
      expect(testKinds.containsKey('bad'), isFalse);
      expect(testKinds.containsKey('num'), isFalse);
    });

    test('keeps a ";" inside the field list out of the group', () {
      final k = parseKinds({'a': 'Add;Grp;f;g'})['a']!;
      expect(k.group, 'Grp');
      expect(k.fields.single.name, 'f;g');
    });

    test('a value that is not a table gives no kinds', () {
      expect(parseKinds('not a table'), isEmpty);
      expect(parseKinds(null), isEmpty);
    });
  });

  group('asList', () {
    test('keeps a list', () => expect(asList(['a']), ['a']));

    test('sorts the numeric keys of a map and drops the other keys', () {
      expect(asList({'3': 'c', '1': 'a', 'name': 'x'}), ['a', 'c']);
    });

    test(
      'reads a key with a sign as the number but looks up the plain key',
      () {
        expect(asList({'+3': 'x'}), [null]);
      },
    );

    test('gives nothing for another value', () {
      expect(asList(null), isEmpty);
      expect(asList('x'), isEmpty);
    });
  });

  group('journalLines', () {
    test('splits the chunks, then adds the open lines', () {
      final log = {
        'chunks': ['1|||||in|login\n2|||||out', 7],
        'open': ['3|||||pl|10', false],
      };
      expect(journalLines(log), ['1|||||in|login', '2|||||out', '3|||||pl|10']);
    });

    test('skips an empty chunk but keeps an empty open line', () {
      expect(
        journalLines({
          'chunks': ['', 'a'],
          'open': [''],
        }),
        ['a', ''],
      );
    });

    test('an empty log, or one that is not a table, has no lines', () {
      expect(
        journalLines({
          'chunks': <String, Object?>{},
          'open': <String, Object?>{},
        }),
        isEmpty,
      );
      expect(journalLines('x'), isEmpty);
    });
  });

  group('decodeLine', () {
    final cases = <String, (String, Map<String, Object?>)>{
      'named fields': (
        '1762437789|500|1429|4512|6120|ss|by hand|ok|WoWScrnShot_110626_140309.jpg',
        {
          't': 1762437789,
          'p': 500,
          'm': 1429,
          'x': 4512,
          'y': 6120,
          'k': 'ss',
          'why': 'by hand',
          'result': 'ok',
          'file': 'WoWScrnShot_110626_140309.jpg',
        },
      ),
      'empty fixed and fields': (
        '5|||||ss||failed',
        rec({'t': 5, 'k': 'ss', 'result': 'failed'}),
      ),
      'numeric field': ('5|||||lv|12', rec({'t': 5, 'k': 'lv', 'level': 12})),
      'float field': ('5|||||lv|1.5', rec({'t': 5, 'k': 'lv', 'level': 1.5})),
      'text in a numeric field': (
        '5|||||lv|ten',
        rec({
          't': 5,
          'k': 'lv',
          'extra': {'1': 'ten'},
        }),
      ),
      'values past the fields': (
        '5|||||lv|3|x||y',
        rec({
          't': 5,
          'k': 'lv',
          'level': 3,
          'extra': {'2': 'x', '4': 'y'},
        }),
      ),
      'unknown kind': (
        '5|1.5|x|||zz|a|b',
        {
          't': 5,
          'p': 1.5,
          'm': 'x',
          'x': null,
          'y': null,
          'k': 'zz',
          'extra': {'1': 'a', '2': 'b'},
        },
      ),
      'NaN is text': (
        '5|||||lv|NaN',
        rec({
          't': 5,
          'k': 'lv',
          'extra': {'1': 'NaN'},
        }),
      ),
      'a text value keeps a "-" and a space': (
        '5|||||ss|a - b',
        rec({'t': 5, 'k': 'ss', 'why': 'a - b'}),
      ),
      'a negative time': ('-5|||||out', rec({'t': -5, 'k': 'out'})),
    };
    cases.forEach((name, c) {
      test(name, () => expect(decodeLine(c.$1, testKinds), c.$2));
    });

    test('numbers keep the int and double types', () {
      final r = decodeLine('5|1|2.0|||lv|3', testKinds);
      expect(r['p'], isA<int>());
      expect(r['m'], isA<double>());
      expect(r['level'], isA<int>());
    });

    test('a field with a reserved name goes into extra', () {
      final kinds = parseKinds({'zz': 'Sub;Test;t,session,name'});
      expect(
        decodeLine('5|||||zz|9|s|n', kinds),
        rec({
          't': 5,
          'k': 'zz',
          'name': 'n',
          'extra': {'1': '9', '2': 's'},
        }),
      );
    });

    test('a line with fewer than 6 columns is a short line', () {
      expect(
        () => decodeLine('1|2|3|4|5', testKinds),
        throwsA(isA<ShortLineException>()),
      );
    });

    test('a time that is not a whole number is refused', () {
      for (final line in [
        'x|2|3|4|5|in',
        '1.5|||||in',
        ' 1|||||in',
        '0x10|||||in',
        '|||||in|',
      ]) {
        expect(
          () => decodeLine(line, testKinds),
          throwsA(isA<BadTimeException>()),
          reason: line,
        );
      }
    });

    test('the error texts are plain', () {
      expect(const ShortLineException().toString(), 'fewer than 6 columns');
      expect(
        const BadTimeException('x').toString(),
        'the time is not a whole number: "x"',
      );
    });
  });

  group('parseNumber', () {
    test('refuses hex, infinity, empty text, underscores and spaces', () {
      for (final s in [
        '0x10',
        'Inf',
        '1e999',
        '',
        '1_000',
        ' 1',
        '+1',
        '1.',
        '.5',
      ]) {
        expect(parseNumber(s), isNull, reason: s);
      }
    });

    test('reads exponents and big numbers as double', () {
      expect(parseNumber('-2e3'), -2000.0);
      expect(parseNumber('-2e3'), isA<double>());
      expect(parseNumber('99999999999999999999'), 1e20);
      expect(parseNumber('-0'), 0);
      expect(parseNumber('-0'), isA<int>());
    });
  });

  group('asInt', () {
    test('reads a whole number', () {
      expect(asInt(3), 3);
      expect(asInt(3.0), 3);
    });

    test('refuses a fraction, a text, null and a number past 2^53', () {
      expect(asInt(3.5), isNull);
      expect(asInt('3'), isNull);
      expect(asInt(null), isNull);
      expect(asInt(9007199254740992.0), isNull);
    });
  });

  test('record helpers', () {
    final r = JournalRecord({'t': 12, 'file': 'a', 'n': 1});
    expect(r.time, 12);
    expect(r.text('file'), 'a');
    expect(r.text('n'), '');
    expect(r.text('none'), '');
    expect(JournalRecord({}).time, 0);
  });

  test('decodes the character file of the fixture like the golden journey', () {
    const root = '../../testdata/wow/WTF/Account/TESTACCOUNT';
    final account = parseSavedVars(
      File('$root/SavedVariables/Memories.lua').readAsBytesSync(),
    );
    final kinds = parseKinds(
      (account['MemoriesDB']! as Map<String, Object?>)['kinds'],
    );
    final character = parseSavedVars(
      File('$root/Brumamar/Ñandú/SavedVariables/Memories.lua')
          .readAsBytesSync(),
    );
    final log = (character['MemoriesCharDB']! as Map<String, Object?>)['log'];

    final golden = <String, Map<String, Object?>>{};
    const addedByExport = {'addon', 'session', 'screenshot', 'notes'};
    final journey = File(
      '../../testdata/expected/eu-brumamar-nandu/journey.jsonl',
    );
    for (final l in journey.readAsLinesSync()) {
      final r = jsonDecode(l) as Map<String, Object?>;
      golden['${r['t']}|${r['k']}'] = {
        for (final e in r.entries)
          if (!addedByExport.contains(e.key)) e.key: e.value,
      };
    }

    var compared = 0;
    var short = 0;
    for (final line in journalLines(log)) {
      final JournalRecord r;
      try {
        r = decodeLine(line, kinds);
      } on ShortLineException {
        short++;
        continue;
      }
      final want = golden['${r['t']}|${r['k']}'];
      if (want == null) continue;
      expect(r, want, reason: line);
      compared++;
    }
    expect(short, 1);
    expect(compared, greaterThan(8));
  });
}
