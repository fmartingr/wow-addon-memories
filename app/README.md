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
- Run: `fvm flutter run -d linux` (or `windows`, `macos`).
- Check: `make app-lint app-test` from the repository root.
