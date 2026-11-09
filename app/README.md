# WoW Journey

The desktop app that gathers the Memories addon data from the WoW folder. It uses the Dart core in
`../packages/memories_core`.

- Screens: the first-run wizard (`lib/src/ui/wizard_page.dart`) and the main window (`home_page.dart`) with three tabs:
  Overview, Website (`website_card.dart`, `website_section.dart`) and Settings (`settings_view.dart`). Settings live in
  `settings.json` in the app support folder.
- Theme: `lib/src/theme/`. `tokens.dart` is made from `web/base.css` by `make app-theme` (do not edit it by hand).
  `ak_theme.dart` is the `ThemeData` and the panel border; `ak_widgets.dart` has the header, the tabs, the tags and the
  panel title. The fonts are in `assets/fonts/` (the same families as the website, as TTF). `make theme-check` compares
  the app theme with the website, and `make app-shots` writes pictures of the screens.
- Language: the app has English, Deutsch, Français, Español, Italiano and Português. Every text comes from
  `AppLocalizations` (Flutter `gen_l10n`). The English catalog is `lib/l10n/app_en.arb`; the generated `lib/l10n/app_localizations*.dart` are committed, because `flutter analyze` does
  not generate them. After a change of an ARB file run `fvm flutter gen-l10n` in `app/`. The app follows the language of
  the system, and the Language row of Settings (`language` in `settings.json`, `null` for System) overrides it at once.
  The tray menu is rebuilt in the same language. Controllers keep codes and arguments (`upload/notice.dart`), and the
  screens turn them into text, so a notice on the screen changes language with the app. The 5 translations are machine
  translated (a note at the top of each ARB file); `test/l10n_test.dart` checks that each has the keys and placeholders of
  English. macOS reads the languages from `CFBundleLocalizations` in `macos/Runner/Info.plist`.
- Run: `fvm flutter run -d linux` (or `windows`, `macos`).
- Check: `make app-lint app-test` from the repository root.
