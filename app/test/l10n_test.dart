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
