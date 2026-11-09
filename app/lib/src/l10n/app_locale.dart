/// Which language the app shows: the setting, else the language of the
/// system, else English.
library;

import 'dart:ui';

import '../../l10n/app_localizations.dart';

/// The language codes of the app, English first.
const List<String> appLanguageCodes = ['en', 'de', 'fr', 'es', 'it', 'pt'];

/// The name of each language in that language, for the Language setting.
const Map<String, String> appLanguageNames = {
  'en': 'English',
  'de': 'Deutsch',
  'fr': 'Français',
  'es': 'Español',
  'it': 'Italiano',
  'pt': 'Português',
};

/// [value] when it is the code of a supported language, else null.
String? validLanguageCode(Object? value) =>
    value is String && appLanguageCodes.contains(value) ? value : null;

/// The first of [preferred] that the app supports, matched on the language
/// part only (`pt_PT` is Portuguese, `es_419` is Spanish), else English.
Locale resolveAppLocale(Iterable<Locale> preferred) {
  for (final locale in preferred) {
    if (appLanguageCodes.contains(locale.languageCode)) {
      return Locale(locale.languageCode);
    }
  }
  return const Locale('en');
}

/// The locale to show: the [language] setting, or the system [preferred]
/// list when the setting is null.
Locale effectiveLocale(String? language, Iterable<Locale> preferred) {
  final code = validLanguageCode(language);
  return code == null ? resolveAppLocale(preferred) : Locale(code);
}

/// The texts for [locale], with no widget tree.
AppLocalizations textsFor(Locale locale) => lookupAppLocalizations(locale);
