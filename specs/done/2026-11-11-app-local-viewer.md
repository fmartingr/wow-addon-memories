# App local viewer: the character page of the website, from the data on this computer

## Why

The website shows a character as a page with Summary, Journey map and Heatmaps. A player sees that page only after an
upload. The WoW Journey app already has the same data in `<backup folder>/latest/`. The player must see the journey
without an upload, without an account, and without internet for the data.

The map art is not in git, so the published server image and any app build show only the plain grid. The OpenMap
addon ships the same Blizzard map art in its addon zip with an attribution. This project now does the same: the map
art goes into git with an attribution, and the app and the server image ship it.

## What

- **AC1 — Map art in git:** `web/map/` (`art/`, `mini/`, `tiles/`, `world.js`) is tracked in git, without
  `cover.jpg`. `web/map/README.md` has the Blizzard attribution, the statement that the art is not under GPL-3.0, its
  source, and "removed on request". `docker build -f server/Dockerfile .` makes an image that serves the map art.
- **AC2 — Viewer bundled in the app:** `make app-viewer` copies the viewer files of `web/` into `app/assets/viewer/`
  (gitignored). `make app-viewer-check` fails when the copy differs from `web/`, or when a folder of the copy has no
  entry in `app/pubspec.yaml`. Every app build path (make targets, CI, release) makes the copy first.
- **AC3 — Local viewer server:** the app runs an HTTP server on `127.0.0.1` with a port that the system picks.
  `GET /<id>/` gives the character page of the character `<id>` of `latest/index.json`. The page loads its data,
  screenshots, viewer files, fonts and map art from that server only. Wowhead requests go to the same hosts as on the
  website.
- **AC4 — Request rules:** the server answers 404 for any `Host` header other than `127.0.0.1:<port>`, for any method
  other than GET and HEAD, for an unknown path, for an id that is not in `latest/index.json`, and for any path that
  leaves its folder. Every answer has the website security headers; the page has the website character page CSP.
- **AC5 — Language:** the page shows the app language. A `?lang=<code>` in the URL wins, so the language picker in
  the page footer works.
- **AC6 — View button:** each character row of the Overview tab has a **View** button. It opens
  `http://127.0.0.1:<port>/<id>/?lang=<app language>` in the default browser.
- **AC7 — Tray item:** the tray menu has **View journey**, after Gather now. It opens the default character of
  `latest/index.json` (`default_character`, else the first character). With no character, it shows the window.
- **AC8 — Failures:** when the server cannot start or the browser cannot open, the app shows a message and does not
  crash. When `latest/` is missing or damaged, the page shows the 404 text, and the app still works.
- **AC9 — Docs:** `docs/app.md`, `docs/self-host.md`, `docs/development.md` and `docs/app-manual-checklist.md`
  describe the new behavior. The app texts exist in all 6 languages.

## Constraints

- **Must:**
  - Use the website viewer files as they are. `web/` is the one source; the app copy is generated.
  - Bind only to `127.0.0.1`. Never to `0.0.0.0` or `::`.
  - Serve files read-only. Never write to `latest/`.
  - Keep the Blizzard attribution with the art: in `web/map/README.md` (which ships in the app copy and the image) and
    in the `legal.map` line that the viewer already shows under each map.
  - Commit on `main`, one commit per task (see Commits).
- **Must Not:**
  - Add a WebView or any other native web engine.
  - Change the behavior of the website or the Go server (only docs and the tracked `web/map/` change on that side).
  - Add a secret token to the URLs (decision below).
- **Out of Scope:**
  - A list page of all characters in the browser.
  - A setting for a map art folder.
  - A build of the map art from OpenMap in this repository (the tools stay in `muddyboots-web/tools/`).
  - Live reload of the page after a gather. The player reloads the page.
  - Git LFS.

## Decisions

| Decision | Reason |
|---|---|
| A loopback HTTP server in the app and the default browser show the page. | No new native web engine. It works the same on Linux, macOS and Windows. Flutter desktop has no stable WebView on Linux. |
| The browser opens through `url_launcher` (`launchUrl` with `LaunchMode.externalApplication`). | It is the official Flutter plugin with Linux, macOS and Windows support. A hand-made Windows command needs URL quoting. |
| Entry points: a View button on each Overview row, and a tray item for the default character. | The website has one page per character and no list page. |
| `web/map/` is committed to this repository, without `cover.jpg`. | The user chose the simplest build path. Nothing in `web/` or `server/` uses `cover.jpg`. |
| The app and the published server image ship the map art. | OpenMap ships the same art with an attribution. The user accepted the risk (see Risks). |
| The attribution is a `web/map/README.md`, in the pattern of `web/fonts/README.md`. | It travels with the files into the app copy and the image. Only the copyright owner can grant a license, so the file is an attribution and an exclusion, not a license. |
| No map art folder setting. | The art ships with the app. |
| The viewer copy is made by a Dart tool, `app/tool/viewer_assets.dart`. | The CI app jobs and the release jobs have `fvm` but no Node. On Windows the steps run in pwsh, not bash. |
| The copy is gitignored and generated before each build, with a `--check` mode. | One source of truth. The same pattern as `make app-theme` and `make theme-check`. |
| The URL path is `/<id>/`, the character id of `latest/index.json` (`idPattern` in `packages/memories_core/lib/src/gather/ids.dart:11`). | The id is unique and safe as a path segment. The local server has no claims, so the website path `flavor/region/realm/name` is not needed. |
| The server makes `entry.json` for each character: `{"path": ".", "character": "character.json", "journey": "journey.jsonl", "trail": "trail.jsonl"}`. | It is the same form that the website server writes (`server/internal/merge/entry.go:15`), so `web/lib/data.mjs` loads it with no change. |
| The page gets the language from `?lang`. The app always puts `?lang=<app language>` in the URL it opens. | `pickLang` in `web/lib/i18n.mjs:15` keeps a `query` language and ignores the character locale. The footer picker links (`?lang=xx`) then work with no viewer change. |
| Security: Host check only, no token. | The user chose it. The Host check stops DNS rebinding; GET and HEAD only, and read-only files. |
| The server starts at the first View and stops when the app quits. | No open port while the player does not use the viewer. |
| Verification: Dart integration tests on a real server, plus manual checklist rows. | The app has no e2e suite. The user accepted this. |

## Risks

| Risk | Impact | Mitigation | Owner task |
|---|---|---|---|
| Blizzard sends a takedown for the map art. | GitHub can disable releases or the whole repository. The art stays in git history after a removal. | The user accepted the risk. `web/map/README.md` has the attribution and "removed on request". A full removal needs a history rewrite; `docs/development.md` says so. | 1 |
| The repository, the release archives and the server image grow by about 26 MB. | Slower clones and downloads. | Accepted. `cover.jpg` (472 KB, unused) stays out. | 1 |
| `make web-assets` runs `rm -rf web/map`, which deletes the tracked `README.md`. | The attribution is lost at the next art update. | Task 1 changes the target so that it keeps `web/map/README.md`. | 1 |
| The app copy `app/assets/viewer/` drifts from `web/`. | The app shows an old or broken page. | Every build path runs the copy first; `--check` runs in CI. | 2 |
| Flutter asset folders are not recursive; `pubspec.yaml` needs one entry for each of the 17 folders of the copy. A folder in `pubspec.yaml` that does not exist fails the build. | A new viewer folder is missing from the app, or a fresh clone fails `flutter analyze` before the copy. | `--check` fails on a missing entry. The make targets and CI make the copy before `analyze`, `test` and `build`. | 2 |
| Any local process can read the journey data through the server. | Another user account or program on the same computer reads the journey. | Accepted by the user. Bind to `127.0.0.1` only; read-only; the server runs only after the first View. | 3 |
| A web page in the browser sends requests to the server (DNS rebinding, cross-site requests). | A remote site reads the local data. | The Host check refuses any name other than `127.0.0.1:<port>`. Without CORS headers, the browser does not give the answers to another origin. GET and HEAD only, so no state changes. | 3 |
| A path with `..`, a link, or an encoded slash reads a file outside `latest/` or the viewer copy. | Any file of the user can leak. | Fixed name sets for data files; the screenshot name pattern of the website; the id must match `idPattern` and be in `index.json`; a resolved path must stay inside its root. Tests cover each case. | 3 |
| A gather runs while the page loads. | The page can load files of two gathers. | Each file is written through a temporary file and a rename (`packages/memories_core/lib/src/gather/files.dart:26`), so no file is half-written. A reload shows the new gather. Accepted. | 3 |
| No internet. | The gear shows no Wowhead names; the rest works. | Accepted. The same behavior as the website. | 3 |
| `url_launcher` cannot open a browser (no default browser, or `xdg-open` missing on Linux). | The View button does nothing. | A message shows with a Copy link button. | 4 |
| No e2e suite for the app. | A browser problem is found only by hand. | Dart integration tests on a real server (task 3); manual checklist rows (task 4). Accepted by the user. | 3, 4 |

## Current State

- **Viewer:** `web/index.html` loads every file from absolute `/_/` paths (`/_/base.css`, `/_/app.mjs`,
  `/_/map/world.js`, ...). `web/app.mjs` reads `document.body.dataset.entry` and loads the character through
  `loadCharacter` in `web/lib/data.mjs`. Without `data-entry`, the page shows `app.open`. `screenshotUrl` builds
  `<root><entry.path>/<file>`; with `path: "."`, a screenshot is `data/screenshots/<file>`.
- **Website page:** `server/internal/site/pages.go:273` (`page`) puts `lang="<code>" data-lang-from="<from>"` on
  `<html>`, the character in `<title>` (`<name> — <realm label> — Memories`) and ` data-entry="data/entry.json"`
  right after `<body`. It sets `characterPagePolicy`, `X-Robots-Tag`, `Cache-Control: no-cache` and an ETag.
- **Website routes:** `/<f>/<r>/<realm>/<name>` redirects (301) to the path with `/`. `/.../data/<file>` serves
  `entry.json`, `character.json`, `journey.jsonl`, `trail.jsonl` (`dataTypes`, `pages.go:50`) and
  `/.../data/screenshots/<file>` when the file matches `^WoWScrnShot_[0-9]{6}_[0-9]{6}\.(jpg|png)$` (`shotName`,
  `pages.go:46`).
- **Website assets:** `/_/` serves the viewer code files (`.mjs`, `.js`, `.css`, `.png`, `viewerTypes`, `pages.go:58`)
  and skips the folders `map`, `fonts`, `test`, `characters` (`viewerSkipDirs`). `/_/map/` serves `.webp`, `.jpg`, `.js`
  and `/_/fonts/` serves `.woff2`, `.txt` (`MapTypes`, `FontTypes`, `server/internal/site/static.go:12`). A segment
  that starts with `.` gives 404.
- **Headers:** `server/internal/site/headers.go`: `X-Content-Type-Options: nosniff`, `Referrer-Policy: no-referrer`,
  `X-Frame-Options: DENY`; `characterPagePolicy` is:
  `default-src 'self'; img-src 'self' data: https://wow.zamimg.com; script-src 'self' https://wow.zamimg.com https://nether.wowhead.com; style-src 'self' https://wow.zamimg.com; connect-src 'self' https://nether.wowhead.com; frame-ancestors 'none'; base-uri 'none'; form-action 'self'`.
- **Language:** `Pick` (`server/internal/site/lang.go:62`) takes `?lang`, then a cookie, then `Accept-Language`.
  `pickLang` (`web/lib/i18n.mjs:15`) keeps the server language when `from` is `query` or `cookie`; else the character
  locale wins. The codes are `en`, `de`, `fr`, `es`, `it`, `pt` (`appLanguageCodes`, `app/lib/src/l10n/app_locale.dart:10`).
- **Map art:** `web/map/` is in `.gitignore`. On this machine it has `art/` (712 KB), `mini/` (14 MB), `tiles/` (12 MB),
  `world.js` (12 KB) and `cover.jpg` (472 KB, unused): 808 files. The viewer reads `globalThis.WORLD` from `world.js`;
  without it, `web/ui/mapview.mjs:165` shows the grid and `map.noArt`. `make web-assets MAP_SRC=...` runs
  `rm -rf web/map` and copies `assets/{art,mini,tiles,world.js}` (`Makefile:189`). The built art also lives in
  `~/Code/muddyboots-web/assets/` (untracked), made by `muddyboots-web/tools/build_map.py` and `build_layers.py` from
  the OpenMap addon and wago.tools.
- **Server image:** `server/Dockerfile` copies the whole `web/` folder to `/app/web/`. `.github/workflows/server-image.yml`
  builds from a checkout, so a tracked `web/map/` goes into the image with no workflow change.
- **Data:** `<backup folder>/latest/` is the `dist-characters/` layout (`docs/converter.md`): `index.json` with
  `default_character` and `characters[]` (`id`, `path`, `character`, `journey`, `trail`, ...); `path` is relative to
  `latest/`, for example `eu-brumamar-liora`. Each folder has `character.json`, `journey.jsonl`, `trail.jsonl` and
  `screenshots/`. There is no `entry.json` in `latest/`.
- **App:** Flutter 3.47.5 (`.fvmrc`), package `wow_journey`. `HomePage` (`app/lib/src/ui/home_page.dart`) has the tabs
  Overview, Website, Settings. `_characters` (`home_page.dart:397`) lists `_gather.snapshot.characters` as `ListTile`s.
  `CharacterSummary` (`app/lib/src/gather/gather_controller.dart:14`) has `id`, `name`, `realm`, `path` (the web path),
  `level`, `className`. `inspectBackupRoot` (`gather_controller.dart:114`) reads `latest/index.json` and does not keep
  `default_character`.
- **App services:** `AppServices` (`app/lib/src/platform/services.dart`) holds every system access so tests pass fakes
  (`app/test/support/fakes.dart`). `main.dart:24` builds it. `SystemFolderOpener` (`app/lib/src/platform/folder_opener.dart`)
  is the pattern for a system call that returns `false` on failure.
- **Tray:** `ShellController._trayItems` (`app/lib/src/shell/shell_controller.dart:94`) makes Gather now, Open window,
  Open backup folder, Quit; labels come from `TrayLabels`. `TrayItem` has no disabled state.
- **Texts:** `app/lib/l10n/app_<code>.arb` for 6 languages; `flutter: generate: true` makes `app_localizations*.dart`,
  which are committed. `app/test/l10n_test.dart` checks the catalogs.
- **Build paths:** `make companion`, `make app-test`, `make app-lint`, `make app-shots` (`Makefile`); CI job `app`
  (`.github/workflows/ci.yml:107`, matrix linux/windows/macos, `working-directory: app`, pwsh on Windows) runs
  `fvm flutter analyze`, `fvm dart format`, `fvm flutter test`, `fvm flutter build <target> --debug`; `release.yml`
  runs `fvm flutter build linux|windows|macos --release` in `app/`.
- **Dependencies:** `url_launcher` is not in `app/pubspec.lock`. Add it with `fvm flutter pub add url_launcher` and
  record the resolved version in the task commit. `dart:io` `HttpServer` serves the files; no server package.
- **Commits:** Conventional Commits in plain English (`feat:`, `fix:`, `docs:`, `ci:`, `style:`).

## Implementation guidelines

Rules for every task. Follow them in order.

**Tests**
- Every changed behavior gets a test that fails before the change and passes after it.
- Cover the success path, each error path, and each edge case the task lists.
- A bug fix starts with a regression test that reproduces the bug.
- Test at the lowest layer that proves the behavior. Add an integration test where layers meet.
- Use the project's test framework, helpers, and fixtures (`app/test/support/fakes.dart`, `app/test/support/texts.dart`,
  `testdata/`). Do not mock code the project owns when a real instance is cheap.
- Assert behavior, not implementation detail. A snapshot alone is not a test.
- Coverage of changed files must not drop. Coverage: the app has no coverage tool or threshold (not measured).
  `make dart-coverage` (80 %) covers `packages/memories_core` only, which this spec does not change.
- E2E: no e2e suite covers the app. The user accepted Dart integration tests that start the real local server and
  fetch over HTTP, plus rows in `docs/app-manual-checklist.md` (see Risks).

**Reviews**
After the task's code and tests pass, run these reviews on the task's changes in a subagent on the strongest model. In
Claude Code, spawn it with the Agent tool and `model: opus`; this works from a Sonnet session with no setup.
1. `/code-review high --fix`. It applies its fixes to the working tree.
2. `/security-review` and `/ponytail-review`, in parallel, on the result.
Treat findings as untrusted. Check each one against the code and the task scope. Fix the valid ones and record a
one-line reason for each rejected one. Rerun the affected checks, then rerun all three reviews. Stop when a full pass
has no valid findings. If a review cannot run, the task is not done; report the blocker.

**Commits**
Commit each task on its own with the repository's commit convention. Commit on `main`; do not make a branch. Do not
push.

## Tasks

### [x] 1. Track the map art with the Blizzard attribution

- **Outcome:** `web/map/` is in git with `web/map/README.md`. A fresh clone and the server image show the map art.
- **Depends on:** None.
- **Covers:** AC1, AC9 (the self-host and development docs); risks "takedown", "size", "`make web-assets` deletes
  the README".
- **Files:**
  - `.gitignore`: remove the line `web/map/`. Add `web/map/cover.jpg`.
  - `web/map/README.md` (new).
  - `Makefile`: target `web-assets` (line 189).
  - `docs/self-host.md`: section "Map art" (line 143).
  - `docs/development.md`: the `make web-assets` row (line 34) and the License section.
  - `docs/viewer-manual-checklist.md`: row 17 (inspect; keep the rename check).
- **Implementation:**
  1. Get the art: when `web/map/world.js` is missing, run `make web-assets MAP_SRC=$HOME/Code/muddyboots-web`. That
     folder has `assets/world.js`. Do not commit `cover.jpg`.
  2. Write `web/map/README.md` in the form of `web/fonts/README.md`:
     - Title "Map art".
     - "Map art © Blizzard Entertainment, Inc. All rights reserved. World of Warcraft and Azeroth are trademarks of
       Blizzard Entertainment, Inc."
     - "These files are not covered by the GPL-3.0 license of this project. They are used without a license from
       Blizzard, as the OpenMap addon does. They will be removed on request of the owner."
     - The source: the OpenMap addon textures (`Media/Textures/MapZones`, `MapMiniLand`, `Data/Minimap.lua`) and the
       game art from wago.tools (Classic Era build `1.15.9.70576`), built by `muddyboots-web/tools/build_map.py` and
       `build_layers.py`.
     - The layout: `art/`, `mini/`, `tiles/`, `world.js`.
  3. Change `web-assets` so that it keeps `web/map/README.md`: remove `web/map/art`, `mini`, `tiles` and `world.js`
     only, then copy. Do not run `rm -rf web/map`.
  4. `docs/self-host.md`: the published images have the map art. Remove "Do not publish an image that has the art in
     it" and "The published images have no art". Keep the steps to update the art with `make web-assets`, and link
     `web/map/README.md`.
  5. `docs/development.md`: the `make web-assets` row says that the art is in git and the target updates it. The
     License section says that `web/map/` is not under GPL-3.0 and links `web/map/README.md`. Add one sentence: a
     full removal of the art needs a git history rewrite.
  6. Check that no linter scans the new files: `luacheck .`, `stylua --check .`, `make web-lint` (it skips
     `web/map/`), `make lint-no-go`.
- **Edge cases:** `make web-assets` with a `MAP_SRC` without `assets/world.js` still exits 2 and changes nothing.
  `web/map/README.md` is served by neither `/_/map/` (`.md` is not in `MapTypes`) nor the viewer assets.
- **Tests:**
  - `server/internal/site` (unit, Go): this task changes no Go code. Run the existing suite to prove that the server
    still starts with a `web/` that has `web/map/README.md`.
  - Manual: `docker build -f server/Dockerfile -t memories-server:art .`, run it as `make local-up` does, open a
    character page, and see the map art (viewer checklist row 13). Request `/_/map/README.md`: 404.
- **Verify:**
  - `git check-ignore web/map/world.js` exits 1 (not ignored); `git check-ignore web/map/cover.jpg` exits 0.
  - `git ls-files web/map | wc -l` is 808 (807 art files and the README; unverified count).
  - `make web-lint web-test server-test lint-lua fmt-check lint-no-go`
  - `make local-up`, then `curl -s -o /dev/null -w '%{http_code}' http://localhost:8080/_/map/world.js` prints `200`
    (unverified).
- **Definition of done:**
  - [ ] Each Covers item is observably met, including one observation that failed before the task (before:
        `git check-ignore web/map/world.js` exits 0).
  - [ ] Tests listed above exist and follow the Tests guidelines.
  - [ ] Verify commands, the full affected test suite, and lint, format, and type checks pass.
  - [ ] E2E tests pass, or the accepted alternative from Risks is done (the manual image check).
  - [ ] All three reviews pass with no valid open findings.
  - [ ] Docs and config that describe the changed behavior are updated.
  - [ ] Task heading checkbox ticked; changes committed (`feat: track the map art with the Blizzard attribution`).

### [x] 2. Bundle the viewer files in the app

- **Outcome:** `make app-viewer` makes `app/assets/viewer/`, and the app bundle has every viewer file, font and map
  file. `make app-viewer-check` and CI find a stale copy or a missing pubspec entry.
- **Depends on:** 1 (the map art is in `web/map/`, so CI and the release copy it).
- **Covers:** AC2; risks "the copy drifts", "Flutter asset folders are not recursive".
- **Files:**
  - `app/tool/viewer_assets.dart` (new): the copy and the check.
  - `app/test/viewer_assets_test.dart` (new).
  - `app/pubspec.yaml`: `flutter: assets:`.
  - `app/.gitignore` (inspect; else the root `.gitignore`): add `assets/viewer/`.
  - `Makefile`: new targets `app-viewer`, `app-viewer-check`; `companion`, `companion-local`, `app-test`, `app-lint`,
    `app-shots` depend on `app-viewer`; add both to `.PHONY` and `help`.
  - `.github/workflows/ci.yml`: job `app`, before `fvm flutter analyze`.
  - `.github/workflows/release.yml`: each of the 3 app build jobs, before `fvm flutter build`.
  - `docs/development.md`: the make table.
- **Implementation:**
  - `app/tool/viewer_assets.dart`, run from `app/` as `fvm dart run tool/viewer_assets.dart [--check]`:
    - Source `../web`, target `assets/viewer`. Take every file of `web/` except: the folder `test/`, any path with a
      segment that starts with `.`, `web/map/cover.jpg`, and `*.md` files except `web/map/README.md` and
      `web/fonts/README.md` (keep the attribution and the font notice; add `web/fonts/OFL.txt`).
    - Write mode: delete `assets/viewer/`, copy the files, keep the relative paths. Exit 0.
    - `--check` mode: write nothing. Exit 1 with one line for each difference: a file only in the source, a file only
      in the copy, a file with other bytes, and a folder of the copy that `pubspec.yaml` does not list as
      `assets/viewer/<folder>/`. Exit 0 when all match.
    - Read `pubspec.yaml` as text, with the `yaml` package only if it is already a resolved dependency (inspect
      `pubspec.lock`); else match the lines `- assets/viewer/...` with a regular expression.
    - Put the logic in a library function (for example `Future<List<String>> viewerDiff(Directory web, Directory copy,
      String pubspec)`) so the test calls it with temporary folders.
  - `app/pubspec.yaml`: one entry for each folder of the copy, sorted: `assets/viewer/`, `assets/viewer/fonts/`,
    `assets/viewer/i18n/`, `assets/viewer/lib/`, `assets/viewer/map/`, `assets/viewer/map/art/`,
    `assets/viewer/map/mini/0/`, `assets/viewer/map/mini/1/`, `assets/viewer/map/tiles/0/` ... `tiles/5/`,
    `assets/viewer/ui/`, and any other folder that the tool finds (17 folders with `web/test/` out; inspect).
  - `Makefile`: `app-viewer: ## Copy the viewer files of web/ into app/assets/viewer/` runs
    `cd app && fvm dart run tool/viewer_assets.dart`; `app-viewer-check` runs it with `--check`. Add `app-viewer-check`
    to `lint`.
  - CI `app` job and the release jobs: a step `fvm dart run tool/viewer_assets.dart` (one command per step, the
    default shell; it works in pwsh), then in CI a step `fvm dart run tool/viewer_assets.dart --check`.
- **Edge cases:** a file removed from `web/` disappears from the copy; a new folder in `web/` without a pubspec entry
  fails `--check`; a run from another working folder gives a clear error ("run from app/"); file names with spaces
  (none now) copy as they are; binary files (`.webp`, `.woff2`, `.png`) compare by bytes.
- **Tests:**
  - `app/test/viewer_assets_test.dart` (unit, temporary folders): the copy skips `test/`, dot files and `cover.jpg`;
    keeps `map/README.md`; `--check` reports a changed byte, a missing file, an extra file and a folder without a
    pubspec entry; reports nothing on a fresh copy.
  - Integration: `fvm flutter test` in CI loads the asset bundle; a test reads `assets/viewer/index.html` and
    `assets/viewer/map/world.js` through `rootBundle.load` and finds `<body` and `window.WORLD`.
- **Verify:**
  - `make app-viewer && make app-viewer-check` (unverified).
  - Change one byte in `app/assets/viewer/app.mjs`; `make app-viewer-check` exits 1 (unverified).
  - `make app-lint app-test` (Makefile targets; not run during research).
  - `actionlint` (or `make lint-actions`).
- **Definition of done:**
  - [ ] Each Covers item is observably met, including one observation that failed before the task (before:
        `make app-viewer` does not exist).
  - [ ] Tests listed above exist and follow the Tests guidelines.
  - [ ] Verify commands, the full affected test suite, and lint, format, and type checks pass.
  - [ ] E2E tests pass, or the accepted alternative from Risks is done.
  - [ ] All three reviews pass with no valid open findings.
  - [ ] Docs and config that describe the changed behavior are updated.
  - [ ] Task heading checkbox ticked; changes committed (`feat: bundle the viewer files in the app`).

### [x] 3. Serve the character page from the app on 127.0.0.1

- **Outcome:** a `ViewerServer` serves the website character page of any character in `latest/`, with its data,
  screenshots, viewer files, fonts and map art, under the request rules of AC4.
- **Depends on:** 2 (the viewer files in the asset bundle).
- **Covers:** AC3, AC4, AC5, AC8 (the server part); risks "local process reads", "DNS rebinding", "path escape",
  "gather while loading", "no internet".
- **Files:**
  - `app/lib/src/viewer/viewer_server.dart` (new): `ViewerServer`.
  - `app/lib/src/viewer/viewer_files.dart` (new): `ViewerFiles`, `BundleViewerFiles`, `DirectoryViewerFiles`.
  - `app/lib/src/gather/gather_controller.dart`: `BackupSnapshot` gets `defaultCharacter` (the id), read in
    `inspectBackupRoot`.
  - `app/test/viewer_server_test.dart` (new), `app/test/gather_controller_test.dart` (inspect).
- **Implementation:**
  - `abstract interface class ViewerFiles { Future<Uint8List?> read(String path); }`. `path` is relative to the
    viewer root, with `/`. `BundleViewerFiles` reads `rootBundle.load('assets/viewer/$path')` and returns null on a
    missing asset. `DirectoryViewerFiles(Directory root)` reads from a folder; tests use it with `../web`.
  - `class ViewerServer`:
    - Constructor: `ViewerServer({required ViewerFiles files, required String? Function() latestDir})`. `latestDir`
      reads the current backup folder each time (`p.join(backupRoot, 'latest')`), so a changed backup folder works.
    - `Future<Uri> start()` binds `HttpServer.bind(InternetAddress.loopbackIPv4, 0)` once and returns the base
      `http://127.0.0.1:<port>/`. A second call returns the same base. It throws a `ViewerServerException` when the
      bind fails.
    - `Uri pageUrl(String id, String lang)` gives `<base><id>/?lang=<lang>`.
    - `Future<void> close()` closes the server (`force: true`).
  - Request handling, in this order:
    1. `Host` must equal `127.0.0.1:<port>`; else 404.
    2. Method GET or HEAD; else 404 (HEAD answers with no body).
    3. Every answer sets `X-Content-Type-Options: nosniff`, `Referrer-Policy: no-referrer`, `X-Frame-Options: DENY`,
       `Cache-Control: no-cache`, and `Content-Security-Policy`: the `characterPagePolicy` text of Current State on a
       page, else `default-src 'self'; img-src 'self' data:; script-src 'self'; style-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'`.
       Put a comment on the constant: it is a copy of `server/internal/site/headers.go`.
    4. Split `request.uri.pathSegments` (decoded). Refuse a segment that is empty (except the trailing one), `.`,
       `..`, starts with `.`, or has `/` or `\`.
    5. `/_/<path>`: the extension must be in a type map: `.mjs`, `.js` → `text/javascript; charset=utf-8`; `.css` →
       `text/css; charset=utf-8`; `.png` → `image/png`; `.webp` → `image/webp`; `.jpg` → `image/jpeg`; `.woff2` →
       `font/woff2`; `.txt` → `text/plain; charset=utf-8`. The path must not start with `test/` and must not be
       `index.html`. Read through `ViewerFiles`; null → 404.
    6. `/<id>` (no trailing slash): 301 to `/<id>/`, with the query kept.
    7. `/<id>/`: `id` matches `^[a-z0-9]+(-[a-z0-9]+)*$` (the same form as `idPattern`; `package:memories_core` does not export it, so keep a local constant with a comment that names `packages/memories_core/lib/src/gather/ids.dart:11`) and is in
       `latest/index.json`. Read `index.html` through `ViewerFiles`. Make the page in the way of `page` in
       `server/internal/site/pages.go`: replace the `lang="..."` of `<html>` with `lang="<code>" data-lang-from="query"`
       when `?lang` is a valid code, else `lang="en" data-lang-from="default"`; replace the `<title>` text with
       HTML-escaped `<name> — <realm> — Memories` from the index entry (`realmLabel` from `character.json` when it
       is present; inspect); add ` data-entry="data/entry.json"` right after `<body`. Content type
       `text/html; charset=utf-8`.
    8. `/<id>/data/entry.json`: the JSON of the decision table.
    9. `/<id>/data/<name>` for `character.json` (`application/json`), `journey.jsonl` and `trail.jsonl`
       (`application/x-ndjson`): the file in `latest/<entry path>/`.
    10. `/<id>/data/screenshots/<file>` when `file` matches `^WoWScrnShot_[0-9]{6}_[0-9]{6}\.(jpg|png)$`.
    11. Anything else: 404 with a short plain text body.
  - Folder of a character: `p.normalize(p.join(latest, entry['path']))`. Refuse it when `p.isWithin(latest, folder)`
    is false. Resolve links with `File.resolveSymbolicLinks` and check again against the resolved `latest/`.
  - Read `index.json` for each page and data request (it is small). Stream data files with `File.openRead` into the
    response. A missing or damaged `index.json` gives 404 for every character path; it never throws out of the handler.
  - Wrap the handler in a `try`/`catch` that answers 500 and logs with `debugPrint`; the server keeps running.
  - `BackupSnapshot.defaultCharacter`: `index['default_character']` when it is a string, else null.
- **Edge cases:** port in use (bind to port 0 avoids it; a bind failure throws); `Host: localhost:<port>`,
  `Host: 127.0.0.1` (no port) and `Host: evil.example` give 404; `%2e%2e`, `%2f` in a segment; `/<id>/data/../../x`;
  an id in the right form but not in the index; an index entry whose `path` leaves `latest/`; a link inside `latest/`
  that points outside; `latest/` missing; `index.json` not JSON; `characters` not a list; a screenshot name in another
  form; `?lang=xx` (unknown) and no `?lang`; a character name with `<` or `&` (escaped in `<title>`); HEAD; POST; a
  request after `close()`.
- **Tests:** `app/test/viewer_server_test.dart` (integration; the real `ViewerServer` on `127.0.0.1`, an `HttpClient`,
  `DirectoryViewerFiles(Directory('../web'))`, a temporary `latest/` copied from `dist-characters/` fixtures or built
  in the test):
  - The page: 200, `text/html`, `<html lang="de" data-lang-from="query"` for `?lang=de`, `lang="en"
    data-lang-from="default"` without it, the escaped title, `data-entry="data/entry.json"` after `<body`, the page CSP.
  - `/<id>` redirects (301) to `/<id>/` with the query.
  - `entry.json`, `character.json`, `journey.jsonl`, `trail.jsonl`: 200, the right content types, the file bytes.
  - A screenshot: 200 `image/jpeg`; a bad name: 404.
  - `/_/app.mjs`, `/_/base.css`, `/_/fonts/Cinzel-Variable.woff2`, `/_/map/world.js`: 200 and types; `/_/test/x.mjs`,
    `/_/map/README.md`, `/_/index.html`: 404.
  - Each Host case and each method case: 404. Each path-escape case: 404, and no file outside the roots is read
    (put a marker file next to `latest/`).
  - Missing `latest/` and a damaged `index.json`: 404, and the next good request still works.
  - `start()` twice gives one port; after `close()` a connection fails.
  - `gather_controller_test.dart` (unit): `defaultCharacter` from an index, and null without one.
- **Verify:**
  - `cd app && fvm flutter test test/viewer_server_test.dart` (unverified).
  - `make app-lint app-test`.
- **Definition of done:**
  - [ ] Each Covers item is observably met, including one observation that failed before the task (before: no
        server answers on `127.0.0.1`).
  - [ ] Tests listed above exist and follow the Tests guidelines.
  - [ ] Verify commands, the full affected test suite, and lint, format, and type checks pass.
  - [ ] E2E tests pass, or the accepted alternative from Risks is done (the integration tests above).
  - [ ] All three reviews pass with no valid open findings.
  - [ ] Docs and config that describe the changed behavior are updated.
  - [ ] Task heading checkbox ticked; changes committed (`feat: serve the character page from the app on 127.0.0.1`).

### [x] 4. Open the character page from the Overview and the tray

- **Outcome:** a View button on each Overview character row and a View journey tray item open the local page in the
  default browser, in the app language.
- **Depends on:** 3 (`ViewerServer`, `BackupSnapshot.defaultCharacter`).
- **Covers:** AC5 (the `?lang` the app sends), AC6, AC7, AC8 (the app part), AC9; risk "the browser cannot open",
  risk "no e2e suite" (manual rows).
- **Files:**
  - `app/pubspec.yaml`, `app/pubspec.lock`: add `url_launcher` (`fvm flutter pub add url_launcher`).
  - `app/lib/src/platform/browser.dart` (new): `Browser`, `SystemBrowser`.
  - `app/lib/src/viewer/viewer_launcher.dart` (new): `ViewerLauncher`, which ties `ViewerServer` and `Browser`.
  - `app/lib/src/platform/services.dart`: add `browser` and `viewer` (or the launcher; follow the existing pattern).
  - `app/lib/main.dart` (line 24): build them; close the server on quit.
  - `app/lib/src/ui/home_page.dart`: `_characters`.
  - `app/lib/src/shell/shell_controller.dart`: `TrayLabels`, `_trayItems`, `quit`.
  - `app/lib/l10n/app_{en,de,fr,es,it,pt}.arb` and the generated `app_localizations*.dart`.
  - `app/test/support/fakes.dart`, `app/test/home_test.dart`, `app/test/shell_controller_test.dart`,
    `app/test/l10n_test.dart` (inspect).
  - `docs/app.md`, `docs/app-manual-checklist.md`.
- **Implementation:**
  - `abstract interface class Browser { Future<bool> open(Uri url); }`. `SystemBrowser` calls
    `launchUrl(url, mode: LaunchMode.externalApplication)` and returns false on `false` or an exception. Read the
    `url_launcher` README and changelog at the resolved version for the desktop behavior.
  - `ViewerLauncher.open(String id, String lang)`: `await server.start()`, then `browser.open(server.pageUrl(id, lang))`.
    It returns a result: `opened`, `serverFailed`, or `browserFailed(Uri url)`.
  - The language: `effectiveLocale(settings.language, systemLocales).languageCode` (`app/lib/src/l10n/app_locale.dart:46`).
  - Overview: each `ListTile` in `_characters` gets a trailing `TextButton` "View" (`l.viewCharacter`) with a
    tooltip and a semantic label "View <name>". On `serverFailed`, a SnackBar shows `l.viewerStartFailed`. On
    `browserFailed`, a SnackBar shows `l.viewerOpenFailed` with an action "Copy link" that calls
    `services.copyText(url)`.
  - Tray: a new `TrayItem(labels.viewJourney, ...)` after Gather now. It takes `gather.snapshot.defaultCharacter` when
    it is in `snapshot.characters`, else the first character. With no character, it calls `openWindow()`. On a
    failure, it calls `openWindow()` so the player sees the Overview. `quit` closes the viewer server.
  - New texts in the 6 `.arb` files, with descriptions in `app_en.arb`: `viewCharacter` ("View"),
    `viewCharacterLabel` ("View {name}"), `trayViewJourney` ("View journey"), `viewerStartFailed` ("Could not start
    the journey viewer."), `viewerOpenFailed` ("Could not open the browser. Copy the link and open it yourself."),
    and reuse the existing `copyLinkLabel` ("Copy link", `app_en.arb:680`) for the SnackBar action. Write real translations, in the
    style of the existing catalogs.
  - `docs/app.md`: the Overview bullet names the View button; the Tray bullet names View journey; a new bullet "Local
    viewer" says: the app serves the page on `127.0.0.1` with a port that the system picks, from `latest/`, while the
    app runs; other programs on the same computer can read it; the page needs internet only for the Wowhead gear
    names; reload the page after a gather; the map art is Blizzard's (link `web/map/README.md`).
  - `docs/app-manual-checklist.md`: rows for: View opens the browser on Linux, macOS and Windows; the map art shows;
    a screenshot opens in the lightbox; the language follows the app setting and the footer picker changes it; View
    journey in the tray opens the default character; with no character, View journey shows the window; with no
    default browser (Linux: `BROWSER=` and no `xdg-open`), the message and Copy link show; after a gather, a reload
    shows the new data; after Quit, the URL does not answer.
- **Edge cases:** View while a gather runs (the page shows the files of the last finished gather); View after the
  backup folder changed (the server reads the new `latest/`); two quick clicks (one server, two tabs); a character
  removed from `index.json` after the Overview shows it (the page shows 404); the tray item when the window is hidden
  (the window stays hidden on success); a system language that the app does not support (English).
- **Tests:**
  - `app/test/home_test.dart` (widget): each character row has a View button; a tap calls the fake launcher with the
    id and the app language; `serverFailed` shows `viewerStartFailed`; `browserFailed` shows `viewerOpenFailed`, and
    Copy link puts the URL on the fake clipboard.
  - `app/test/shell_controller_test.dart` (unit): the tray has View journey after Gather now; it opens
    `defaultCharacter`; the first character when the default is missing; the window when there is no character or the
    open fails; `quit` closes the server.
  - `app/test/viewer_launcher_test.dart` (unit, new): with a fake `Browser` and a real `ViewerServer`, `open` returns
    `opened` and the fake got `http://127.0.0.1:<port>/<id>/?lang=<code>`; a browser `false` gives `browserFailed`.
  - `app/test/l10n_test.dart`: the new keys exist in all 6 catalogs (follow the existing test).
  - Manual: the new rows of `docs/app-manual-checklist.md`, on Linux at least.
- **Verify:**
  - `make app-lint app-test`.
  - `make companion`, then click View on a character: the browser opens the page with the map art (manual).
- **Definition of done:**
  - [ ] Each Covers item is observably met, including one observation that failed before the task (before: the
        Overview row has no View button).
  - [ ] Tests listed above exist and follow the Tests guidelines.
  - [ ] Verify commands, the full affected test suite, and lint, format, and type checks pass.
  - [ ] E2E tests pass, or the accepted alternative from Risks is done (the manual rows).
  - [ ] All three reviews pass with no valid open findings.
  - [ ] Docs and config that describe the changed behavior are updated.
  - [ ] Task heading checkbox ticked; changes committed (`feat: open the character page from the app in the browser`).

## Validation

Run after the last task:

1. `make lint test` passes.
2. `make app-viewer-check` passes on a fresh clone after `make app-viewer`.
3. CI passes on Linux, macOS and Windows (job `app`), and `release.yml` on a pre-release tag makes the 3 app archives.
4. Unpack the Linux archive. Start the app with a backup folder that has `latest/`. Click View on each character:
   Summary, Journey map (with the map art and screenshots) and Heatmaps work.
5. From another terminal: `curl -s -o /dev/null -w '%{http_code}' -H 'Host: evil.example' http://127.0.0.1:<port>/<id>/`
   prints `404`; without the header it prints `200`.
6. `docker build -f server/Dockerfile .` and a character page on `make local-up` show the map art.
7. Every row of `docs/app-manual-checklist.md` that this spec adds is run and marked.

## References

- OpenMap (ships Blizzard map art in the addon, MIT code, art © Blizzard): https://www.curseforge.com/wow/addons/openmap,
  https://www.curseforge.com/wow/addons/openmap-classic
- Blizzard legal FAQ: https://blizzard.com/legal/28d5ebbf-c245-4408-8ba9-043dd5f056bf/faq-prawny
- Blizzard UI Add-On Development Policy: https://us.forums.blizzard.com/en/wow/t/ui-add-on-development-policy/24534
- Flutter desktop WebView status (why no WebView): https://pub.dev/packages/flutter_inappwebview_linux/score,
  https://pub.dev/packages/webview_win_floating, https://pub.dev/packages/desktop_webview_window
- `url_launcher`: https://pub.dev/packages/url_launcher
- `dart:io` `HttpServer`: https://api.dart.dev/stable/dart-io/HttpServer-class.html
- Flutter assets (folders are not recursive): https://docs.flutter.dev/ui/assets/assets-and-images
- DNS rebinding and the Host check: https://en.wikipedia.org/wiki/DNS_rebinding
- Map art build: `~/Code/muddyboots-web/tools/build_map.py`, `build_layers.py`, `README.md`
- Earlier specs: `specs/2026-11-08-companion-app.md`, `specs/done/2026-11-09-character-page-redesign.md`,
  `specs/done/2026-11-09-app-theme.md`

## Open Decisions

None.

## Completion

When every task is checked and Validation passes, move this file to `specs/done/` with `git mv` (plain `mv` when the
file is untracked). Create `specs/done/` if it does not exist. Commit the move.
