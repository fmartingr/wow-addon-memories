import 'dart:io';

import 'package:memories_core/memories_core.dart';
import 'package:memories_core/src/gather/files.dart';
import 'package:memories_core/src/gather/json.dart';
import 'package:memories_core/src/gather/merge.dart';
import 'package:memories_core/src/gather/notes.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String _mergeDir = '../../testdata/merge';
const List<String> _files = ['character.json', 'journey.jsonl', 'trail.jsonl'];

/// The notes of a record as `Note`s, which write their keys as source, note.
/// A note read back from a file is a plain map, which writes them sorted. The
/// server's validator writes source, note for every note, so the contract
/// starts from that form.
List<JournalRecord> _records(String dir) =>
    readJsonl(p.join(dir, 'journey.jsonl'), (row) {
      final rec = JournalRecord(row! as Map<String, Object?>);
      final notes = rec['notes'];
      if (notes is List<Object?>) {
        rec['notes'] = [
          for (final n in notes.cast<Map<String, Object?>>())
            Note(n['source']! as String, n['note']! as String),
        ];
      }
      return rec;
    });

Map<String, List<int>> _merge(String oldDir, String freshDir) {
  final oldChar = readJson(p.join(oldDir, 'character.json'))!;
  final freshChar = readJson(p.join(freshDir, 'character.json'))!;
  final records = mergeRecords(_records(oldDir), _records(freshDir));
  final trail = mergeTrail(
    readJsonl(p.join(oldDir, 'trail.jsonl'), Chunk.fromJson),
    readJsonl(p.join(freshDir, 'trail.jsonl'), Chunk.fromJson),
  );
  final sessions = mergeSessions([
    oldChar['sessions']! as List<Object?>,
    freshChar['sessions']! as List<Object?>,
  ]);
  for (final rec in records) {
    final i = sessionAt(sessions, rec.time).index;
    rec['session'] = i > 0 ? i : null;
  }
  final addons = <String, Object?>{
    ...oldChar['addons']! as Map<String, Object?>,
    ...freshChar['addons']! as Map<String, Object?>,
  };
  final doc = <String, Object?>{
    ...freshChar,
    'sessions': sessions,
    'addons': {
      for (final e in addons.entries)
        e.key: () {
          final a = e.value! as Map<String, Object?>;
          return Ordered({
            'counts': a['counts'],
            'snap': a['snap'],
            'schema': a['schema'],
            'writtenBy': a['writtenBy'],
          });
        }(),
    },
  };
  return {
    'character.json': encodeJsonBytes(doc, indent: true),
    'journey.jsonl': [for (final r in records) ...encodeJsonBytes(r)],
    'trail.jsonl': [
      for (final c in trail) ...encodeJsonBytes(Ordered(c.toJson())),
    ],
  };
}

void main() {
  test(
    'the merge of testdata/merge/old and fresh is testdata/merge/expected',
    () {
      final got = _merge(p.join(_mergeDir, 'old'), p.join(_mergeDir, 'fresh'));
      final expected = p.join(_mergeDir, 'expected');
      if (Platform.environment['UPDATE'] == '1') {
        for (final e in got.entries) {
          File(p.join(expected, e.key)).writeAsBytesSync(e.value);
        }
        return;
      }
      for (final name in _files) {
        expect(
          File(p.join(expected, name)).readAsBytesSync(),
          got[name],
          reason: '$name differs; review a change, then run with UPDATE=1',
        );
      }
    },
  );

  test(
    'merging the expected data with the fresh data again changes nothing',
    () {
      final once = p.join(_mergeDir, 'expected');
      final again = _merge(once, p.join(_mergeDir, 'fresh'));
      for (final name in _files) {
        expect(again[name], File(p.join(once, name)).readAsBytesSync());
      }
    },
  );
}
