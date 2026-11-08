import '../savedvars/lexer.dart' show goQuote;
import 'journal.dart';

/// One trail point with an absolute time. It is written as [time, x, y, flags].
class TrailPoint {
  const TrailPoint(this.t, this.x, this.y, this.flags);

  /// Reads the array form.
  factory TrailPoint.fromJson(Object? json) {
    if (json is! List<Object?>) {
      throw const FormatException('a trail point is not an array');
    }
    if (json.length != 4) {
      throw FormatException('a trail point has ${json.length} values, want 4');
    }
    final t = asInt(json[0]);
    final x = asInt(json[1]);
    final y = asInt(json[2]);
    final flags = json[3];
    if (t == null || x == null || y == null || flags is! String) {
      throw const FormatException(
        'a trail point has a value of the wrong type',
      );
    }
    return TrailPoint(t, x, y, flags);
  }

  final int t;
  final int x;
  final int y;
  final String flags;

  List<Object?> toJson() => [t, x, y, flags];

  @override
  bool operator ==(Object other) =>
      other is TrailPoint &&
      other.t == t &&
      other.x == x &&
      other.y == y &&
      other.flags == flags;

  @override
  int get hashCode => Object.hash(t, x, y, flags);
}

/// One trail stretch: [s] is the start of its session, [t] the time of its
/// first point, [m] its map.
class Chunk {
  const Chunk({
    this.s,
    required this.t,
    required this.m,
    required this.n,
    required this.pts,
  });

  /// Reads the form that [toJson] writes.
  factory Chunk.fromJson(Object? json) {
    if (json is! Map<String, Object?>) {
      throw const FormatException('a trail chunk is not an object');
    }
    final t = asInt(json['t']);
    final m = asInt(json['m']);
    final n = asInt(json['n']);
    final pts = json['pts'];
    final s = json['s'];
    if (t == null ||
        m == null ||
        n == null ||
        (s != null && asInt(s) == null)) {
      throw const FormatException(
        'a trail chunk has a value of the wrong type',
      );
    }
    if (pts != null && pts is! List<Object?>) {
      throw const FormatException('a trail chunk has no list of points');
    }
    return Chunk(
      s: asInt(s),
      t: t,
      m: m,
      n: n,
      pts: [
        for (final p in (pts as List<Object?>?) ?? const [])
          TrailPoint.fromJson(p),
      ],
    );
  }

  final int? s;
  final int t;
  final int m;

  /// The number of points. A chunk read back from JSON keeps the stored count,
  /// as Go does, because the trail merge picks the chunk with the higher count.
  final int n;
  final List<TrailPoint> pts;

  Map<String, Object?> toJson() => {
    's': s,
    't': t,
    'm': m,
    'n': n,
    'pts': [for (final p in pts) p.toJson()],
  };
}

// The `.` of a Go pattern does not match "\n" only, so the flags class says the same.
final RegExp _pointPattern = RegExp(r'^([0-9]+),([0-9]+),([0-9]+),?([^\n]*)$');

/// Decodes a saved trail chunk { s, t, m, n, d, o }. Points without flags keep
/// the flags before them.
Chunk decodeChunk(Object? v) {
  if (v is! Map<String, Object?>) throw const BadChunkException();
  final t = asInt(v['t']);
  final m = asInt(v['m']);
  final d = v['d'];
  if (t == null || m == null || d is! String) throw const BadChunkException();
  final pts = <TrailPoint>[];
  var flags = '-';
  if (d.isNotEmpty) {
    for (final part in d.split(';')) {
      final g = _pointPattern.firstMatch(part);
      if (g == null) throw BadChunkException('point ${goQuote(part)}');
      final sec = int.tryParse(g[1]!);
      final x = int.tryParse(g[2]!);
      final y = int.tryParse(g[3]!);
      if (sec == null || x == null || y == null) {
        throw BadChunkException(
          'the number in the point ${goQuote(part)} is too large',
        );
      }
      if (g[4]!.isNotEmpty) flags = g[4]!;
      pts.add(TrailPoint(t + sec, x, y, flags));
    }
  }
  return Chunk(s: asInt(v['s']), t: t, m: m, n: pts.length, pts: pts);
}

/// Decodes the chunks of a saved trail { v, chunks, open }. The open copy is a
/// stretch whose logout step did not run, so it is kept too. It returns the
/// chunks and the number of chunks it could not decode.
({List<Chunk> chunks, int bad}) trail(Object? v) {
  if (v is! Map<String, Object?>) return (chunks: const [], bad: 0);
  final raw = [...asList(v['chunks'])];
  final open = v['open'];
  if (open is Map<String, Object?>) raw.add(open);
  final out = <Chunk>[];
  var bad = 0;
  for (final r in raw) {
    try {
      out.add(decodeChunk(r));
    } on BadChunkException {
      bad++;
    }
  }
  return (chunks: out, bad: bad);
}
