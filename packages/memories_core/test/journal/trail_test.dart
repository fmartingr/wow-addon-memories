import 'dart:convert';
import 'dart:io';

import 'package:memories_core/memories_core.dart';
import 'package:test/test.dart';

void main() {
  group('decodeChunk', () {
    test('decodes the points and carries the flags forward', () {
      final c = decodeChunk({
        's': 100,
        't': 1000,
        'm': 1429,
        'n': 3,
        'd': '0,4512,6120,m;2,4530,6101;4,4560,6080,mc',
      });
      expect(
        jsonEncode(c.toJson()),
        '{"s":100,"t":1000,"m":1429,"n":3,"pts":'
        '[[1000,4512,6120,"m"],[1002,4530,6101,"m"],[1004,4560,6080,"mc"]]}',
      );
    });

    test('round trips through JSON', () {
      final c = decodeChunk({
        's': 100,
        't': 1000,
        'm': 1429,
        'd': '0,1,2,m;3,4,5',
      });
      final back = Chunk.fromJson(jsonDecode(jsonEncode(c.toJson())));
      expect(back.toJson(), c.toJson());
      expect(back.pts, c.pts);
    });

    test('an empty path has no points and no session start', () {
      final c = decodeChunk({'t': 1, 'm': 2, 'd': ''});
      expect(c.s, isNull);
      expect(c.n, 0);
      expect(c.pts, isEmpty);
      expect(c.toJson()['s'], isNull);
    });

    test('a point with no flags starts with "-"', () {
      expect(decodeChunk({'t': 1, 'm': 2, 'd': '0,1,2'}).pts.first.flags, '-');
    });

    test('a chunk that cannot be decoded is refused', () {
      final bad = <Object?>[
        'x',
        {'m': 2, 'd': ''},
        {'t': 1, 'd': ''},
        {'t': 1, 'm': 2},
        {'t': 1, 'm': 2, 'd': '0,1'},
        {'t': 1, 'm': 2, 'd': '99999999999999999999,1,2'},
        {'t': 1, 'm': 2, 'd': '0,1,2,a\nb'},
        {'t': 1, 'm': 2, 'd': '0,1,2;'},
      ];
      for (final v in bad) {
        expect(
          () => decodeChunk(v),
          throwsA(isA<BadChunkException>()),
          reason: '$v',
        );
      }
    });

    test('the error text names the bad point', () {
      try {
        decodeChunk({'t': 1, 'm': 2, 'd': '0,1'});
        fail('expected an error');
      } on BadChunkException catch (e) {
        expect(e.toString(), 'bad trail chunk: point "0,1"');
      }
      expect(const BadChunkException().toString(), 'bad trail chunk');
    });
  });

  group('trail', () {
    test('decodes the trail of the fixture like the golden trail', () {
      const root = '../../testdata/wow/WTF/Account/TESTACCOUNT';
      final character = parseSavedVars(
        File('$root/Brumamar/Ñandú/SavedVariables/Memories.lua')
            .readAsBytesSync(),
      );
      final db = character['MemoriesCharDB']! as Map<String, Object?>;
      final r = trail(db['trail']);
      final golden = File(
        '../../cmd/memories-export/testdata/expected/eu-brumamar-nandu/trail.jsonl',
      ).readAsLinesSync();
      expect(r.bad, 0);
      expect([for (final c in r.chunks) jsonEncode(c.toJson())], golden);
    });

    test('keeps the open chunk and counts the broken ones', () {
      final r = trail({
        'v': 1,
        'chunks': [
          {'t': 1, 'm': 2, 'd': '0,1,2'},
          'broken',
        ],
        'open': {'t': 5, 'm': 2, 'd': '0,3,4,m', 'o': 1},
      });
      expect(r.bad, 1);
      expect(r.chunks, hasLength(2));
      expect(r.chunks[1].t, 5);
    });

    test('a value that is not a table has no chunks', () {
      final r = trail(null);
      expect(r.chunks, isEmpty);
      expect(r.bad, 0);
    });

    test('a broken open chunk is counted', () {
      final r = trail({
        'chunks': <String, Object?>{},
        'open': {'t': 1},
      });
      expect(r.chunks, isEmpty);
      expect(r.bad, 1);
    });
  });

  group('TrailPoint.fromJson', () {
    test('refuses a wrong shape', () {
      for (final v in <Object?>[
        <String, Object?>{},
        [1, 2, 3],
        ['a', 2, 3, '-'],
        [1, 2, 3, 4],
      ]) {
        expect(
          () => TrailPoint.fromJson(v),
          throwsFormatException,
          reason: '$v',
        );
      }
    });

    test('reads a good point', () {
      expect(
        TrailPoint.fromJson([1, 2, 3, 'm']),
        const TrailPoint(1, 2, 3, 'm'),
      );
      expect(
        TrailPoint.fromJson([1, 2, 3, 'm']).hashCode,
        const TrailPoint(1, 2, 3, 'm').hashCode,
      );
    });
  });

  group('Chunk.fromJson', () {
    test('refuses a wrong shape', () {
      for (final v in <Object?>[
        'x',
        {'t': 'a', 'm': 1, 'n': 0},
        {'t': 1, 'm': 1, 'n': 0, 's': 'x'},
        {'t': 1, 'm': 1, 'n': 0, 'pts': 'x'},
        {'t': 1, 'm': 1},
      ]) {
        expect(() => Chunk.fromJson(v), throwsFormatException, reason: '$v');
      }
    });

    test('reads a chunk with no points', () {
      final c = Chunk.fromJson({
        's': null,
        't': 1,
        'm': 1,
        'n': 0,
        'pts': null,
      });
      expect(c.pts, isEmpty);
      expect(c.s, isNull);
    });

    test('keeps the stored count of points, as Go does', () {
      final c = Chunk.fromJson({
        't': 1,
        'm': 1,
        'n': 2,
        'pts': [
          [1, 2, 3, 'm'],
        ],
      });
      expect(c.n, 2);
      expect(c.pts, hasLength(1));
    });
  });
}
