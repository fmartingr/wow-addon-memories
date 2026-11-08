# WoW Journey

The desktop app that gathers the Memories addon data from the WoW folder. It uses the Dart core in
`../packages/memories_core`.

- Screens: the first-run wizard (`lib/src/ui/wizard_page.dart`), the main screen (`home_page.dart`) and the settings
  (`settings_page.dart`). Settings live in `settings.json` in the app support folder.
- Run: `fvm flutter run -d linux` (or `windows`, `macos`).
- Check: `make app-lint app-test` from the repository root.
