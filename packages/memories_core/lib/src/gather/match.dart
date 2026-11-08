/// Matches screenshot records with the files in the Screenshots folder.
library;

/// The widest gap in seconds between a record and the time in a screenshot
/// file name.
const int shotTolerance = 2;

/// The only form of screenshot file name that the gather reads or copies.
final RegExp fileNamePattern = RegExp(
  r'^WoWScrnShot_[0-9]{6}_[0-9]{6}\.(jpg|png|tga)$',
);

const int _prefix = 'WoWScrnShot_'.length;
final RegExp _stamp = RegExp(
  r'^([0-9]{2})([0-9]{2})([0-9]{2})_([0-9]{2})([0-9]{2})([0-9]{2})$',
);

/// A record that names a screenshot: its predicted file, its time, and the
/// UTC offset of the client clock.
class Shot {
  const Shot({
    required this.file,
    required this.t,
    this.tz = 0,
    required this.hasTz,
  });

  final String file;
  final int t;
  final int tz;
  final bool hasTz;
}

/// Returns the unix time of a screenshot file name, or null. The name holds
/// the client's local time, [tz] seconds ahead of UTC.
int? fileTime(String name, int tz) {
  if (name.length < _prefix + 13) return null;
  final g = _stamp.firstMatch(name.substring(_prefix, _prefix + 13));
  if (g == null) return null;
  final month = int.parse(g[1]!);
  final day = int.parse(g[2]!);
  final yy = int.parse(g[3]!);
  final hour = int.parse(g[4]!);
  final minute = int.parse(g[5]!);
  final second = int.parse(g[6]!);
  // Go reads a two-digit year 69 to 99 as 19xx, and 00 to 68 as 20xx.
  final year = yy >= 69 ? 1900 + yy : 2000 + yy;
  if (month < 1 || month > 12 || hour > 23 || minute > 59 || second > 59) {
    return null;
  }
  if (day < 1 || day > DateTime.utc(year, month + 1, 0).day) return null;
  final utc = DateTime.utc(year, month, day, hour, minute, second);
  return utc.millisecondsSinceEpoch ~/ 1000 - tz;
}

/// Returns, for each shot, the index of its file in [files], or -1. A shot
/// takes the file with its exact name first, else the nearest unclaimed file
/// within [shotTolerance] seconds. A tie matches nothing. [claimed] holds files
/// that earlier runs gave to other records; this adds the files it gives.
List<int> matchShots(
  List<Shot> shots,
  List<String> files,
  Set<String> claimed,
) {
  final out = List<int>.filled(shots.length, -1);
  final index = <String, int>{};
  for (var i = 0; i < files.length; i++) {
    index[files[i]] = i;
  }
  for (var i = 0; i < shots.length; i++) {
    final j = index[shots[i].file];
    if (j != null && !claimed.contains(shots[i].file)) {
      claimed.add(shots[i].file);
      out[i] = j;
    }
  }

  final utc = List<int>.filled(files.length, 0);
  final bySecond = <int, List<int>>{};
  for (var j = 0; j < files.length; j++) {
    final t = fileTime(files[j], 0);
    if (t != null) {
      utc[j] = t;
      (bySecond[t] ??= []).add(j);
    }
  }
  final pairs = <Pair>[];
  for (var i = 0; i < shots.length; i++) {
    final s = shots[i];
    if (out[i] >= 0 || !s.hasTz) continue;
    final near = <int>[];
    for (var d = -shotTolerance; d <= shotTolerance; d++) {
      near.addAll(bySecond[s.t + s.tz + d] ?? const []);
    }
    // The ascending file order keeps the stable sort in matchNearest deterministic.
    near.sort();
    for (final j in near) {
      if (!claimed.contains(files[j])) {
        pairs.add(Pair(i, j, absDiff(utc[j] - s.tz, s.t)));
      }
    }
  }
  matchNearest(pairs, (j) => !claimed.contains(files[j]), (i, j) {
    claimed.add(files[j]);
    out[i] = j;
  });
  return out;
}

/// A possible match of [a] to [b] at a distance.
class Pair {
  const Pair(this.a, this.b, this.dist);

  final int a;
  final int b;
  final int dist;
}

/// Gives each a its nearest free b, nearest pairs first. An a with two free b
/// at its nearest distance gets nothing. [take] must make b no longer free.
void matchNearest(
  List<Pair> pairs,
  bool Function(int b) free,
  void Function(int a, int b) take,
) {
  sortStable(pairs, (x, y) => x.dist.compareTo(y.dist));
  final byA = <int, List<Pair>>{};
  for (final c in pairs) {
    (byA[c.a] ??= []).add(c);
  }
  final done = <int>{};
  for (final c in pairs) {
    if (done.contains(c.a) || !free(c.b)) continue;
    done.add(c.a);
    final tie = byA[c.a]!.any(
      (o) => o.b != c.b && o.dist == c.dist && free(o.b),
    );
    if (!tie) take(c.a, c.b);
  }
}

int absDiff(int a, int b) => a > b ? a - b : b - a;

/// Sorts [list] in place and keeps the order of equal items, as Go's
/// `sort.SliceStable` does. Dart's own sort is not stable.
void sortStable<T>(List<T> list, int Function(T a, T b) compare) {
  final indexed = [for (var i = 0; i < list.length; i++) (i, list[i])];
  indexed.sort((x, y) {
    final c = compare(x.$2, y.$2);
    return c != 0 ? c : x.$1.compareTo(y.$1);
  });
  for (var i = 0; i < list.length; i++) {
    list[i] = indexed[i].$2;
  }
}

/// Returns the first index in 0..n for which [f] is true, as Go's
/// `sort.Search` does; [f] must be false and then true.
int searchFirst(int n, bool Function(int i) f) {
  var lo = 0;
  var hi = n;
  while (lo < hi) {
    final mid = (lo + hi) >> 1;
    if (f(mid)) {
      hi = mid;
    } else {
      lo = mid + 1;
    }
  }
  return lo;
}
