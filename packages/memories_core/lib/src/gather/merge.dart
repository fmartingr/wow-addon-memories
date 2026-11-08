/// Merges the records, trail and sessions of this gather with an earlier one.
library;

import '../journal/journal.dart';
import '../journal/trail.dart';
import 'json.dart';
import 'match.dart';
import 'notes.dart';

/// Derived keys are computed again on each run, so they do not make two
/// records different.
const Set<String> _derived = {'session', 'screenshot', 'notes'};

String _recordKey(JournalRecord r) => encodeJson({
  for (final e in r.entries)
    if (!_derived.contains(e.key)) e.key: e.value,
});

List<Note> _notesOf(Object? v) {
  if (v is! List<Object?>) return const [];
  final out = <Note>[];
  for (final n in v) {
    if (n is Note) {
      out.add(n);
    } else if (n is Map<String, Object?>) {
      final source = n['source'];
      final note = n['note'];
      out.add(Note(source is String ? source : '', note is String ? note : ''));
    }
  }
  return out;
}

/// Returns the multiset union of the records of an earlier run and of this
/// run, sorted by time. A record of this run takes the screenshot and notes of
/// its earlier copy when it has none of its own, so a screenshot that is gone
/// from the Screenshots folder stays linked. An sn record of this run that
/// [joinNotes] left alone, such as after a later ss made a tie, is dropped when
/// an earlier copy already carries its note on an ss within [noteTolerance].
List<JournalRecord> mergeRecords(
  List<JournalRecord> old,
  List<JournalRecord> fresh,
) {
  final queue = <String, List<JournalRecord>>{};
  final head = <String, int>{};
  for (final r in old) {
    (queue[_recordKey(r)] ??= []).add(r);
  }
  final carried = <Note, List<int>>{};
  for (final r in fresh) {
    final k = _recordKey(r);
    final q = queue[k];
    final h = head[k] ?? 0;
    if (q == null || h >= q.length) continue;
    final match = q[h];
    for (final key in const ['screenshot', 'notes']) {
      if (!r.containsKey(key) && match[key] != null) {
        r[key] = match[key];
        if (key == 'notes') {
          for (final n in _notesOf(r[key])) {
            (carried[n] ??= []).add(r.time);
          }
        }
      }
    }
    head[k] = h + 1;
  }
  final out = <JournalRecord>[];
  for (final r in fresh) {
    if (r.text('k') == 'sn' &&
        _takeCarried(carried, Note(r.text('source'), r.text('note')), r.time)) {
      continue;
    }
    out.add(r);
  }
  for (final e in queue.entries) {
    out.addAll(e.value.skip(head[e.key] ?? 0));
  }
  sortStable(out, (a, b) => a.time.compareTo(b.time));
  return out;
}

bool _takeCarried(Map<Note, List<int>> carried, Note n, int t) {
  final times = carried[n];
  if (times == null) return false;
  for (var i = 0; i < times.length; i++) {
    if (absDiff(times[i], t) <= noteTolerance) {
      times.removeAt(i);
      return true;
    }
  }
  return false;
}

(int, int, int) _chunkKey(Chunk c) => (c.s ?? -1, c.t, c.m);

/// Joins the trail chunks of two runs. A stretch grows while it is open, so
/// chunks with the same session, start and map are one chunk, and the one with
/// more points wins.
List<Chunk> mergeTrail(List<Chunk> old, List<Chunk> fresh) {
  final best = <(int, int, int), Chunk>{};
  for (final c in [...old, ...fresh]) {
    final k = _chunkKey(c);
    final b = best[k];
    if (b == null || c.n >= b.n) best[k] = c;
  }
  final out = best.values.toList()
    ..sort((x, y) {
      final a = _chunkKey(x);
      final b = _chunkKey(y);
      if (a.$2 != b.$2) return a.$2.compareTo(b.$2);
      if (a.$1 != b.$1) return a.$1.compareTo(b.$1);
      return a.$3.compareTo(b.$3);
    });
  return out;
}

({String computer, int start})? _keyOf(Map<String, Object?> s) {
  final start = asInt(s['start']);
  if (start == null) return null;
  final computer = s['computer'];
  return (computer: computer is String ? computer : '', start: start);
}

/// The time a session was last seen, else its start.
int lastOf(Map<String, Object?> s) =>
    asInt(s['last']) ?? asInt(s['start']) ?? 0;

/// Joins session lists. Sessions with the same computer and start are one
/// session; the one that ran longest wins, and a later list wins a tie.
List<Map<String, Object?>> mergeSessions(List<List<Object?>> lists) {
  final best = <({String computer, int start}), Map<String, Object?>>{};
  for (final list in lists) {
    for (final v in list) {
      if (v is! Map<String, Object?>) continue;
      final k = _keyOf(v);
      if (k == null) continue;
      final b = best[k];
      if (b == null || lastOf(v) >= lastOf(b)) best[k] = v;
    }
  }
  final out = best.values.toList()
    ..sort((x, y) {
      final a = _keyOf(x)!;
      final b = _keyOf(y)!;
      if (a.start != b.start) return a.start.compareTo(b.start);
      return compareUtf8(a.computer, b.computer);
    });
  return out;
}

/// The session that contains a time: its 1-based [index] or 0, and the UTC
/// offset [tz] of that session, else of the latest session that started at or
/// before the time. The offset names the screenshot files of that time.
typedef SessionMatch = ({int index, int tz, bool hasTz});

/// Returns the session that contains [t]. Sessions of two computers can
/// overlap; the one that started last wins. [sessions] are sorted by start, as
/// [mergeSessions] returns them.
SessionMatch sessionAt(List<Map<String, Object?>> sessions, int t) {
  var found = false;
  int? tz;
  final after = searchFirst(
    sessions.length,
    (i) => (_keyOf(sessions[i])?.start ?? 0) > t,
  );
  for (var i = after - 1; i >= 0; i--) {
    if (t <= lastOf(sessions[i])) {
      final z = asInt(sessions[i]['tz']);
      return (index: i + 1, tz: z ?? 0, hasTz: z != null);
    }
    if (!found) {
      found = true;
      tz = asInt(sessions[i]['tz']);
    }
  }
  return (index: 0, tz: tz ?? 0, hasTz: tz != null);
}
