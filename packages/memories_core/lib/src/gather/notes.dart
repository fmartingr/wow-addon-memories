/// Joins the screenshot notes of other addons with their screenshot records.
library;

import '../journal/journal.dart';
import 'json.dart';
import 'match.dart';

/// The widest time gap between an sn line and the ss line it joins by time.
const int noteTolerance = 2;

/// A screenshot note from another addon.
class Note implements GoStruct {
  const Note(this.source, this.note);

  final String source;
  final String note;

  @override
  Map<String, Object?> get goFields => {'source': source, 'note': note};

  @override
  bool operator ==(Object other) =>
      other is Note && other.source == source && other.note == note;

  @override
  int get hashCode => Object.hash(source, note);

  @override
  String toString() => 'Note($source, $note)';
}

/// Moves each sn record into the notes of its ss record and returns the
/// records without the joined sn records. An sn joins the ss with the same
/// file, else the nearest ss within [noteTolerance] seconds that no other sn
/// took. A tie or no match keeps the sn record.
({List<JournalRecord> records, int joined}) joinNotes(
  List<JournalRecord> records,
) {
  final shots = <int>[];
  final notes = <int>[];
  for (var i = 0; i < records.length; i++) {
    switch (records[i].text('k')) {
      case 'ss':
        shots.add(i);
      case 'sn':
        notes.add(i);
    }
  }
  final shotByFile = <String, int>{};
  for (final s in shots) {
    final file = records[s].text('file');
    if (file.isNotEmpty) shotByFile.putIfAbsent(file, () => s);
  }
  final target = <int, int>{};
  final taken = <int>{};
  for (final n in notes) {
    final file = records[n].text('file');
    final s = shotByFile[file];
    if (s != null && file.isNotEmpty) {
      target[n] = s;
      taken.add(s);
    }
  }

  final byTime = [...shots];
  sortStable(byTime, (a, b) => records[a].time.compareTo(records[b].time));
  final pairs = <Pair>[];
  for (final n in notes) {
    if (target.containsKey(n)) continue;
    final t = records[n].time;
    final from = searchFirst(
      byTime.length,
      (i) => records[byTime[i]].time >= t - noteTolerance,
    );
    final near = <int>[];
    for (final s in byTime.skip(from)) {
      if (records[s].time > t + noteTolerance) break;
      near.add(s);
    }
    // The record order keeps the stable sort in matchNearest deterministic.
    near.sort();
    for (final s in near) {
      if (taken.contains(s) || records[s].text('result') == 'failed') continue;
      pairs.add(Pair(n, s, absDiff(t, records[s].time)));
    }
  }
  matchNearest(pairs, (s) => !taken.contains(s), (n, s) {
    target[n] = s;
    taken.add(s);
  });

  final attached = <int, List<Note>>{};
  for (final n in notes) {
    final s = target[n];
    if (s != null) {
      (attached[s] ??= []).add(
        Note(records[n].text('source'), records[n].text('note')),
      );
    }
  }
  final out = <JournalRecord>[];
  var joined = 0;
  for (var i = 0; i < records.length; i++) {
    if (target.containsKey(i)) {
      joined++;
      continue;
    }
    final ns = attached[i];
    if (ns != null) records[i]['notes'] = ns;
    out.add(records[i]);
  }
  return (records: out, joined: joined);
}
