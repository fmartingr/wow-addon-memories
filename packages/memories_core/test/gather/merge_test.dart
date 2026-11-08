import 'dart:convert';

import 'package:memories_core/memories_core.dart';
import 'package:memories_core/src/gather/json.dart';
import 'package:memories_core/src/gather/merge.dart';
import 'package:memories_core/src/gather/notes.dart';
import 'package:test/test.dart';

JournalRecord rec(int t, String k, [Map<String, Object?> kv = const {}]) =>
    JournalRecord({'t': t, 'k': k, ...kv});

List<String> kinds(List<JournalRecord> rs) => [for (final r in rs) r.text('k')];

/// The record as the next run reads it back from journey.jsonl.
List<JournalRecord> roundTrip(List<JournalRecord> rs) => [
  for (final r in rs)
    JournalRecord(jsonDecode(encodeJson(r)) as Map<String, Object?>),
];

Chunk chunk(int? s, int t, int m, int n) =>
    Chunk(s: s, t: t, m: m, n: n, pts: const []);

void main() {
  group('mergeRecords', () {
    test('keeps the multiset union and the earlier screenshot', () {
      final old = roundTrip([
        rec(1, 'in', {'session': 1}),
        rec(2, 'ss', {
          'file': 'A.jpg',
          'screenshot': 'screenshots/A.jpg',
          'notes': ['n'],
        }),
        rec(2, 'ss', {'file': 'A.jpg'}),
        rec(5, 'lv', {'level': 2}),
      ]);
      final fresh = [
        rec(1, 'in', {'session': 1}),
        rec(2, 'ss', {'file': 'A.jpg'}),
        rec(3, 'xp', {'amount': 10}),
        rec(3, 'xp', {'amount': 10}),
      ];
      final out = mergeRecords(old, fresh);
      expect(kinds(out), ['in', 'ss', 'ss', 'xp', 'xp', 'lv']);
      expect(out[1]['screenshot'], 'screenshots/A.jpg');
      expect(out[1]['notes'], isNotNull);
      expect(out[2]['screenshot'], isNull);
      expect(mergeRecords(out, fresh), hasLength(out.length));
    });

    test('a float and its JSON copy are one record', () {
      final old = roundTrip([
        rec(1, 'xp', {'rate': 1.5, 'big': 1e21, 'whole': 2.0}),
      ]);
      final out = mergeRecords(old, [
        rec(1, 'xp', {'rate': 1.5, 'big': 1e21, 'whole': 2.0}),
      ]);
      expect(out, hasLength(1));
    });

    test('keeps the note join of an earlier run', () {
      final first = joinNotes([
        rec(100, 'ss'),
        rec(101, 'sn', {'source': 'X', 'note': 'hi'}),
      ]).records;
      final old = roundTrip(mergeRecords(const [], first));
      // A later ss within noteTolerance makes a tie, so this run leaves the sn
      // record alone.
      final fresh = joinNotes([
        rec(100, 'ss'),
        rec(101, 'sn', {'source': 'X', 'note': 'hi'}),
        rec(102, 'ss'),
      ]);
      expect(fresh.joined, 0);
      final out = mergeRecords(old, fresh.records);
      expect(kinds(out), ['ss', 'ss']);
      expect(out[0]['notes'], isNotNull);
    });

    test('an sn far from the carried note stays', () {
      final old = roundTrip([
        rec(100, 'ss', {
          'notes': [
            {'source': 'X', 'note': 'hi'},
          ],
        }),
      ]);
      final out = mergeRecords(old, [
        rec(100, 'ss'),
        rec(110, 'sn', {'source': 'X', 'note': 'hi'}),
      ]);
      expect(kinds(out), ['ss', 'sn']);
    });
  });

  test('mergeTrail keeps the longer copy of a stretch', () {
    final out = mergeTrail(
      [chunk(1, 10, 5, 2), chunk(null, 30, 5, 1)],
      [chunk(1, 10, 5, 4), chunk(1, 20, 6, 1), chunk(1, 20, 5, 1)],
    );
    expect(
      [for (final c in out) (c.t, c.n)],
      [(10, 4), (20, 1), (20, 1), (30, 1)],
    );
    expect(out[1].m, 5);
    final none = mergeTrail([chunk(2, 1, 1, 1)], [chunk(1, 1, 1, 1)]);
    expect([for (final c in none) c.s], [1, 2]);
  });

  group('sessions', () {
    final old = <Object?>[
      {'start': 100, 'last': 150, 'computer': 'a', 'tz': 3600},
      {'start': 300, 'last': 400, 'computer': 'a'},
      'bad',
      {'last': 1},
    ];
    final fresh = <Object?>[
      {'start': 100, 'last': 200, 'computer': 'a', 'tz': 3600},
      {'start': 100, 'computer': 'b'},
    ];

    test('mergeSessions joins by computer and start', () {
      final s = mergeSessions([old, fresh]);
      expect(s, hasLength(3));
      expect(s[0]['computer'], 'a');
      expect(s[0]['last'], 200);
      expect(s[1]['computer'], 'b');
    });

    test('sessionAt finds the session and its time zone', () {
      final s = mergeSessions([old, fresh]);
      final cases = [
        (50, 0, 0, false),
        (150, 1, 3600, true),
        (100, 2, 0, false),
        (350, 3, 0, false),
        (500, 0, 0, false),
      ];
      for (final (t, index, tz, hasTz) in cases) {
        final got = sessionAt(s, t);
        expect(
          (got.index, got.tz, got.hasTz),
          (index, tz, hasTz),
          reason: '$t',
        );
      }
      final only = mergeSessions([fresh.sublist(0, 1)]);
      final after = sessionAt(only, 250);
      expect((after.index, after.tz, after.hasTz), (0, 3600, true));
    });

    test('lastOf falls back to the start', () {
      expect(lastOf({'start': 5}), 5);
      expect(lastOf({'start': 5, 'last': 9}), 9);
      expect(lastOf({}), 0);
    });
  });
}
