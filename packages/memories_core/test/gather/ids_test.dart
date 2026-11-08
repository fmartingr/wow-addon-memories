import 'package:memories_core/src/gather/ids.dart';
import 'package:test/test.dart';

void main() {
  test('slug', () {
    // The values of golang.org/x/text NFKD with the ASCII filter: letters
    // without a decomposition, such as ß, Ø and Ł, are dropped.
    final cases = {
      'Neral-Brumamar': 'neral-brumamar',
      'Ñandú': 'nandu',
      'Los Errantes': 'los-errantes',
      "  Zul'jin!! ": 'zul-jin',
      'Ⅻ ﬁre': 'xii-fire',
      '日本': '',
      'ß': '',
      'Ø': '',
      'Å': 'a',
      'Ł': '',
      'Æsir': 'sir',
      'Đorđe': 'ore',
      'İstanbul': 'istanbul',
      'ǅ': 'dz',
      '①': '1',
      'Ａｂ': 'ab',
    };
    cases.forEach((input, want) => expect(slug(input), want, reason: input));
  });

  test('region', () {
    expect(region('SET locale "esES"\nSET portal "EU"\n'), 'eu');
    expect(region('SET locale "esES"\n'), 'xx');
    expect(region('SET portal "__"'), 'xx');
  });

  test('ids', () {
    expect(baseId('eu', 'Brumamar', 'Neral', 'Player-1'), 'eu-brumamar-neral');
    expect(baseId('eu', 'Brumamar', '日本', 'Player-1'), 'eu-player-1');
    final taken = <String, String>{};
    final steps = [
      ('eu-brumamar-nandu', 'Player-1', 'eu-brumamar-nandu'),
      ('eu-los-errantes-nandu', 'Player-2', 'eu-los-errantes-nandu'),
      ('eu-brumamar-nandu', 'Player-1', 'eu-brumamar-nandu'),
      ('eu-brumamar-nandu', 'Player-3', 'eu-brumamar-nandu-forever'),
      ('eu-brumamar-nandu', 'Player-4', 'eu-brumamar-nandu-player-4'),
      ('eu-brumamar-nandu', 'player-4', 'eu-brumamar-nandu-player-4-2'),
    ];
    for (final (base, guid, want) in steps) {
      expect(assignId(taken, base, '_forever_', guid), want);
      expect(idPattern.hasMatch(want), isTrue, reason: want);
    }
  });

  test('isCandidate', () {
    const base = 'eu-brumamar-nandu';
    expect(isCandidate(base, base, '_forever_', 'Player-1'), isTrue);
    expect(isCandidate('$base-forever', base, '_forever_', 'Player-1'), isTrue);
    expect(
      isCandidate('$base-player-1', base, '_forever_', 'Player-1'),
      isTrue,
    );
    expect(
      isCandidate('$base-player-1-2', base, '_forever_', 'Player-1'),
      isTrue,
    );
    expect(
      isCandidate('$base-player-1-1', base, '_forever_', 'Player-1'),
      isFalse,
    );
    expect(
      isCandidate('$base-player-1-02', base, '_forever_', 'Player-1'),
      isFalse,
    );
    expect(
      isCandidate('$base-player-1-x', base, '_forever_', 'Player-1'),
      isFalse,
    );
    expect(isCandidate('eu-other', base, '_forever_', 'Player-1'), isFalse);
  });
}
