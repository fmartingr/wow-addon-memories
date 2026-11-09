# Language support: addons, companion app and website in the EU WoW languages

## Why

The addons, the companion app **WoW Journey** and the website show English text only. Most EU players use a German,
French, Spanish, Italian or Portuguese game client. Today they read an English settings page in the game, an English
app, and an English website around zone and item names in their own language.

This change shows each part in the language of the player:

- The addons follow the language of the game client.
- The app follows the language of the operating system, with a setting that overrides it.
- The website follows a saved choice of the viewer, then the language of the character's game client, then the
  browser language.

It also fixes two English-only lookups that fail on other clients: the last-boss table of the addon and the map zone
labels of the viewer.

## What

The supported languages are these 6. The "WoW locale" column is what `GetLocale()` returns. The "Code" column is the
language code that the app and the website use.

| Language | WoW locale | Code |
| --- | --- | --- |
| English | `enUS` (an enGB client also returns `enUS`) | `en` |
| Deutsch | `deDE` | `de` |
| Français | `frFR` | `fr` |
| Español | `esES`, and `esMX` | `es` |
| Italiano | `itIT` | `it` |
| Português | `ptBR` (the EU Portuguese client also uses `ptBR`) | `pt` |

Every other locale (`ruRU`, `koKR`, `zhCN`, `zhTW`) and every other OS or browser language falls back to English.

- **AC1 — Addon language:** on a client whose `GetLocale()` is one of the 6 WoW locales, every text that the addons
  show is in that language. This includes chat lines, `/memories` help and status, the minimap tooltip, the save
  reminder, the low-health popup, the data-guard popups, the error frame, and every label and tooltip of the Settings
  page (kind names and group names included). On any other locale the text is English.
- **AC2 — Addon list:** each of the 6 TOC files has `## Title-<locale>:` and `## Notes-<locale>:` lines for `deDE`,
  `frFR`, `esES`, `esMX`, `itIT` and `ptBR`. The game addon list shows the translated title and notes.
- **AC3 — Stored data does not change:** the SavedVariables format stays the same. Kind group names in
  `MemoriesDB.kinds`, journal note tokens (`"restored backup"`, `"started fresh"`, `"new character"`) and every recorded
  field token stay English. The commands `/memories`, `/mem`, `errors`, `options`, `settings` and `status` stay English.
- **AC4 — Character language recorded:** the addon writes `MemoriesDB.char.locale = GetLocale()` at each login. After
  the next gather and upload, `character.json` on the website has `"locale": "<WoW locale>"`. The server accepts the
  upload. Characters that do not have the field still upload and show.
- **AC5 — Dungeon clears on every client:** the addon finds the last boss of a dungeon or raid by the encounter ID of
  `ENCOUNTER_END`. It uses the English name only when the ID is not in the table. A clear counts on a German, French,
  Spanish, Italian or Portuguese client.
- **AC6 — App language:** the app shows every screen, dialog, notice, tooltip, semantics label and tray menu item in the
  language of the OS when it is one of the 6. Otherwise the app is English.
- **AC7 — App language setting:** Settings has a **Language** row with the choices System, English, Deutsch, Français,
  Español, Italiano and Português. System is the default. A change applies at once to every screen and to the tray
  menu, with no restart. The choice persists in `settings.json`. A `settings.json` without the key loads as System.
- **AC8 — App error text:** the app shows translated text for each known error code from `memories_core` and from the
  website API. The app shows the English text from the server only for an unknown code or for the `problems` reasons of
  a rejected upload.
- **AC9 — Website language order:** the server picks the page language in this order:
  1. a `?lang=<code>` query on the request,
  2. the `lang` cookie,
  3. on a character page only: the `locale` of the character,
  4. the `Accept-Language` header,
  5. English.
  An unknown code at any step goes to the next step.
- **AC10 — Website picker:** the home page, the 404 page and the character page have a language picker in the footer.
  A choice sets the cookie `lang=<code>; Path=/; Max-Age=31536000; SameSite=Lax` and shows the same page in that
  language. On the character page, the hash state (tab, camera, selection) stays.
- **AC11 — Website pages:** the home page, the 404 page and every text of the character page (tabs, labels, buttons,
  aria labels, tooltips, toasts, journal log lines, legends, notices, slot names, standings, qualities, races, classes,
  layer and profession names) show in the chosen language. `<html lang>` is the chosen code. Dates and numbers use the
  chosen language through `Intl`.
- **AC12 — Wowhead language:** gear links point to the Wowhead page in the page language, so the tooltip shows
  translated item names. English uses the plain URL.
- **AC13 — Map zone labels:** the 50 zone labels of the map show the official name of the zone in the page language.
  A zone with no translation shows its English name.
- **AC14 — Catalog parity:** a test in each part fails when a language catalog misses a key that English has, or has a
  key that English does not have.

## Constraints

- **Must:**
  - Keep every key and value of the SavedVariables, the gather output, the upload API and the stored files that exist
    today. The only data change is the new optional `char.locale` key.
  - Keep the URLs of the website. The language is never a path segment.
  - Keep the Content Security Policy of each page. No inline script and no inline style.
  - Keep `X-Robots-Tag: noindex, nofollow` on character pages and data files.
  - Use plain ES modules with no build step and no npm dependency on the website.
  - Treat every value from a data file as untrusted player text. Put it on the page with `textContent` or `esc()`.
    Translated strings with placeholders get their values escaped the same way.
  - Keep the addons free of libraries. Use plain Lua tables, as `docs/sub-addon-api.md` asks of sub-addons.
  - Keep sub-addons independent of a new core API. Each addon carries its own strings.
  - Put a note at the top of each non-English catalog: "Machine translated. Corrections are welcome."
  - Write the English strings as they are today. The English user sees no text change, except the fixed plural in
    AC11 ("1 kill", not "1 kills").
- **Must Not:**
  - Translate data that comes from the game client: zone, item, quest, boss, NPC, faction and skill names in the
    journal. They stay as recorded.
  - Translate the admin UI, the API `message` field, or the `problems` reasons.
  - Change the server `kinds.json`, `docs/kinds.md` or the Dart journal parser.
  - Add a font. The 6 languages use Latin script, which Cinzel and Alegreya Sans cover.
- **Out of Scope:**
  - Russian and the Asian languages.
  - Native window titles and native menus of the app on Windows and Linux (`Runner.rc`, `main.cpp`,
    `my_application.cc`) and the stock macOS `MainMenu.xib`.
  - A language override inside the addon.
  - Detection of the language of characters uploaded before this change.
  - Translated docs (`README.md`, `docs/`).

## Decisions

| # | Decision | Reason |
| --- | --- | --- |
| D1 | 6 languages: en, de, fr, es, it, pt. No Russian. | The user cut Russian. Cinzel has no Cyrillic, so Russian needed font work. |
| D2 | The implementing agent writes every translation. Each catalog has the "Machine translated" note. | No native reviewer is available. The note invites corrections. |
| D3 | The addon follows `GetLocale()` only. `esMX` uses Spanish. | Standard WoW practice. The game already shows its own UI in that language. |
| D4 | Addon strings use English keys: `L["Save reminder"]`. A metatable returns the key when a translation is missing. | No `enUS` file to keep in sync. A missing translation shows English, never `nil`. Pattern from the Warcraft Wiki. |
| D5 | Each addon has its own `Locales.lua` with all its languages. | Sub-addons stay free of a new core API and of an API version change. Each file is small. |
| D6 | Kind groups stay English in `MemoriesDB.kinds`. Only the display label is translated. | `journal.dart:84`, `Status.lua:24` and `Settings.SetGroup` read the group as a token. |
| D7 | The addon records `char.locale`. It passes to `character.json` through `...c.char` (`gather.dart:785`). | The website needs the language of the character's client. The server accepts extra character keys as text (`validate/character.go:98`). |
| D8 | Last-boss lookup by encounter ID first, English name second. | Encounter IDs do not depend on the client language. Custom WoW Forever bosses have no public ID, so the name stays as a fallback. |
| D9 | The app uses Flutter `gen_l10n` with ARB files in `app/lib/l10n/`, and `generate: true`. | The official Flutter way. Flutter 3.47.5 writes the generated code into the source tree; `package:flutter_gen` is gone. |
| D10 | The app follows the OS language, with a Language setting that overrides it at once. | The user chose it. |
| D11 | The app maps known error codes to text. Server text shows as is only for unknown codes and upload problems. | API messages stay English (user choice). Codes are stable. |
| D12 | The app keeps codes and arguments in its controllers, not finished strings. | A language change must re-translate notices that are already on the screen. |
| D13 | The website order is `?lang` > cookie > character locale > `Accept-Language` > English. | The user chose it. A saved viewer choice wins over the character. |
| D14 | The picker is a set of plain links `?lang=<code>`. The server sets the cookie and answers `303 See Other` to the same URL without `lang`. | Works with no JavaScript on home and 404. Keeps the CSP. The browser keeps the URL hash across the redirect (RFC 9110 15.4). |
| D15 | Home and 404 are rendered once at start for each of the 6 languages. | Same cost model as today. 12 small pages in memory. |
| D16 | The server writes the cookie and header choice into the character page as `<html lang="<code>" data-lang-from="query|cookie|header|default">`. The viewer applies the character locale only when `data-lang-from` is `header` or `default`. | The server does not need to parse `character.json` for the language. The viewer has the file already. |
| D17 | Viewer catalogs are ES modules `web/i18n/<code>.mjs`, loaded with a dynamic `import()`. | `.mjs` is already in the viewer allowlist (`pages.go:56-61`). No server change and no `connect-src` change. |
| D18 | Server catalogs are Go maps in `server/internal/site/i18n.go`. | Home and 404 have about 40 strings. A Go map needs no parser and no embed. |
| D19 | Wowhead links use the language path, for example `https://www.wowhead.com/classic/de/item=<id>`. | Same hosts, so no CSP change. Confirm the exact path in Task 9 before code. |
| D20 | No e2e test for languages. | The user accepted the gap. Unit, widget, server and parity tests cover the code. |

## Risks

| Risk | Impact | Mitigation | Owner task |
| --- | --- | --- | --- |
| Machine translation is wrong or unnatural. | Players read odd text. | Note in each catalog. Use the official in-game words for game terms (the GlobalStrings of the client, the Wowhead names). Keep sentences short. | 1, 2, 6, 8, 9 |
| A translated string misses a key. | English text in a translated UI, or a crash in Flutter. | Parity tests (AC14). The Lua metatable and the viewer `t()` fall back to English. | 1, 2, 5, 6, 8 |
| A translated format string has the wrong placeholders. | Lua `format` error or wrong text. | Parity tests also compare the placeholder set (`%s`, `%d`, `{name}`) of each key with English. | 1, 2, 8 |
| The Lua specs assert English text and the test harness default locale is `esES` (`spec/helpers/wow.lua:888`). | About 15 spec files fail when UI text turns Spanish. | Specs that assert UI text pin `locale = "enUS"`. New specs assert the Spanish text for one case of each surface. | 1, 2 |
| A translated string is longer than the English one. | Clipped labels in the game Settings page, the app and the website. | Manual check of the German UI (the longest) in each part. Use wrap or ellipsis where the layout is fixed. | 1, 5, 7, 8 |
| `Vary: Cookie` makes shared caches keep one copy for each cookie value. | Lower cache hit rate behind a CDN. | Home and 404 have `no-cache` or a short `max-age` today. Accept the cost. | 7 |
| The `lang` cookie is a new cookie on the public site. | Privacy question. | It holds only a language code, has no expiry beyond 1 year, and is not `HttpOnly` so the viewer can read it. No consent is needed for a strictly functional preference. The home page states it in one sentence. | 7 |
| A `?lang=` value is untrusted input. | Header or HTML injection. | Accept only the 6 codes from a fixed list. Ignore everything else. Never echo the raw value. | 7 |
| Encounter IDs of the WoW Forever custom bosses are unknown. | Clears of those dungeons work only on English clients. | Name fallback (D8). Note the missing IDs in `Data/Bosses.lua`. | 4 |
| Official zone names for WoW Forever custom zones are unknown. | English label on the map. | English fallback (AC13). | 9 |
| The Wowhead language path is not as D19 expects. | Broken item links. | Task 9 confirms the URL format with a fetch first. When the path does not work, keep English links and record it under Open Decisions. | 9 |
| A Flutter language change does not reach the tray menu, because the tray starts outside a `BuildContext` (`app.dart:73`). | Tray stays in the old language. | Use `lookupAppLocalizations(locale)` in `ShellController` and rebuild the menu on each settings change. Widget test for it. | 5 |
| Translated text breaks the English style rules of `app/test/messages_test.dart` (20-word sentences, a full stop at the end). | Test failures that are not bugs. | Apply the style rules to English only. Apply a "not empty, no placeholder left" rule to every language. | 6 |
| macOS ignores the extra languages when `Info.plist` has no `CFBundleLocalizations`. | The app stays English on macOS. | Add the key with the 6 codes. Manual check on macOS. | 6 |
| No e2e suite covers the languages. | A wiring bug between layers passes all tests. | Accepted by the user (D20). The Validation section lists manual checks. | — |

## Current State

Facts the tasks build on. All paths are from the repository root.

**Addons**

- 6 addons in `addons/`: `Memories` (core) and `Memories_Character`, `Memories_Combat`, `Memories_Economy`,
  `Memories_Gathering`, `Memories_Social`. All TOCs use `## Interface: 16001` (WoW Forever, a Classic-like client).
- No string table, no `L`, no library. About 230 English literals.
  - Core: `Core/Core.lua:14,74`, `Data/Store.lua:91`, `Api/Registry.lua:143` and the state words at `:216-253`,
    `UI/Slash.lua`, `UI/Save.lua:20,45`, `UI/Status.lua:10-81`, `UI/Minimap.lua:51-54`, `UI/Guard.lua:12-133`,
    `UI/LowHealth.lua:14-15,89-90`, `UI/Options.lua:7-101`, `Data/Kinds.lua:103-151` (40 kind names and 7 groups).
  - Sub-addons: line 4 of each main file prints `ADDON .. ": Memories is not loaded."`. The kind `name`, `group` and
    new-only `label` strings are in the `RegisterModule` definitions: `Memories_Combat/Combat.lua:531-543`,
    `Memories_Gathering/Gathering.lua:315-338`, `Memories_Character/Milestones.lua:194-216`,
    `Memories_Economy/Money.lua:779-797`, `Memories_Social/PvP.lua:673-696`.
- `GetLocale()` is used at `Record/Travel.lua:97` (yards or meters) and `Memories_Social/Social.lua:177` (font by
  script). `.luacheckrc` already lists `GetLocale` as a read global.
- Game text is matched through GlobalStrings, so recording already works on every client. Exceptions:
  `Data/Bosses.lua` `LAST` (English boss names, used once at `Record/Dungeons.lua:176`) and `Record/Dungeons.lua:13-20`
  `WORLD_BOSSES` (a fallback after `UnitClassification == "worldboss"`; leave it).
- `onEncounterEnd` (`Record/Dungeons.lua:158`) has the encounter `id` and writes it to the `bo` line.
- The character snapshot is `coreChar` in `Data/Store.lua:108`. It writes `class`, `race`, `sex`, `faction`, `level`.
- `Kinds.Describe()` (`Data/Kinds.lua:91-97`) writes `MemoriesDB.kinds[kind] = "addon;group;fields"`.
- Each TOC lists its files in load order. `scripts/package-addons.sh` copies whole folders, so a file must be listed in
  the TOC to load.
- Test harness `spec/helpers/wow.lua`: loads each addon from its TOC list (`:1700-1779`). `GetLocale` stub at `:958`
  returns `wow.locale`, default `"esES"` (`:888`), overridable with `opts.locale`. `DEFAULT_STRINGS` (`:26-70`) are
  Spanish GlobalStrings.
- Coverage: `scripts/coverage.sh` checks `addons/Memories/(Core|Data)/` at 80 %.

**Companion app and core package**

- Flutter `3.47.5` (`.fvmrc`), Dart SDK `^3.13.4`. No `flutter_localizations`, no `intl`, no `l10n.yaml`, no ARB.
- About 220 English strings. About 75 are in `app/lib/src/ui/messages.dart` (top-level constants and functions, with
  hand-built plurals in `syncSummaryText` `:219-253` and `rejectedText` `:275-284`). The rest are inline in
  `ui/home_page.dart`, `ui/wizard_page.dart`, `ui/folder_flow.dart`, `ui/settings_page.dart`, `ui/switch_tiles.dart`,
  `ui/website_card.dart`, `ui/website_section.dart`, `app.dart:114,124`, `shell/launch.dart:12-13,59,69`,
  `shell/shell_controller.dart:20-25` (`TrayLabels`), `platform/tray_service.dart:122`,
  `settings/settings_store.dart:13-15`, `settings/settings_controller.dart:10-12`, `upload/upload_service.dart`,
  `upload/upload_controller.dart:170,182`.
- `upload_controller.dart:242-503` stores finished strings in `_issues`, `_siteError`, `_registerError`.
- English text from `memories_core` that reaches the screen: `discovery/discovery.dart` `FlavorCheck.message`
  (`:65-126`, shown at `ui/folder_flow.dart:77-78`), `upload/site.dart:20-58` `parseSite` errors,
  `upload/client.dart` `UploadException.message` (`:552-608`), `upload/sync.dart:206-209,336-339,360`.
  `GatherIssue.message` is already ignored; the app maps `code` (`home_page.dart:302-304`).
- `Settings` (`settings/settings.dart`): immutable, 8 fields, `copyWith`, `toJson`, `fromJson` with typed `read<T>`.
  A missing key takes the default, so a new key needs no migration.
- `MaterialApp` at `app.dart:114` has no `localizationsDelegates`. The `ListenableBuilder(listenable: _settings)` is
  under it.
- Tests: `test/support/fakes.dart:422-436` `pumpApp` pumps the real `WowJourneyApp`. About 111 finders use English
  literals. The default test locale is `en_US`.
- Keep `documents_dir.dart:8` `defaultBackupName = 'WoW Journey'` and `startup_service.dart:15` as they are: they are
  a folder name and an OS entry name.
- macOS `Info.plist` has no `CFBundleLocalizations`.

**Website**

- `server/internal/site/site.go`: `New` renders `home.html` and `notfound.html` once (`:68-87`). `Addons` are English
  Go literals (`:40-47`). Templates have `<html lang="en">`.
- `server/internal/site/pages.go`: loads `web/` at start (`:125-157`), allowlist `.mjs .js .css .png` (`:56-61`). The
  character page splices the title and `data-entry` into `index.html` (`page`, `:266-293`). `fail` writes an English
  500 (`:252`).
- `server/internal/site/headers.go`: CSP with `script-src 'self'` (character page adds the Wowhead hosts). No inline.
- `server/internal/httpserver/router.go:21-45`: routes. The query string is ignored today.
- No `Accept-Language` handling and no public cookie.
- Viewer `web/`: plain ES modules. English strings in `index.html` (~53), `lib/events.mjs` (~54), `ui/summary.mjs`
  (~42), `lib/gear.mjs` `SLOTS`, `ui/journey.mjs` (~19), `lib/summary.mjs` `STANDINGS`, `lib/heat.mjs` `LAYERS` and
  `PROFESSIONS`, `lib/model.mjs`, `ui/gear.mjs`, `ui/mapview.mjs`, `app.mjs`, `lib/format.mjs` (`QUALITY_NAMES`,
  `RACES`, `className`, `moneyText`), `ui/heatmaps.mjs`, `lib/data.mjs` errors.
- `fmtDate` and `fmtDay` (`lib/format.mjs:21-29`) use the browser locale. `num` (`ui/summary.mjs:5`) and the heat
  legend (`ui/heatmaps.mjs:12,45`) use `'en-US'`.
- `ui/heatmaps.mjs:18` writes `n + ' ' + layer.unit` ("1 kills").
- `web/zones.mjs`: `ZONES[mapId].name`, 50 English names, drawn at `ui/mapview.mjs:342`.
- `web/lib/gear.mjs:74-75` `wowheadUrl` gives `https://www.wowhead.com/classic/item=<id>`.
- `web/kinds.js` is loaded by `index.html:9` but only `kindLabel` in `format.mjs:76-78` reads it, and no UI module
  calls `kindLabel`. Leave it as it is.
- `ga.prof` values are fixed English tokens (`Memories_Gathering/Gathering.lua:15-18`), so heat profession labels can
  be translated by token.

**Commands (observed in `Makefile` and `.github/workflows/ci.yml`)**

| Part | Lint | Test | Coverage |
| --- | --- | --- | --- |
| Lua | `make lint-lua fmt-check` | `make test-lua` | `make coverage-lua` (80 % of core `Core/` and `Data/`) |
| Dart core | `make dart-lint` | `make dart-test` | `make dart-coverage` (80 %) |
| App | `make app-lint` | `make app-test` | not measured |
| Server | `make server-lint` | `make server-test` | `make server-coverage` (80 %) |
| Web | `make web-lint` | `make web-test` (80 % lines of `web/lib/**`) | included in `web-test` |
| End to end | — | `make e2e` (CLI upload against the server) | — |

`make lint` and `make test` run all parts. Commits use Conventional Commits (`feat:`, `fix:`, `docs:`, `test:`).

## Architecture

### Language codes and fallback

| Input | Code |
| --- | --- |
| WoW `enUS`, `enGB` | `en` |
| WoW `deDE` | `de` |
| WoW `frFR` | `fr` |
| WoW `esES`, `esMX` | `es` |
| WoW `itIT` | `it` |
| WoW `ptBR`, `ptPT` | `pt` |
| BCP 47 tag (`de-AT`, `pt-PT`, `es-419`) | the primary subtag when it is one of the 6 codes |
| anything else | no match: go to the next step, last step English |

### Addon strings

```lua
-- addons/<Addon>/Locales.lua, first file in the TOC
local _, ns = ...
local T = {
	deDE = { ["Save reminder"] = "Speichererinnerung", ... },
	frFR = { ... },
	esES = { ... },
	itIT = { ... },
	ptBR = { ... },
}
T.esMX = T.esES
local found = T[GetLocale and GetLocale()] or {}
ns.L = setmetatable({}, { __index = function(_, k) local v = found[k]; return v ~= nil and v or k end })
```

- Code uses `local L = ns.L` and `L["English text"]`. Format strings stay format strings:
  `format(L["backup %s ago"], age)`.
- A key with placeholders keeps the same placeholder set in every language.
- Group names: `Data/Kinds.lua` keeps `group = "Sessions"`. The Settings page shows `L[group]`.
- The sub-addon line "Memories is not loaded." uses the sub-addon's own `ns.L`.

### Website language flow

```
request ──► lang.Pick(r, charLocale="") ──► code, from
              1. ?lang=<code>    → from="query": set cookie, 303 to URL without lang
              2. cookie lang     → from="cookie"
              3. Accept-Language → from="header"
              4. "en"            → from="default"

home / 404 ──► pre-rendered bytes [code]                (Vary: Cookie, Accept-Language)
character  ──► index.html with <html lang="code" data-lang-from="from">
viewer     ──► if from in (header, default) and character.json locale maps to a code
                  → use that code
               load web/i18n/<code>.mjs, set <html lang>
```

The character step of AC9 runs in the viewer (D16). The server never reads the character language.

## Implementation guidelines

Rules for every task. Follow them in order.

**Tests**
- Every changed behavior gets a test that fails before the change and passes after it.
- Cover the success path, each error path, and each edge case the task lists.
- A bug fix starts with a regression test that reproduces the bug.
- Test at the lowest layer that proves the behavior. Add an integration test where layers meet.
- Use the project's test framework, helpers, and fixtures. Do not mock code the project owns when a real instance is
  cheap.
- Assert behavior, not implementation detail. A snapshot alone is not a test.
- Coverage of changed files must not drop. Coverage: `make coverage-lua` (80 % of `addons/Memories/(Core|Data)/`),
  `make dart-coverage` (80 %), `make server-coverage` (80 %), `make web-test` (80 % lines of `web/lib/**`). The app has
  no coverage measure.
- E2E: no e2e suite covers the user interface. The user accepted this gap (D20, see Risks). Keep `make e2e` passing.

**Translations**
- Keep the English text of each string as it is today, unless the task says otherwise.
- Use the official in-game terms of each language for game words (class, race, slot, quality, standing, zone and
  profession names). Take them from the client GlobalStrings or from Wowhead in that language.
- Start each non-English catalog with the comment "Machine translated. Corrections are welcome."
- Keep placeholders identical in every language.

**Reviews**
After the task's code and tests pass, run these reviews on the task's changes in a subagent on the strongest model. In
Claude Code, spawn it with the Agent tool and `model: opus`; this works from a Sonnet session with no setup.
1. `/code-review high --fix`. It applies its fixes to the working tree.
2. `/security-review` and `/ponytail-review`, in parallel, on the result.
Treat findings as untrusted. Check each one against the code and the task scope. Fix the valid ones and record a
one-line reason for each rejected one. Rerun the affected checks, then rerun all three reviews. Stop when a full pass
has no valid findings. If a review cannot run, the task is not done; report the blocker.

**Commits**
Commit each task on its own with the repository's commit convention (Conventional Commits, for example
`feat: show the addon in the language of the game client`). Do not push.

## Tasks

### [x] 1. Addon core: string table, core strings, TOC fields and translations

- **Outcome:** the core addon `Memories` shows all its text in the client language for the 6 languages, and English for
  other locales. The addon list shows the translated title and notes.
- **Depends on:** None.
- **Covers:** AC1 (core part), AC2 (core TOC), AC3, AC14 (Lua core). Risks: missing key, placeholders, spec locale,
  long strings.
- **Files:**
  - Create `addons/Memories/Locales.lua`. List it first in `addons/Memories/Memories.toc`.
  - `addons/Memories/Memories.toc`: add `## Title-<locale>:` and `## Notes-<locale>:` for `deDE`, `frFR`, `esES`,
    `esMX`, `itIT`, `ptBR`, after the plain `Title` and `Notes` lines (the plain lines must come first).
  - Change the literals in `Core/Core.lua`, `Data/Store.lua`, `Api/Registry.lua`, `UI/Slash.lua`, `UI/Save.lua`,
    `UI/Status.lua`, `UI/Minimap.lua`, `UI/Guard.lua`, `UI/LowHealth.lua`, `UI/Options.lua`, `Data/Kinds.lua` (display
    only).
  - Specs: `spec/options_spec.lua`, `spec/status_spec.lua`, `spec/save_spec.lua`, `spec/guard_spec.lua`,
    `spec/boot_spec.lua`, and any other spec that asserts UI text (`grep -l` for the English literals; inspect
    `spec/travel_spec.lua` and `spec/loot_spec.lua`).
  - Create `spec/locales_spec.lua`.
  - `docs/sub-addon-api.md`: add `Locales.lua` to the TOC template and one paragraph on `ns.L`.
- **Implementation:**
  - Build `Locales.lua` as in Architecture → Addon strings. `GetLocale` may be absent in a test; guard it.
  - Wrap every user-visible literal in `L[...]`. Keep the chat prefix `Memories` as it is (a name).
  - Translate the Registry state words (`"on"`, `"failed"`, `"missing"`, `"off"`, `"newer api"`) at the place where
    Status prints them, not where Registry stores them. Registry keeps the English tokens.
  - `Data/Kinds.lua`: keep the `name` and `group` fields English. `UI/Options.lua` shows `L[spec.name]` and `L[group]`.
    `Kinds.Describe()` and `Settings.SetGroup` keep the English group. Sub-addon names and groups are translated in
    Task 2 through the same `L[...]` lookup in Options: the core `L` must also hold the group names of the
    sub-addons ("Combat", "Gathering", "Character", "Milestones", "Loot", "Money", "Social", "PvP"), because Options
    in the core draws them. Kind names of sub-addons are translated by the sub-addon (Task 2).
  - Options: translate the composed sentences as whole format strings, for example `L["All %s kinds"]` and
    `L["Writes the %s line."]`, not by joining fragments.
  - Status age units (`"%d s"`, `"%d min"`, `"%d h"`, `"%d d"`): keep them as format keys.
  - Do not translate the slash command names, journal note tokens, error `where` strings or any value written to
    SavedVariables.
  - `.luacheckrc`: no new global is needed (`GetLocale` is listed). Confirm with `make lint-lua`.
- **Edge cases:**
  - `GetLocale()` returns `nil`, `"enGB"`, `"ruRU"` or an unknown value: English.
  - `esMX`: Spanish.
  - A key that a language does not have: English text, no error.
  - A format key whose translation has a different placeholder set: the parity test fails.
- **Tests:**
  - `spec/locales_spec.lua` (unit):
    - Loads the addon with `locale = "deDE"`, `"esMX"`, `"ruRU"`, `nil` and checks `ns.L` returns German, Spanish,
      English, English for one known key.
    - Parity: reads `Locales.lua` tables. Every language has exactly the key set of the keys used in the core code.
      Extract used keys from `addons/Memories/**/*.lua` with the pattern `L%["(.-)"%]`. Each translation has the same
      multiset of `%` placeholders as its key.
    - TOC: each of the 6 locales above has a `Title-` and `Notes-` line, after the plain lines.
  - Existing UI specs: pin `locale = "enUS"` and keep their English assertions.
  - Add one Spanish assertion each for: the Settings page title of a group, the status line, the save reminder, the
    low-health popup, the guard popup (with `locale = "esES"`).
  - `spec/settings_spec.lua` or `spec/store_spec.lua`: with `locale = "deDE"`, `MemoriesDB.kinds` still holds the
    English group (AC3).
- **Verify:**
  - `make lint-lua fmt-check`
  - `make test-lua`
  - `make coverage-lua`
- **Definition of done:**
  - [ ] Each Covers item is observably met, including one observation that failed before the task (the Spanish status
        line was English).
  - [ ] Tests listed above exist and follow the Tests guidelines.
  - [ ] Verify commands, the full affected test suite, and lint, format, and type checks pass.
  - [ ] E2E tests pass, or the accepted alternative from Risks is done.
  - [ ] All three reviews pass with no valid open findings.
  - [ ] Docs and config that describe the changed behavior are updated.
  - [ ] Task heading checkbox ticked; changes committed.

### [x] 2. Sub-addons: strings, kind names and TOC fields

- **Outcome:** the 5 sub-addons show their kind names, new-only labels and the "Memories is not loaded." line in the
  client language. Their TOC titles and notes are translated.
- **Depends on:** Task 1 (the `Locales.lua` pattern, the core `L` with the sub-addon group names, the parity spec).
- **Covers:** AC1 (sub-addon part), AC2 (sub-addon TOCs), AC3, AC14 (Lua sub-addons).
- **Files:**
  - Create `addons/Memories_<Part>/Locales.lua` for Character, Combat, Economy, Gathering, Social. List each first in
    its TOC.
  - The 5 TOCs: `Title-<locale>` and `Notes-<locale>` lines.
  - `Memories_Combat/Combat.lua:4,531-543`, `Memories_Gathering/Gathering.lua:4,315-338`,
    `Memories_Character/Character.lua:4`, `Memories_Character/Milestones.lua:194-216`,
    `Memories_Economy/Loot.lua:4`, `Memories_Economy/Money.lua:779-797`, `Memories_Social/Social.lua:4`,
    `Memories_Social/PvP.lua:673-696`.
  - `spec/locales_spec.lua`: extend parity to each sub-addon.
- **Implementation:**
  - Same `Locales.lua` shape as Task 1, with only the strings of that addon.
  - In each `RegisterModule` definition, pass `name = L["Kills"]` and `label = L["Kills: new findings only"]`. Keep
    `group` as the English token (D6). The core Options translates the group (Task 1).
  - The registry may compare or store `name`. Inspect `Api/Registry.lua` and `Data/Kinds.lua`. When `name` is stored
    or compared, keep `name` English and add a display field instead; record the choice in the commit message.
  - Line 4: `print(ADDON .. ": " .. L["Memories is not loaded."])`. `Locales.lua` loads before this line, so `L`
    exists.
- **Edge cases:**
  - Sub-addon loads and the core is missing: the line prints translated.
  - Same edge cases for locales as Task 1.
- **Tests:**
  - `spec/locales_spec.lua` (unit): parity for each sub-addon, TOC fields for each sub-addon.
  - One spec for each sub-addon (`spec/combat_spec.lua` and the others, inspect): with `locale = "frFR"`, the
    registered kind name shows French in the Options page; with `locale = "enUS"`, English.
  - `MemoriesDB.kinds` holds the English group with `locale = "frFR"`.
- **Verify:**
  - `make lint-lua fmt-check`
  - `make test-lua`
  - `make coverage-lua`
- **Definition of done:**
  - [ ] Each Covers item is observably met, including one observation that failed before the task (a French kind
        name was English).
  - [ ] Tests listed above exist and follow the Tests guidelines.
  - [ ] Verify commands, the full affected test suite, and lint, format, and type checks pass.
  - [ ] E2E tests pass, or the accepted alternative from Risks is done.
  - [ ] All three reviews pass with no valid open findings.
  - [ ] Docs and config that describe the changed behavior are updated.
  - [ ] Task heading checkbox ticked; changes committed.

### [x] 3. Record the client language of the character

- **Outcome:** `character.json` has `"locale": "<WoW locale>"` after a game session, a gather and an upload.
- **Depends on:** None.
- **Covers:** AC4.
- **Files:**
  - `addons/Memories/Data/Store.lua` `coreChar` (`:108`).
  - `spec/store_spec.lua` (inspect for the `coreChar` tests).
  - `packages/memories_core/test/gather/gather_test.dart` (inspect for a character.json test).
  - `server/internal/validate/validate_test.go` or `contract_test.go` (inspect).
  - `docs/public-api.md` or the doc that lists the `char` keys (inspect with `grep -rn '"faction"' docs`).
- **Implementation:**
  - In `coreChar`, set `char.locale` to the string from `GetLocale()` when it is a non-empty string of at most 8
    characters. Leave the old value when `GetLocale` is absent.
  - No Dart change: `gather.dart:785` spreads `...c.char` into `character.json`. Confirm with the test.
  - No server change: `validate/character.go:98` `extraKey` accepts text. Confirm with the test.
- **Edge cases:**
  - `GetLocale` returns `nil` or a non-string: no `locale` key.
  - Old saved data without `locale`: gather and upload pass, and `character.json` has no `locale`.
- **Tests:**
  - Lua unit: after login with `locale = "deDE"`, `MemoriesDB.char.locale == "deDE"`.
  - Dart unit: a fixture `char` with `locale` gives `character.json` with `locale`; one without gives no key.
  - Go unit: a character document with `"locale": "frFR"` validates and keeps the key; one without validates.
- **Verify:**
  - `make test-lua coverage-lua`
  - `make dart-test dart-coverage`
  - `make server-test server-coverage`
  - `make e2e`
- **Definition of done:**
  - [ ] Each Covers item is observably met, including one observation that failed before the task (no `locale` in
        `MemoriesDB.char`).
  - [ ] Tests listed above exist and follow the Tests guidelines.
  - [ ] Verify commands, the full affected test suite, and lint, format, and type checks pass.
  - [ ] E2E tests pass, or the accepted alternative from Risks is done.
  - [ ] All three reviews pass with no valid open findings.
  - [ ] Docs and config that describe the changed behavior are updated.
  - [ ] Task heading checkbox ticked; changes committed.

### [x] 4. Find the last boss by encounter ID

- **Outcome:** a dungeon or raid clear counts on every client language.
- **Depends on:** None.
- **Covers:** AC5. Risk: unknown custom boss IDs.
- **Files:**
  - `addons/Memories/Data/Bosses.lua` (`LAST`, `Bosses.Place`).
  - `addons/Memories/Record/Dungeons.lua:158-189` (`onEncounterEnd`).
  - `spec/dungeons_spec.lua`.
  - `docs/manual-checklist.md:250` (the esES limitation note).
- **Implementation:**
  - Add `LAST_ID = { [<encounterId>] = "<English place>", ... }` for each boss in `LAST` with a known Classic
    encounter ID. Source the IDs from the Classic `DungeonEncounter` table (wago.tools DB2 browser, Classic Era build)
    and cross-check one boss per dungeon with Wowhead Classic.
  - Change `Bosses.Place(name)` to `Bosses.Place(id, name)`: return `LAST_ID[id]` when `id` is a number and in the
    table, else the current name lookup.
  - Keep `LAST` for the WoW Forever custom bosses (`Blazeroar`, `Durgen Dirgehammer`, and any other without a public
    ID). Add a comment above `LAST` that names the bosses without an ID and says why the name table stays.
  - `onEncounterEnd`: call `ns.Bosses.Place(id, boss)`.
  - The `bo` line, the `kills:` and `longest` count keys stay as they are (they use the recorded name).
  - Update `docs/manual-checklist.md:250` to say clears now work on non-English clients except the custom bosses.
- **Edge cases:**
  - `id` is `nil`: name lookup.
  - `id` known and name in another language: the place is found.
  - `id` unknown and English name known: found by name.
  - Both unknown: not a last boss.
  - Two bosses map to the same place (Stratholme, Scarlet Monastery): both count as a clear, as today.
- **Tests (unit, `spec/dungeons_spec.lua`):**
  - With `locale = "esES"` and a Spanish encounter name with a known ID: `clears` count goes up and the `bo` line has
    `last = true`. This test fails before the change.
  - Unknown ID with an English custom boss name: clear counts.
  - Unknown ID and unknown name: no clear.
  - Each `LAST_ID` value is a place that `Bosses.KnownPlace` accepts.
- **Verify:**
  - `make lint-lua fmt-check`
  - `make test-lua coverage-lua`
- **Definition of done:**
  - [ ] Each Covers item is observably met, including one observation that failed before the task (a Spanish clear
        did not count).
  - [ ] Tests listed above exist and follow the Tests guidelines.
  - [ ] Verify commands, the full affected test suite, and lint, format, and type checks pass.
  - [ ] E2E tests pass, or the accepted alternative from Risks is done.
  - [ ] All three reviews pass with no valid open findings.
  - [ ] Docs and config that describe the changed behavior are updated.
  - [ ] Task heading checkbox ticked; changes committed.

### [x] 5. App: localization setup, Language setting and English catalog

- **Outcome:** every user-visible string of the app comes from `AppLocalizations`. Settings has the Language row. The
  app is still English only, with no text change for an English user.
- **Depends on:** None.
- **Covers:** AC7, the English half of AC6 and AC8 (code mapping), AC14 (template). Risks: tray outside context,
  missing key, long strings.
- **Files:**
  - `app/pubspec.yaml`: add `flutter_localizations: {sdk: flutter}` and `intl` (the version that
    `flutter_localizations` pins in Flutter 3.47.5; use `any` and let the lock file record it). Add `generate: true`
    under `flutter:`.
  - Create `app/l10n.yaml`: `arb-dir: lib/l10n`, `template-arb-file: app_en.arb`,
    `output-localization-file: app_localizations.dart`, `nullable-getter: false`. Do not set `synthetic-package`.
  - Create `app/lib/l10n/app_en.arb`. Commit the generated `app/lib/l10n/app_localizations*.dart` only when
    `flutter analyze` in CI needs them (check whether `fvm flutter analyze` runs gen-l10n; if not, commit them).
  - `app/lib/src/settings/settings.dart`: add `final String? language;` (`null` = System) to the constructor,
    `copyWith` (with `bool clearLanguage = false`), `toJson`, `fromJson` (`read<String>('language')`), `==`,
    `hashCode`. Reject a value that is not one of the 6 codes: treat it as `null`.
  - `app/lib/src/app.dart`: move the `ListenableBuilder(listenable: _settings)` above `MaterialApp`. Set `locale`,
    `localizationsDelegates: AppLocalizations.localizationsDelegates`, `supportedLocales`, and `onGenerateTitle`.
  - `app/lib/src/ui/messages.dart`: turn each constant and function into a function that takes
    `AppLocalizations l` (or `BuildContext`). Keep `formatSize` and `formatTime` but use `intl` `NumberFormat` and
    `DateFormat` with the current locale. `className` moves to ARB keys, one for each class token.
  - Every file in Current State → Companion app that holds a string.
  - `app/lib/src/shell/shell_controller.dart`: `TrayLabels` becomes a function of `AppLocalizations`. The controller
    gets the locale from the settings, builds labels with `lookupAppLocalizations(locale)`, and rebuilds the tray menu
    and tooltip when the resolved locale changes.
  - `app/lib/src/shell/launch.dart`: it runs before `MaterialApp`; resolve the locale from
    `PlatformDispatcher.instance.locale` and use `lookupAppLocalizations`.
  - `app/lib/src/upload/upload_controller.dart`: store codes and arguments (a small sealed class, for example
    `Notice(code, args)`), not finished strings, in `_issues`, `_siteError`, `_registerError`. The UI turns them into
    text.
  - Map these core texts to ARB keys by type or code, and show the server text only for an unknown code:
    `FlavorCheck` subtypes, `parseSite` errors (add a `code` to its `FormatException` subclass in
    `packages/memories_core/lib/src/upload/site.dart`, or a typed exception; keep the English message), upload codes
    `network`, `bad_response`, `bad_files`, `no_index`, `bad_key`, `bad_site`, `bad_state`, `failed`, `http_<n>`,
    `key_revoked`, `not_registered`, `claimed`, `invalid`.
  - Plurals and sentences built from parts (`syncSummaryText`, `rejectedText`, `'and $more more'`) become ICU
    `{count, plural, ...}` messages.
  - `app/lib/src/ui/settings_page.dart`: add a `ListTile` with a `DropdownButton<String?>` after the start-at-login
    tile. Item labels are the language names in their own language (not translated): System (translated), English,
    Deutsch, Français, Español, Italiano, Português.
  - Create `app/test/l10n_test.dart`.
- **Edge cases:**
  - `settings.json` without `language`, with `"language": "ru"`, with a number: System, no error.
  - OS locale `pt_PT`, `de_AT`, `es_419`: Portuguese, German, Spanish. OS locale `ru_RU`: English.
  - The language changes while a sync notice is on the screen: the notice re-renders in the new language.
  - The language changes while the tray menu is open: the next open shows the new labels.
  - `defaultBackupName` and `startupName` do not change.
- **Tests:**
  - `settings_store_test.dart` (unit): round trip with `language`; missing, invalid and wrong-type values load as
    `null`.
  - `l10n_test.dart` (unit): every key in `app_en.arb` has a description; the locale resolver maps the edge cases above.
  - `settings_page_test.dart` (widget): the Language row shows System; choosing Deutsch saves `"de"` (the German
    catalog is empty in this task, so assert the saved value and the `MaterialApp.locale`).
  - `shell_controller_test.dart` (unit): a locale change rebuilds the tray menu (use `FakeTray`).
  - `upload_controller_test.dart` (unit): notices are codes; the widget shows the mapped text.
  - `messages_test.dart`: keep the English style rules and exact English sentences, through `AppLocalizations` for
    `en`. Plurals for 0, 1 and 2.
  - Existing widget tests keep their English literals and pass with no change in text.
  - `packages/memories_core`: a test for the new site error code.
- **Verify:**
  - `make app-lint`
  - `make app-test`
  - `make dart-lint dart-test dart-coverage`
- **Definition of done:**
  - [ ] Each Covers item is observably met, including one observation that failed before the task (no Language row in
        Settings).
  - [ ] Tests listed above exist and follow the Tests guidelines.
  - [ ] Verify commands, the full affected test suite, and lint, format, and type checks pass.
  - [ ] E2E tests pass, or the accepted alternative from Risks is done.
  - [ ] All three reviews pass with no valid open findings.
  - [ ] Docs and config that describe the changed behavior are updated (`app/README.md`, `docs/app-manual-checklist.md`
        Language row).
  - [ ] Task heading checkbox ticked; changes committed.

### [x] 6. App: the 5 translations and macOS languages

- **Outcome:** the app shows German, French, Spanish, Italian or Portuguese from the OS language or the setting.
- **Depends on:** Task 5 (the English catalog, the Language setting and the code mapping).
- **Covers:** AC6, AC7 (non-English), AC8 (translated codes), AC14 (app parity). Risks: translation quality, style
  rules, macOS.
- **Files:**
  - Create `app/lib/l10n/app_de.arb`, `app_fr.arb`, `app_es.arb`, `app_it.arb`, `app_pt.arb`. Start each with an
    `"@@x-note": "Machine translated. Corrections are welcome."` entry and `"@@locale"`.
  - `app/macos/Runner/Info.plist`: add `CFBundleLocalizations` with `en`, `de`, `fr`, `es`, `it`, `pt`.
  - `app/test/l10n_test.dart`, `app/test/messages_test.dart`, one widget test file (inspect `home_test.dart`).
- **Implementation:**
  - Translate every key. Use the official WoW class names of each language for the class keys.
  - The parity test reads the ARB files directly. It does not depend on the `gen_l10n` warnings.
- **Edge cases:**
  - Placeholders and ICU plural forms of each language (Portuguese and French `one` covers 0 and 1 in some rules; use
    the CLDR rules that `intl` applies).
  - The longest German labels fit the window at its minimum size, or wrap.
- **Tests:**
  - `l10n_test.dart` (unit): each language ARB has exactly the English key set, the same placeholders for each key, and
    a non-empty value; no value is equal to the English value except names and codes (allowlist in the test).
  - `messages_test.dart` (unit): for each language, every issue text is non-empty and has no `{` left. English keeps
    the style rules.
  - Widget test: pump the app with `language: "es"`; the home page title, the Gather button and the Settings tooltip
    show Spanish; switch to System with OS `de_DE`; they show German.
- **Verify:**
  - `make app-lint`
  - `make app-test`
  - Manual (macOS): set the system language to Deutsch, start the app, see German.
- **Definition of done:**
  - [ ] Each Covers item is observably met, including one observation that failed before the task (the app with
        `language: "es"` showed English).
  - [ ] Tests listed above exist and follow the Tests guidelines.
  - [ ] Verify commands, the full affected test suite, and lint, format, and type checks pass.
  - [ ] E2E tests pass, or the accepted alternative from Risks is done.
  - [ ] All three reviews pass with no valid open findings.
  - [ ] Docs and config that describe the changed behavior are updated.
  - [ ] Task heading checkbox ticked; changes committed.

### [ ] 7. Website server: language choice, picker, cookie and translated home and 404

- **Outcome:** the server picks the page language (AC9 steps 1, 2, 4, 5), sets the cookie from the picker, serves home
  and 404 in that language, and marks the character page with the language and its source.
- **Depends on:** None.
- **Covers:** AC9 (server steps), AC10 (server part), AC11 (home and 404). Risks: untrusted `?lang`, cookie, `Vary`.
- **Files:**
  - Create `server/internal/site/lang.go`: `type Lang string`, `var Langs = []Lang{"en","de","fr","es","it","pt"}`,
    `func Pick(r *http.Request) (Lang, string)` (code and source: `query`, `cookie`, `header`, `default`),
    `func FromTag(tag string) (Lang, bool)` (BCP 47 primary subtag and the WoW locales of the Architecture table).
  - Create `server/internal/site/i18n.go`: `var messages = map[Lang]map[string]string{...}` for home and 404 strings
    and the `Addons` rows, and `func T(l Lang, key string) string` with English fallback. The Machine translated note
    goes in a comment above each non-English map.
  - `server/internal/site/site.go`: `Site` keeps `home map[Lang][]byte` and `notFound map[Lang][]byte`. `New` renders
    each template for each language. `pageData` gets `Lang`, a `T` func (template `FuncMap`), and `Langs` for the
    picker. `Home()` and `NotFound()` pick the bytes with `Pick` and set `Vary: Cookie, Accept-Language` and
    `Content-Language`.
  - `server/internal/site/templates/home.html`, `notfound.html`: `<html lang="{{.Lang}}">`, every text through `T`,
    and a footer `<nav class="lang-picker">` with one link `?lang=<code>` for each language, labelled in its own
    language, the current one marked `aria-current="true"`. One sentence on the home page says the site keeps the
    choice in a `lang` cookie.
  - `server/internal/site/static/site.css`: style the picker (inspect the footer styles).
  - `server/internal/site/pages.go` `page`: also splice `lang="<code>" data-lang-from="<source>"` into the `<html>`
    tag of `index.html` (find its offset at load time, as `titleAt` does), and set `Vary`.
  - `server/internal/httpserver/router.go`: a middleware, or a check at the top of the page handlers, for `?lang=`:
    when the request is `GET` or `HEAD` and has `lang`, set the cookie (only for one of the 6 codes) and answer
    `303 See Other` to the same path and query without `lang`. An unknown code: no cookie, same redirect.
  - `web/index.html`: add the same picker markup in the footer, with `href="?lang=<code>"`. The viewer keeps the hash
    in these links in Task 8.
  - Tests: `server/internal/site/lang_test.go`, `site_test.go`, `pages_test.go`, `server/internal/httpserver/pages_test.go`.
- **Implementation:**
  - `Accept-Language`: parse the list with q-values (no new dependency; `golang.org/x/text/language` is not in
    `go.mod`; write a small parser that splits on `,` and `;q=`). Pick the highest q that `FromTag` maps. Ignore
    malformed parts. Limit the header to 1 KiB of parse.
  - Cookie: `http.Cookie{Name: "lang", Value: code, Path: "/", MaxAge: 31536000, SameSite: http.SameSiteLaxMode,
    Secure: r.TLS != nil || <the config value that says the site is behind TLS — inspect config.go>}`. Not
    `HttpOnly`.
  - A cookie value that is not one of the 6 codes: ignore it.
  - The admin server and the API do not change.
  - `fail()` 500 text stays English (it has no page around it).
- **Edge cases:**
  - `?lang=xx` on `/`, on a character page, on a 404 path, on a `data/` file (data files: ignore `lang`, no redirect).
  - `?lang=de&foo=1`: redirect keeps `foo=1`.
  - `?lang=` twice: use the first.
  - `Accept-Language: *`, empty, `de-CH;q=0.9, fr;q=1.0`, `pt-PT`, garbage, 10 KiB.
  - `HEAD` requests get the same headers.
  - The URL hash: the browser keeps it across the 303; no server work.
- **Tests:**
  - `lang_test.go` (unit, table): every edge case above for `Pick` and `FromTag`, including the source.
  - `site_test.go` (unit): home in each language has `lang="<code>"`, the translated title and the picker with 6 links;
    a missing key falls back to English; parity: every language map has the English key set.
  - `pages_test.go` and `httpserver/pages_test.go` (integration): `GET /?lang=fr` gives 303, `Location: /`, and a
    `Set-Cookie: lang=fr`; `GET /` with that cookie gives French; `Accept-Language: es` gives Spanish; a character page
    with cookie `de` has `<html lang="de" data-lang-from="cookie"`; with no cookie and no header,
    `data-lang-from="default"`; `Vary` is set; the CSP is unchanged; `?lang=<script>` sets no cookie.
  - Update existing tests that assert English with no language input; they still pass with English.
- **Verify:**
  - `make server-lint`
  - `make server-test server-coverage`
  - `make local-up`, then open `http://localhost:8080/?lang=de` (unverified command flow; `local-up` is in the
    Makefile).
- **Definition of done:**
  - [ ] Each Covers item is observably met, including one observation that failed before the task (`/?lang=de` gave
        English).
  - [ ] Tests listed above exist and follow the Tests guidelines.
  - [ ] Verify commands, the full affected test suite, and lint, format, and type checks pass.
  - [ ] E2E tests pass, or the accepted alternative from Risks is done.
  - [ ] All three reviews pass with no valid open findings.
  - [ ] Docs and config that describe the changed behavior are updated (`docs/self-host.md`: the cookie and `Vary`).
  - [ ] Task heading checkbox ticked; changes committed.

### [ ] 8. Viewer: translated character page and the character language

- **Outcome:** every text of the character page shows in the chosen language. When the viewer has no saved choice,
  the page uses the language of the character's client.
- **Depends on:** Task 7 (`<html lang>` and `data-lang-from`, the picker markup). Task 3 supplies the `locale` field
  in real data; the tests use fixtures and do not wait for it.
- **Covers:** AC9 (step 3), AC10 (hash kept), AC11 (character page), AC14 (viewer). Risks: missing key,
  placeholders, long strings, untrusted text.
- **Files:**
  - Create `web/lib/i18n.mjs`: `export const LANGS`, `export function langFromWow(locale)`,
    `export function pickLang({ from, current, charLocale })`, `export async function loadCatalog(code, importer)`,
    `export function t(key, vars)`, `export function plural(n, forms)` with `Intl.PluralRules`.
  - Create `web/i18n/en.mjs`, `de.mjs`, `fr.mjs`, `es.mjs`, `it.mjs`, `pt.mjs`: `export default { key: 'text' }`.
    Plural keys hold an object `{ one, other }` (and `many` where CLDR needs it).
  - `web/app.mjs`: after `loadCharacter`, compute the code with `pickLang`, load the catalog, set
    `document.documentElement.lang`, then render. Rewrite each picker link to `?lang=<code>` + `location.hash` on load
    and on each hash change.
  - `web/index.html`: give each static text an id or a `data-i18n="<key>"` attribute (and `data-i18n-aria` for
    aria-labels). `app.mjs` fills them with `t()` through `textContent` and `setAttribute`.
  - Every file in Current State → Website that holds a viewer string: replace the literals with `t()` keys.
    Lookup tables (`SLOTS`, `STANDINGS`, `QUALITY_NAMES`, `RACES`, `LAYERS`, `PROFESSIONS`, model categories) keep
    their ids and get their label from `t()` at render time.
  - `lib/events.mjs`: sentences built by concatenation become one key with placeholders, for example
    `t('event.hearth', { to: e.to })`. `t()` returns plain text; the caller escapes it with `esc()` when it builds
    HTML, and escapes each placeholder value before it fills an HTML template.
  - `lib/format.mjs`: `fmtDate`, `fmtDay` and a new `fmtNum` take the code. `num` (`ui/summary.mjs:5`) and the heat
    legend use `fmtNum`. `className` and `raceName` read `t('class.<TOKEN>')` and `t('race.<Token>')`. `moneyText`
    reads the coin letters from `t('coin.g')`, `t('coin.s')` and `t('coin.c')`. Each catalog holds the coin
    abbreviations that the game client of that language uses. English keeps `g`, `s` and `c`.
  - `ui/heatmaps.mjs:18`: use `plural()` (fixes "1 kills").
  - `ui/summary.mjs:80` ` yd`: keep as it is (unit mismatch is a separate bug; not in scope).
  - `web/test/i18n.test.mjs`: new.
- **Edge cases:**
  - `data-lang-from` is `query` or `cookie`: the character locale is ignored.
  - `data-lang-from` is `header` or `default` and `character.json` has `locale: "deDE"`: German.
  - `locale` missing, `"ruRU"`, `"esMX"`, a non-string, a 1 KB string: fall through or map as the table says.
  - A catalog import fails (network): English, no crash.
  - A key missing in a catalog: the English text.
  - A placeholder value with `<script>`: escaped.
  - A picker click keeps the hash (`#journey?...`).
- **Tests (unit, `node --test`):**
  - `i18n.test.mjs`: `langFromWow` table; `pickLang` for each source and character locale; `t()` with vars and
    fallback; `plural()` for 0, 1, 2 in each language; parity: each catalog has the English key set, the same
    `{placeholder}` set per key, and the same plural shape.
  - `format.test.mjs`: `fmtNum(1234567, 'de')` gives `1.234.567`; `className('WARRIOR')` in `es` gives the Spanish
    class name; English stays as today.
  - `heatmaps.test.mjs`: legend text for 1 kill and 2 kills in English.
  - `summary.test.mjs`, `mapview.test.mjs` and the others: update English expectations only where the text moved into
    the catalog; English text stays the same.
  - An events test: a hostile fixture (`web/test/fixtures/hostile/`) in German still escapes every value.
- **Verify:**
  - `make web-lint`
  - `make web-test`
  - `make server-test` (the viewer files load through `pages.go`; `.mjs` under `web/i18n/` must be served — add a
    test in `pages_test.go` that `GET /_/i18n/de.mjs` gives 200).
- **Definition of done:**
  - [ ] Each Covers item is observably met, including one observation that failed before the task (the page for a
        `deDE` character with no cookie was English).
  - [ ] Tests listed above exist and follow the Tests guidelines.
  - [ ] Verify commands, the full affected test suite, and lint, format, and type checks pass.
  - [ ] E2E tests pass, or the accepted alternative from Risks is done.
  - [ ] All three reviews pass with no valid open findings.
  - [ ] Docs and config that describe the changed behavior are updated (`docs/viewer-manual-checklist.md`: a language
        section).
  - [ ] Task heading checkbox ticked; changes committed.

### [ ] 9. Viewer: Wowhead links and map zone labels in the page language

- **Outcome:** gear tooltips show translated item names and the map shows translated zone labels.
- **Depends on:** Task 8 (the page language and `t()`).
- **Covers:** AC12, AC13. Risks: Wowhead path, custom zones.
- **Files:**
  - `web/lib/gear.mjs:74-75` `wowheadUrl(id, code)`.
  - `web/ui/gear.mjs` (inspect the call site of `wowheadUrl`).
  - `web/zones.mjs` and `web/ui/mapview.mjs:342`.
  - Create `web/i18n/zones.mjs`: `export default { de: { <mapId>: 'Name' }, fr: {...}, ... }`.
  - `web/test/gear.test.mjs`, `web/test/mapview.test.mjs`.
- **Implementation:**
  - First confirm the Wowhead URL format for Classic in each language: fetch
    `https://www.wowhead.com/classic/de/item=19019` and the same for `fr`, `es`, `it`, `pt`. Expect a page in that
    language. Confirm that the tooltip widget (`web/wowhead.js`, inspect) reads the language from the link. When a
    language fails, use the English URL for it and record it under Open Decisions in this file.
  - `wowheadUrl(id, code)`: `en` gives `https://www.wowhead.com/classic/item=<id>`; others give
    `https://www.wowhead.com/classic/<code>/item=<id>`. Keep the integer check. Accept only the 6 codes.
  - Zone labels: for each `mapId` in `web/zones.mjs`, take the official name in each language from the Classic
    `UiMap` or `AreaTable` data (wago.tools, Classic Era build, with the locale filter). A zone with no official name
    (WoW Forever custom zones) has no entry.
  - `mapview.mjs`: draw `zoneName(mapId, code)`, which falls back to `ZONES[mapId].name`.
  - CSP: no change. Check that `characterPagePolicy` already allows the hosts.
- **Edge cases:**
  - `id` not an integer: no link, as today.
  - `code` unknown: English URL.
  - A `mapId` that is not in the zone catalog: English name.
- **Tests (unit):**
  - `gear.test.mjs`: `wowheadUrl(19019, 'en')` and `wowheadUrl(19019, 'de')`; bad id; bad code.
  - `mapview.test.mjs`: the label of a known zone in `fr`; the English fallback for an unknown `mapId`; every key of
    `web/i18n/zones.mjs` is a `mapId` in `web/zones.mjs`.
- **Verify:**
  - `make web-lint`
  - `make web-test`
  - Manual: a German character page; hover a gear slot; the tooltip shows the German item name; the map shows
    "Wald von Elwynn".
- **Definition of done:**
  - [ ] Each Covers item is observably met, including one observation that failed before the task (the German map
        showed "Elwynn Forest").
  - [ ] Tests listed above exist and follow the Tests guidelines.
  - [ ] Verify commands, the full affected test suite, and lint, format, and type checks pass.
  - [ ] E2E tests pass, or the accepted alternative from Risks is done.
  - [ ] All three reviews pass with no valid open findings.
  - [ ] Docs and config that describe the changed behavior are updated.
  - [ ] Task heading checkbox ticked; changes committed.

## Validation

Run after the last task.

**Automated**

1. `make lint`
2. `make test`
3. `make coverage`
4. `make web-test`
5. `make e2e`

**Manual (the e2e gap accepted in D20)**

1. In the game with a German client (or `SET textLocale "deDE"` in `WTF/Config.wtf`): the addon list shows the German
   title and notes; `/memories status`, the Settings page, the minimap tooltip and the save reminder are German.
2. Same with `esES` and `itIT`: spot-check the Settings page.
3. In the game with `enUS`: every text is as before this change.
4. Kill the last boss of a dungeon on a Spanish client: `/memories status` or the journal shows a clear.
5. App: Settings → Language → Español. Every screen and the tray menu turn Spanish at once. Restart: still Spanish.
   Choose System with the OS in German: German.
6. App on macOS with the system language Français: French.
7. Website: open the home page with the browser in Italian: Italian. Click Português in the picker: Portuguese, and
   the cookie is set. Open an unknown path: the 404 page is Portuguese.
8. Website: delete the cookie. Open a character uploaded from a German client with the browser in English: the page
   is German. Choose English in the picker: English, and the hash (tab and camera) stays.
9. Website: a German page shows German Wowhead tooltips and German zone labels.

## References

- WoW `GetLocale` return values: https://warcraft.wiki.gg/wiki/API_GetLocale
- TOC localized fields (`Title-<locale>`, order rule): https://warcraft.wiki.gg/wiki/TOC_format
- Addon localization pattern: https://warcraft.wiki.gg/wiki/Localizing_an_addon
- Portuguese client in the EU uses `ptBR`:
  https://worldofwarcraft.blizzard.com/en-gb/news/10035825/world-of-warcraft-is-now-available-in-portuguese-brazilian
- Flutter internationalization: https://docs.flutter.dev/ui/internationalization
- Flutter `gen_l10n` source in the tree (synthetic package removed):
  https://docs.flutter.dev/release/breaking-changes/flutter-generate-i10n-source
- ICU plural rules in JavaScript: https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Intl/PluralRules
- HTTP `Accept-Language`: https://www.rfc-editor.org/rfc/rfc9110#name-accept-language
- Fragment kept across a redirect: https://www.rfc-editor.org/rfc/rfc9110#section-10.2.2
- Cinzel coverage (Latin and Latin Extended only): https://fonts.google.com/specimen/Cinzel
- Classic DB2 tables for encounter IDs and zone names: https://wago.tools/db2

## Open Decisions

None at the time of writing. Task 9 adds an entry here if a Wowhead language path does not work.

## Completion

When every task is checked and Validation passes, move this file to `specs/done/` with `git mv` (plain `mv` when the
file is untracked). Create `specs/done/` if it does not exist. Commit the move.
