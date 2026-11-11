import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:wow_journey/l10n/app_localizations.dart';
import 'package:wow_journey/src/l10n/app_locale.dart';

Map<String, Object?> _arb(String code) =>
    jsonDecode(File('lib/l10n/app_$code.arb').readAsStringSync())
        as Map<String, Object?>;

void main() {
  group('the English catalog', () {
    final en = _arb('en');
    final keys = en.keys.where((k) => !k.startsWith('@'));

    test('has messages', () {
      expect(keys, isNotEmpty);
    });

    for (final key in keys) {
      test('$key has a description', () {
        final meta = en['@$key'];
        expect(meta, isA<Map<String, Object?>>(), reason: key);
        final description = (meta as Map<String, Object?>)['description'];
        expect(description, isA<String>(), reason: key);
        expect(description as String, isNotEmpty, reason: key);
      });
    }

    test('every placeholder of a message is declared', () {
      for (final key in keys) {
        final text = en[key]! as String;
        final meta = (en['@$key']! as Map<String, Object?>)['placeholders'];
        final declared = meta is Map<String, Object?>
            ? meta.keys.toSet()
            : <String>{};
        final used = RegExp(r'\{(\w+)(?:,|\})')
            .allMatches(text)
            .map((m) => m[1]!)
            .toSet();
        expect(used, declared, reason: key);
      }
    });
  });

  group('the local viewer texts', () {
    const keys = [
      'viewCharacter',
      'viewCharacterLabel',
      'trayViewJourney',
      'viewerStartFailed',
      'viewerOpenFailed',
    ];
    for (final code in appLanguageCodes) {
      test('$code has them', () {
        final arb = _arb(code);
        for (final key in keys) {
          expect(arb[key], isA<String>(), reason: '$code $key');
          expect((arb[key] as String).trim(), isNotEmpty, reason: '$code $key');
        }
        expect(arb['viewCharacterLabel'], contains('{name}'));
      });
    }
  });

  group('the languages', () {
    test('are the 6 of the app, English first', () {
      expect(appLanguageCodes, ['en', 'de', 'fr', 'es', 'it', 'pt']);
      expect(appLanguageNames.keys, appLanguageCodes);
      expect(
        AppLocalizations.supportedLocales.map((l) => l.languageCode).toSet(),
        appLanguageCodes.toSet(),
      );
    });

    for (final code in appLanguageCodes) {
      test('$code has a catalog that names its locale', () {
        expect(_arb(code)['@@locale'], code);
      });
    }

    test('each language file starts with the machine translation note', () {
      for (final code in appLanguageCodes.skip(1)) {
        expect(
          _arb(code)['@@x-note'],
          'Machine translated. Corrections are welcome.',
          reason: code,
        );
      }
    });
  });

  group('parity with English', () {
    final en = _arb('en');
    final enKeys = en.keys.where((k) => !k.startsWith('@')).toSet();

    // The {name} arguments that print a value. The selector of a plural
    // (`{count, plural, ...}`) is not one: a branch must print it itself.
    Set<String> placeholders(String text) => {
      for (final m in RegExp(r'\{(\w+)\}').allMatches(text)) m[1]!,
    };

    // Names and codes that are the same word as in English, per language.
    const sameAsEnglish = {
      'de': {
        'appTitle',
        'statusSemantics',
        'countScreenshots',
        'countSemantics',
        'sizeKb',
        'sizeMb',
        'sizeGb',
        'sizeTb',
        'classPaladin',
        'languageSystem',
        'versionTitle',
        'versionText',
        'namedError',
      },
      'fr': {
        'appTitle',
        'classPaladin',
        'classMage',
        'versionTitle',
        'versionText',
      },
      'es': {
        'appTitle',
        'countSemantics',
        'sizeKb',
        'sizeMb',
        'sizeGb',
        'sizeTb',
        'versionText',
        'namedError',
      },
      'it': {
        'appTitle',
        'countSemantics',
        'sizeKb',
        'sizeMb',
        'sizeGb',
        'sizeTb',
        'versionText',
        'namedError',
      },
      'pt': {
        'appTitle',
        'statusSemantics',
        'countSemantics',
        'sizeKb',
        'sizeMb',
        'sizeGb',
        'sizeTb',
        'versionText',
        'namedError',
      },
    };

    for (final code in appLanguageCodes.skip(1)) {
      final arb = _arb(code);
      final keys = arb.keys.where((k) => !k.startsWith('@')).toSet();

      test('$code has exactly the keys of English', () {
        expect(keys.difference(enKeys), isEmpty, reason: 'extra keys');
        expect(enKeys.difference(keys), isEmpty, reason: 'missing keys');
      });

      test('$code has the placeholders of English in every message', () {
        for (final key in enKeys) {
          expect(
            placeholders(arb[key]! as String),
            placeholders(en[key]! as String),
            reason: '$code $key',
          );
        }
      });

      test('$code keeps the plural form of every plural message', () {
        for (final key in enKeys) {
          if ((en[key]! as String).contains(', plural,')) {
            expect(arb[key]! as String, contains(', plural,'), reason: key);
          }
        }
      });

      test('$code has a non-empty text that is not the English one', () {
        for (final key in enKeys) {
          final text = arb[key]! as String;
          expect(text.trim(), isNotEmpty, reason: '$code $key');
          if (!sameAsEnglish[code]!.contains(key)) {
            expect(text, isNot(en[key]), reason: '$code $key');
          }
        }
      });

      test('$code keeps the program words and commands as they are', () {
        for (final key in enKeys) {
          final enText = en[key]! as String;
          for (final word in [
            '/reload',
            'index.json',
            '_retail_',
            'https://',
          ]) {
            if (enText.contains(word)) {
              expect(arb[key]! as String, contains(word), reason: '$code $key');
            }
          }
        }
      });
    }
  });

  group('resolveAppLocale', () {
    test('takes the language part of a supported locale', () {
      expect(resolveAppLocale(const [Locale('pt', 'PT')]), const Locale('pt'));
      expect(resolveAppLocale(const [Locale('de', 'AT')]), const Locale('de'));
      expect(resolveAppLocale(const [Locale('es', '419')]), const Locale('es'));
      expect(resolveAppLocale(const [Locale('fr', 'CA')]), const Locale('fr'));
      expect(resolveAppLocale(const [Locale('it')]), const Locale('it'));
    });

    test('falls back to English for the rest', () {
      expect(resolveAppLocale(const [Locale('ru', 'RU')]), const Locale('en'));
      expect(resolveAppLocale(const [Locale('ko')]), const Locale('en'));
      expect(resolveAppLocale(const []), const Locale('en'));
    });

    test('takes the first language of the list that the app has', () {
      expect(
        resolveAppLocale(const [Locale('ru'), Locale('it'), Locale('de')]),
        const Locale('it'),
      );
    });
  });

  group('effectiveLocale', () {
    test('the setting wins over the system', () {
      expect(effectiveLocale('es', const [Locale('de')]), const Locale('es'));
    });

    test('null follows the system', () {
      expect(effectiveLocale(null, const [Locale('de')]), const Locale('de'));
      expect(effectiveLocale(null, const [Locale('ru')]), const Locale('en'));
    });

    test('an unsupported code follows the system', () {
      expect(effectiveLocale('ru', const [Locale('fr')]), const Locale('fr'));
    });
  });

  test('validLanguageCode accepts only the 6 codes', () {
    expect(validLanguageCode('de'), 'de');
    expect(validLanguageCode('ru'), isNull);
    expect(validLanguageCode(''), isNull);
    expect(validLanguageCode(null), isNull);
    expect(validLanguageCode(7), isNull);
  });
}
