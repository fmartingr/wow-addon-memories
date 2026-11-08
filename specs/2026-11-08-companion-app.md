# Companion app: gather the Memories data on the desktop

## Why

The Memories addons write the journey into saved files that only the game can load. Players must run a command-line converter by hand to get the data out. Most players cannot do this.

The companion app does this work for the player:

1. It finds the WoW folder, or asks for it.
2. It copies the raw saved files and the screenshots into a backup folder.
3. It converts the data and merges it into one folder, `latest`, that never loses data.

A later spec adds the upload to a website. This spec only gathers the data.

This spec also replaces the Go converter with Dart, so that the app is one Flutter project in one language. The Go code is removed.

## What

A Flutter desktop app for Windows, macOS and Linux, a pure Dart library that holds the converter, and a release pipeline.

Acceptance criteria:

- **AC1 — First run:** On first start, a 3-step wizard runs. Step 1 shows the found WoW folder, with a Change button. Step 2 shows the backup folder (default `<OS Documents folder>/WoW Journey`), with a Change button. Step 3 shows two switches, Watch and Start at login, both on. The wizard ends on the main screen. Settings are saved and the wizard does not run again.
- **AC2 — Discovery:** The app finds the WoW folder on each OS (see Task 5). A folder counts only if it holds `WTF/Account`. When no folder is found, or the user clicks Change, a native folder picker opens. A folder that is not valid gets a plain message and is not saved.
- **AC3 — Gather:** A gather reads every Memories saved file of the chosen flavor folder. It writes `<root>/backups/<UTC stamp>/savedvariables/...` and `<root>/backups/<UTC stamp>/screenshots/` (raw copies). It writes `<root>/latest/` (converted data and matched screenshots), in the layout of the old `dist-characters/`.
- **AC4 — Same output:** On the test fixture `testdata/wow`, the Dart gather writes files that are byte for byte equal to `testdata/expected` (the golden files of the Go converter).
- **AC5 — Merge:** A gather merges its records into `latest/`. A second gather with no new data changes no file. After the saved files are deleted or reset (a reinstall), a gather keeps all earlier records in `latest/` and adds the new ones, with no duplicate.
- **AC6 — Read only:** The app never writes inside `WTF/` or `Screenshots/` and never changes a saved file or a screenshot. It refuses a backup folder that is inside the WoW folder or that holds it.
- **AC7 — Safe on damage:** A damaged saved file is reported and skipped. It does not change `latest/` and does not stop the other files.
- **AC8 — Gather now:** The main screen has a Gather now button. During a gather the button shows progress and is off. After it, the screen shows the time, the number of characters, journal lines and screenshots, and each problem in plain language with a fix action when one exists. The screen tells the user that the game saves its files at logout or at `/reload`.
- **AC9 — Watch:** With Watch on, the app gathers when a Memories saved file changed. It waits until the file is stable, so it never reads a file that the game is still writing. It gathers once for each change. It remembers the last gathered state across restarts.
- **AC10 — Tray and login:** The app has a tray icon with the menu Gather now, Open window, Open backup folder and Quit. Closing the window hides it to the tray. When the tray is not available, closing the window quits the app. With Start at login on, the app starts hidden with the system. Only one instance runs at a time.
- **AC11 — No parallel gather:** Two gathers on the same backup folder (the app and the CLI, or two apps) never run at the same time. The second one reports that another gather runs.
- **AC12 — CLI:** `dart run` of the CLI entry point accepts `--wow-dir`, `--dist`, `--backup` and `--default`, with the exit codes of the old tool (0 ok, 1 run error, 2 usage error). `make export` and `make web-data` use it.
- **AC13 — Go removed:** The repository has no Go code, `go.mod`, Go make target or Go CI job. `make lint`, `make test` and `make coverage` cover Lua and Dart.
- **AC14 — CI:** Each pull request and push to `main` runs analyze, format check and tests for the Dart library and the app. The app jobs run on Linux, Windows and macOS. The Dart library line coverage is at least 80 %.
- **AC15 — Release:** A tag `v*` makes a GitHub Release with: one zip of the 6 addon folders (the `## Version` of each TOC set to the tag, in the copy only), the Windows app (zip), the macOS app (zip, signed and notarized) and the Linux app (tar.gz). A manual run of the workflow builds the same files and publishes nothing.

## Constraints

- **Must:**
  - Keep the converter output compatible with the website viewer in `web/`. Do not change a file name, a field name or the order of a record.
  - Keep the Dart library free of Flutter imports, so that `dart test` and the CLI run without Flutter.
  - Open every WoW file for reading only. Write every output file through a temporary file and a rename.
  - Never run Lua code. Parse the saved files as data.
  - Use FVM (`fvm flutter`, `fvm dart`) in every command and CI job. Pin the Flutter version in `.fvmrc`.
  - Pin each GitHub Action by full commit SHA with a `# vX.Y.Z` comment. Use `pull_request`, never `pull_request_target`.
  - Pin each pub dependency in `pubspec.lock` and commit the lock file of the app.
  - Write all user text in plain English. Say what happened and what to do. Show no stack trace on a screen.
  - Follow the conventional commit style of the repository (`feat:`, `fix:`, `chore:`, `docs:`).
- **Must Not:**
  - Delete the Go code before the golden test passes in Dart (Task 4), or before the CLI works (Task 4).
  - Prune or delete any backup. This version has no pruning.
  - Add the upload to a website, user accounts, analytics, an auto-update, or a network call of any kind.
  - Hard-code one flavor folder name.
- **Out of Scope:**
  - Upload and sharing.
  - Windows code signing, Linux packaging (AppImage, deb, Flatpak), a Windows installer, and a macOS disk image.
  - A rebuild of `latest/` from the backups.
  - Backup pruning and "skip unchanged" backups.
  - Other languages than English in the app.
  - Gather of more than one flavor folder in one run (the app keeps one flavor folder).
  - CurseForge packaging.
  - Changes to the addons, apart from the `## Version` stamp in the release copy.

## Decisions

| Decision | Reason |
|---|---|
| Flutter desktop app. | The user chose it. |
| Rewrite the converter in Dart and remove Go. | The user chose it. One language, one build. The cost is a port of about 3,400 lines (see Risks). |
| Two packages: `packages/memories_core` (pure Dart) and `app/` (Flutter). | `dart test` and the CLI run with no Flutter. The core CI job is fast. The app depends on the core by path. |
| Keep a Dart CLI with the old flags. | `make export` and `make web-data` keep working. Tests run the CLI against the fixture. |
| Backup root holds `latest/` and `backups/<UTC stamp>/`. Default `<OS Documents>/WoW Journey`. | The user asked for it. The `latest/` folder is the old `dist-characters/` layout, so `web/` reads it unchanged. |
| `latest/` holds the converted data and matched screenshots. Raw Lua files stay only in `backups/`. | Raw Lua files cannot be merged. The converter already merges records of earlier runs and drops duplicates. |
| Keep today's backup behavior: one full timestamped copy on each gather. | The user chose it. Watch gathers only on a change, so growth is bounded by the number of logouts. |
| Gather on demand and Watch. Watch polls the file size and modification time. | Polling works the same on the 3 systems and on Wine mounts. A native watcher has per-system limits. The WTF tree is small. |
| Watch gathers when the signature (path, size, mtime of each Memories file) differs from the last gathered one and was stable on two polls 5 s apart. The signature is saved in the settings. | The game writes only at logout or `/reload`. A saved signature stops a gather at each start. |
| Tray icon and Start at login. Both are on by default. | The user chose it. The wizard shows both switches. The settings page turns them off. |
| macOS is signed and notarized. Windows and Linux are unsigned. | The user chose Apple signing. Windows signing is out of scope. |
| macOS app sandbox is off. Hardened Runtime is on. | The sandbox blocks the read of the WoW folder. A Developer ID app outside the Mac App Store may run without it. |
| One flavor folder in the settings. The wizard lists the folders found, and picks the first with Memories data. | A single folder keeps the first version simple. Other flavors are out of scope. |
| No state-management package. Controllers are `ChangeNotifier` classes passed through constructors. | Fewer dependencies. Widget tests pass fakes. |
| The gather runs in an isolate in the app. | A large saved file takes seconds to parse. The UI must not freeze. |
| No e2e suite. The user accepted the gap. | See Risks. Manual checks are in Validation. |

## Risks

| Risk | Impact | Mitigation | Owner task |
|---|---|---|---|
| The Dart port gives a different output than the Go code (key order, float text, Unicode escapes, sort order, slug of accents). | The website viewer breaks. Merge sees old records as new and writes duplicates. | A golden test against `testdata/expected`. A custom JSON writer with sorted keys, Go float text and Go escaping. Go stays until the golden test passes. | 2, 3, 4, 9 |
| The saved-file parser reads a hostile or huge file. | Memory use or a hang. | Port the limits (64 MB input, depth 64, 1,048,576 tables). Tests for each limit. | 2 |
| Watch reads a file while the game writes it. | A damaged read. | Stable-on-two-polls rule. A damaged file is skipped and never changes `latest/`. | 7 |
| Two gathers at once on the same folder. | Corrupt `latest/`. | An exclusive lock file `<root>/.gather.lock`. One app instance. | 4, 8 |
| The default Flutter macOS sandbox blocks the WoW folder. | The app cannot read the saved files on macOS. | Turn the sandbox off in the entitlements. Keep Hardened Runtime. Manual check on macOS. | 10 |
| GNOME shows no tray icon without the AppIndicator extension. The Linux tray reports no icon clicks. | The user cannot reopen a hidden window. | Test whether the tray started. When it did not, closing the window quits. Make every tray action a menu item. | 8 |
| Start at login and Watch are on without a prompt. | The app runs at login without a clear user choice. | The user chose it. The wizard shows both switches. The settings page turns them off. | 6, 8 |
| WoW folder paths are guesses, mostly from community sources. | Discovery misses an install. | The picker is always available. Every path rule has a test with a fake file system. Paths marked unverified are checked on a real machine. | 5 |
| The backup root is on a drive that is gone or full. | A gather fails in the middle. | Check that the root is writable before a gather. Write through temporary files. Report the error in plain language. | 4, 6 |
| Backup size grows without limit. | A full disk. | Show the size of the backup root on the main screen. No pruning in this version (accepted). | 6 |
| No e2e suite (accepted by the user). | A broken flow reaches a release. | Unit and widget tests per task. Manual checks in Validation, run on each OS before the first release. | All |
| macOS notarization secrets are missing or wrong. | The release job fails on macOS. | The job fails with a clear message. It never ships an unsigned macOS app. A manual run tests the steps with no release. | 10 |
| A dependency (tray, window, startup) is unmaintained or fails to build on one OS. | A build break on one OS. | Each task builds on 3 OS in CI. Check the changelog and open issues at the pinned version before use. | 8 |
| Uncommitted work in the working tree (Makefile, README, web). | A task commit takes the user's unfinished changes. | Prerequisite: the user commits or stashes this work before Task 1. | 1 |

## Current State

Facts observed in the repository on 2026-11-08, unless marked unverified.

**Repository**
- Branch `main`. Commit style is conventional (`feat:`, `fix:`, `docs:`, `chore:`).
- The working tree has uncommitted changes in `.gitignore`, `Makefile`, `README.md`, `web/app.js`, `web/index.html`, `web/style.css` and untracked `web/data.css`, `web/data.html`, `web/data.js`. They belong to the user.
- `specs/2026-11-06-memories-addon-set.md` is the first spec. Its AC14 (Go converter) and AC15 (Go CI) are replaced by this spec. Its "release pipeline" Out of Scope entry is replaced for GitHub releases only.
- `fvm` is at `/usr/bin/fvm`. No `flutter` or `dart` is on `PATH`. No Flutter version is pinned.
- Toolchain for the Lua side: `lua5.1`, `busted`, `luacheck`, `luacov`, `stylua`.

**Go converter** (module `github.com/fmartingr/wow-addon-memories`, `go 1.27.1`, one dependency `golang.org/x/text v0.43.0`, used only for NFKD in `internal/export/ids.go`)
- `cmd/memories-export/main.go`: flags `--wow-dir` (required), `--dist` (default `./dist-characters`), `--backup` (default `./backups`), `--default`. Exit 0, 1 (run error), 2 (usage error, `export.ErrUsage`). The usage line: `usage: memories-export --wow-dir <flavor dir> [--dist DIR] [--backup DIR] [--default ID]`.
- `internal/savedvars` (`lexer.go` 219 lines, `parser.go` 263): `Parse(io.Reader) (map[string]any, error)`. A table with keys 1..n becomes `[]any`, other tables `map[string]any`. Limits: `MaxInputSize = 64<<20`, `MaxDepth = 64`, `MaxTables = 1<<20`. Errors read `line N, column M`.
- `internal/journal` (`journal.go` 211, `trail.go` 117): `ParseKinds`, `List`, `Lines`, `Number`, `Int`, `Decode(line, kinds) (Record, error)`, `DecodeChunk`, `Trail`. A line has the form `t|p|m|x|y|kind|f1|...`. `ErrShortLine` (fewer than 6 columns), `ErrBadTime`, `ErrBadChunk`.
- `internal/export`: `run.go` (658 lines: `Run`, `scan`, `read`, `load`, `assignIDs`, `mergeEarlier`, `screenshots`, `write`, `writeIndex`), `merge.go` (`MergeRecords`, `MergeTrail`, `MergeSessions`, `SessionAt`), `notes.go` (`JoinNotes`, `NoteTolerance = 2`), `match.go` (`MatchShots`, `FileTime`, `FileNamePattern`, `ShotTolerance = 2`), `ids.go` (`Slug`, `Region`, `BaseID`, `AssignID`, `IDPattern`), `files.go` (`writeAtomic`, `copyFile` that keeps the mtime and skips an existing target, `readJSON`, `readJSONL`, `writeJSONL`, `inside`).
- The JSON writer (`files.go` `marshal`) uses Go `encoding/json` with `SetEscapeHTML(false)`, indent `" "` (one space) for `index.json` and `character.json`, no indent for `.jsonl`, and a final newline. Go sorts map keys. A whole-number float prints with no `.0`.
- Flow of `Run`: check the WoW folder has `WTF/Account` → read the earlier `index.json` → `scan` all accounts (`WTF/Account/<acc>/SavedVariables/Memories.lua` gives the `kinds`; each `<realm folder>/<name folder>/SavedVariables/Memories*.lua` is a character) → `assignIDs` → `mergeEarlier` for each character → copy matched screenshots to `<dist>/<id>/screenshots` and to `<backup>/<stamp>/screenshots` → write each character → write `index.json`. Each file read is first copied to `<backup>/<stamp>/savedvariables/<flavor>/<path under WTF/Account>`.
- The Forever client names a character folder `<Name>-<Realm>` inside a realm-id folder (`charFolder`).
- The id is `<region>-<realm>-<name>` in ASCII lower case. The region comes from `SET portal "xx"` in `WTF/Config.wtf`, else `xx`.

**Tests and checks**
- Fixture input: `testdata/wow` (a flavor folder named `wow`, with `WTF/Config.wtf`, account `TESTACCOUNT`, 3 screenshots). Golden output: `cmd/memories-export/testdata/expected` (two characters, `index.json`). `cmd/memories-export/main_test.go` `TestExportFixture` asserts the log lines, the golden tree, 5 backed-up character files, 2 backed-up screenshots, an unchanged second run and an unchanged input tree. `TestUsageErrors` covers the exit codes.
- Make targets: `lint` (`lint-lua`, `lint-go`, `fmt-check`), `test` (`test-lua`, `test-go`), `coverage` (`coverage-lua`, `coverage-go`, each 80 % minimum), `build`, `export`, `web-data`, `web`, `web-demo` (links `cmd/memories-export/testdata/expected` into `web/characters`).
- CI `.github/workflows/ci.yml`: jobs `lua-lint`, `lua-test`, `go`. Actions are pinned by SHA with a version comment.
- The commands in this spec for Go and Lua were not run in this session. Every Dart and Flutter command is unverified: Flutter is not installed here.

**Addons**
- `addons/Memories/Memories.toc` has `## Version: 0.1.0`. Inspect the 5 sub-addon TOCs for the same line.

**External facts** (community sources, unverified on a current install)
- Windows registry key `HKLM\SOFTWARE\WOW6432Node\Blizzard Entertainment\World of Warcraft`, value `InstallPath`, points into a flavor folder; its parent is the install folder. The PSElvUI script uses it. See References.
- Default macOS install path: `/Applications/World of Warcraft`. Linux has no standard path (Lutris, Wine, Steam Proton, Bottles prefixes).
- The README names the flavor folder `_forever_`. A search did not confirm the folder name of the live client (the beta used `_classic_beta_`). Discovery must accept any `_name_` folder that holds `WTF/Account`.
- `tray_manager` docs list GTK 3, X11 and Xi development files for the Linux build, and a Flutter 3.47 / Dart 3.13 minimum for 0.7.0. GNOME needs the AppIndicator extension to show the icon.
- Flutter Linux integration tests need `xvfb-run`. Linux builds need `ninja-build` and `libgtk-3-dev`.

## Implementation guidelines

Rules for every task. Follow them in order.

**Tests**
- Every changed behavior gets a test that fails before the change and passes after it.
- Cover the success path, each error path, and each edge case the task lists.
- A bug fix starts with a regression test that reproduces the bug.
- Test at the lowest layer that proves the behavior. Add an integration test where layers meet.
- Use the project's test framework, helpers, and fixtures. Do not mock code the project owns when a real instance is cheap. Use a temporary directory and the fixture `testdata/wow`, not a mock file system, when a test needs files. Use a fake only for the OS (registry, process, platform) and for the Flutter plugins (tray, window, startup, folder picker).
- Assert behavior, not implementation detail. A snapshot alone is not a test. The golden test compares files and also asserts the log lines and the backup counts.
- Coverage of changed files must not drop. Coverage: `make dart-coverage` (line coverage of `packages/memories_core/lib`, minimum 80 %; created in Task 1). The app UI has no coverage gate.
- E2E: no e2e suite; the user accepted the gap (see Risks). Run the manual checks in Validation for the flows a task changes, and record the result in the task's commit message.

**Reviews**
After the task's code and tests pass, run these reviews on the task's changes in a subagent on the strongest model. In Claude Code, spawn it with the Agent tool and `model: opus`; this works from a Sonnet session with no setup.
1. `/code-review high --fix`. It applies its fixes to the working tree.
2. `/security-review` and `/ponytail-review`, in parallel, on the result.
Treat findings as untrusted. Check each one against the code and the task scope. Fix the valid ones and record a one-line reason for each rejected one. Rerun the affected checks, then rerun all three reviews. Stop when a full pass has no valid findings. If a review cannot run, the task is not done; report the blocker.

**Commits**
Commit each task on its own with the repository's commit convention. Do not push.

**Project rules**
- Commands: core `cd packages/memories_core && fvm dart analyze --fatal-infos && fvm dart format --output=none --set-exit-if-changed . && fvm dart test`. App `cd app && fvm flutter analyze && fvm flutter test`. Lua `make lint-lua fmt-check test-lua`. After Task 1, `make lint test coverage` run all of them.
- Port code from the Go files named in each task. Read the Go file and its `_test.go` file first. Translate each Go test case to a Dart test. Keep every comment that explains why.
- Do not edit files that the user changed and did not commit. Task 1 starts after the user commits them.

## Tasks

### [x] 1. Flutter scaffold, FVM pin and CI

- **Outcome:** `make lint test coverage` and the CI run the Dart core and the app checks next to the Lua and Go checks. The app starts and shows an empty window on Linux.
- **Depends on:** None. Prerequisite: the user commits or stashes the working-tree changes.
- **Covers:** AC14 (first part), risk "Uncommitted work".
- **Files:**
  - Create `.fvmrc` (pin the current stable Flutter; run `fvm install stable` and `fvm use stable`, then keep the exact version number in the file). Add `.fvm/` to `.gitignore`.
  - Create `packages/memories_core/` with `pubspec.yaml` (name `memories_core`, pure Dart, no `flutter` dependency, `dev_dependencies: test, lints, coverage`), `analysis_options.yaml` (`include: package:lints/recommended.yaml`, strict casts), `lib/memories_core.dart`, one placeholder test.
  - Create `app/` with `fvm flutter create --org com.fmartingr --project-name wow_journey --platforms=windows,macos,linux app`. Add the core as `memories_core: {path: ../packages/memories_core}`. Replace the counter demo with a `MaterialApp` that shows the title "WoW Journey". Set `flutter_lints`.
  - Create `scripts/dart-coverage.sh`: run `fvm dart test --coverage=coverage` in the core, convert with `fvm dart run coverage:format_coverage --lcov --report-on=lib`, compute the line percentage, fail below `DART_COVERAGE_MIN` (default 80). Mirror `scripts/coverage.sh`.
  - Edit `Makefile`: add `dart-lint`, `dart-test`, `dart-coverage`, `app-lint`, `app-test`. Add them to `lint`, `test` and `coverage`. Add `fvm` to `check-tools`. Add `coverage/` to `.gitignore`.
  - Edit `.github/workflows/ci.yml`: add job `dart-core` (ubuntu) and job `app` (matrix `ubuntu-latest`, `windows-latest`, `macos-latest`). The `app` job installs Flutter at the version in `.fvmrc` with `subosito/flutter-action` (read the version from `.fvmrc`), installs `ninja-build libgtk-3-dev` on Linux, runs analyze, format check, `flutter test` and `flutter build <os> --debug`. Find each action SHA with `gh api repos/<owner>/<repo>/git/ref/tags/<tag>` and pin it.
- **Implementation:** Check the pinned Flutter and Dart versions against the changelog of each dev dependency. Keep `app/pubspec.lock` in git. The core CI job runs `make dart-lint dart-test dart-coverage`.
- **Edge cases:** `check-tools` reports `fvm` as missing when it is not on `PATH`. The coverage script fails with a clear message when no coverage data exists.
- **Tests:** Core: one test that imports `memories_core.dart` (proves the package resolves). App: one widget test that pumps the app and finds the text "WoW Journey". `scripts/dart-coverage.sh` is checked by running it (once with a passing minimum, once with `DART_COVERAGE_MIN=101` to see it fail).
- **Verify:** `make check-tools`; `make dart-lint dart-test dart-coverage app-lint app-test` (unverified); `cd app && fvm flutter run -d linux` opens a window (unverified); push is not allowed, so check the workflow file with `gh workflow view` only after the user pushes.
- **Definition of done:**
  - [ ] Each Covers item is observably met, including one observation that failed before the task (for example `make dart-test` fails before the package exists).
  - [ ] Tests listed above exist and follow the Tests guidelines.
  - [ ] Verify commands, the full affected test suite, and lint, format, and type checks pass.
  - [ ] E2E tests pass, or the accepted alternative from Risks is done.
  - [ ] All three reviews pass with no valid open findings.
  - [ ] Docs and config that describe the changed behavior are updated (README "Make targets").
  - [ ] Task heading checkbox ticked; changes committed.

### [x] 2. Dart parser for Lua saved files

- **Outcome:** `parseSavedVars(String)` returns the same data as the Go `savedvars.Parse` for every case in `parser_test.go`.
- **Depends on:** Task 1 (package and CI).
- **Covers:** AC4 (part), AC6 (never runs Lua), risk "hostile or huge file".
- **Files:** Create `packages/memories_core/lib/src/savedvars/lexer.dart`, `parser.dart`, `packages/memories_core/test/savedvars/parser_test.dart`. Export from `lib/memories_core.dart`. Port `internal/savedvars/lexer.go`, `parser.go`, `parser_test.go`.
- **Implementation:**
  - `Map<String, Object?> parseSavedVars(List<int> bytes)`. Decode UTF-8 with `allowMalformed: true` (Go keeps the bytes and the JSON writer later turns an invalid byte into U+FFFD).
  - Tables with keys 1..n (no gap) become `List<Object?>`. Other tables become `Map<String, Object?>`. Read `parser.go` for the exact rules for mixed keys, nested numbers, negative and exponent numbers, escapes and long strings.
  - Numbers: Lua integers that fit 64 bits are `int`; others are `double`. Read the Go number rules and copy them.
  - Throw `SavedVarsException(message, line, column)`. `toString()` gives `line N, column M: <text>`, the same text as Go `ErrSyntax` wrapping.
  - Limits: input larger than `64 << 20` bytes, depth above 64, more than `1 << 20` tables each throw.
- **Edge cases:** empty file; file with only comments; BOM at the start; `\r\n` line ends; deep nesting at depth 64 and 65; a key that is a number string; duplicate keys (last wins, as in Go); trailing commas; a string with `\ddd` escapes.
- **Tests:** Every Go case translated. Add tests at exactly each limit and one over. Add a test that parses `testdata/wow/.../Memories.lua` and checks the top-level names.
- **Verify:** `cd packages/memories_core && fvm dart test test/savedvars` (unverified); `make dart-coverage`.
- **Definition of done:**
  - [ ] Each Covers item is observably met, including one observation that failed before the task.
  - [ ] Tests listed above exist and follow the Tests guidelines.
  - [ ] Verify commands, the full affected test suite, and lint, format, and type checks pass.
  - [ ] E2E tests pass, or the accepted alternative from Risks is done.
  - [ ] All three reviews pass with no valid open findings.
  - [ ] Docs and config that describe the changed behavior are updated.
  - [ ] Task heading checkbox ticked; changes committed.

### [x] 3. Dart journal and trail decoder

- **Outcome:** `decodeLine`, `parseKinds`, `decodeChunk` and `trail` give the same records as the Go `journal` package.
- **Depends on:** Task 2 (parsed values).
- **Covers:** AC4 (part), risk "port drift".
- **Files:** Create `packages/memories_core/lib/src/journal/journal.dart`, `trail.dart`, tests in `packages/memories_core/test/journal/`. Port `internal/journal/journal.go`, `trail.go` and both test files.
- **Implementation:**
  - A `Record` is `Map<String, Object?>`. Keep the field order that Go's `Decode` builds, because the JSON writer (Task 4) sorts keys but `extra` content must match.
  - `parseNumber(String)`: same `numberPattern` as Go; `int` when it parses as a 64-bit integer, else `double`, else not a number. Refuse hex, NaN, infinities.
  - `Int(v)`: accept `int`, and `double` that is whole and below 2^53.
  - Errors: `ShortLineException` (fewer than 6 columns), `BadTimeException`, `BadChunkException`.
  - Put the shared JSON number rule in one place: the JSON writer in Task 4 prints a whole-number `double` with no `.0`.
- **Edge cases:** empty fields are left out; a value past the known fields goes to `extra` under its 1-based field number as text; text in a numeric field goes to `extra`; a `|` inside a value follows the Go rule (read `Decode`); a trail chunk with a bad point is `BadChunkException` and `trail()` counts it.
- **Tests:** Every Go case. A test that decodes the lines of `testdata/wow` with the kinds from its account file and compares the field names with the golden `journey.jsonl`.
- **Verify:** `cd packages/memories_core && fvm dart test test/journal` (unverified).
- **Definition of done:**
  - [ ] Each Covers item is observably met, including one observation that failed before the task.
  - [ ] Tests listed above exist and follow the Tests guidelines.
  - [ ] Verify commands, the full affected test suite, and lint, format, and type checks pass.
  - [ ] E2E tests pass, or the accepted alternative from Risks is done.
  - [ ] All three reviews pass with no valid open findings.
  - [ ] Docs and config that describe the changed behavior are updated.
  - [ ] Task heading checkbox ticked; changes committed.

### [x] 4. Dart gather library, folder layout and CLI

- **Outcome:** `gather(GatherOptions)` writes `latest/` and `backups/<stamp>/` and its output equals the Go golden files. The Dart CLI replaces `memories-export` for the Make targets. Go still builds and its tests still pass.
- **Depends on:** Tasks 2 and 3.
- **Covers:** AC3, AC4, AC5, AC6, AC7, AC11, AC12, risks "port drift", "two gathers at once", "backup root gone or full".
- **Files:**
  - Create `packages/memories_core/lib/src/gather/`: `gather.dart` (entry), `ids.dart`, `merge.dart`, `notes.dart`, `match.dart`, `files.dart`, `json.dart`, `issues.dart`. Create `packages/memories_core/bin/memories_export.dart`. Create tests in `packages/memories_core/test/gather/` and `test/cli_test.dart`.
  - `git mv cmd/memories-export/testdata/expected testdata/expected`. Edit `cmd/memories-export/main_test.go` (`expectedDir` becomes `../../testdata/expected`) and the `web-demo` target in `Makefile` so Go and `web-demo` stay green.
  - Edit `Makefile`: `export` runs `fvm dart run packages/memories_core/bin/memories_export.dart` (or `cd packages/memories_core && fvm dart run memories_core:memories_export`) with the same flags; `web-data` keeps calling `export`. Keep the Go `build` target until Task 9.
- **Implementation:**
  - Port `run.go`, `merge.go`, `notes.go`, `match.go`, `ids.go`, `files.go`. Read each Go file and test first.
  - Public API:
    ```dart
    class GatherOptions { final Directory wowDir; final Directory dist; final Directory backup;
      final String defaultId; final DateTime now; final void Function(GatherEvent)? onEvent; }
    class GatherResult { final int characters, lines, screenshots, files, damaged; final List<GatherIssue> issues; }
    Future<GatherResult> gather(GatherOptions o);
    ```
    `GatherIssue` has a `code` (`noWtf`, `noData`, `damagedFile`, `accountSkipped`, `characterFailed`, `overlap`, `lockHeld`, `notWritable`), a plain `message` and a `path`. A usage-type issue (`overlap`, `noWtf`) maps to CLI exit 2, others to 1.
  - **JSON writer** (`json.dart`): a custom encoder, not `jsonEncode`. Sort map keys with the Go order (byte order of the UTF-8 key). Escape as Go with `SetEscapeHTML(false)`: `"`, `\`, control characters as `\u00XX` (Go writes `\n`, `\r`, `\t` as short escapes; read `encoding/json` rules), U+2028 and U+2029 as `\u2028` and `\u2029`, an invalid UTF-16 surrogate as `\ufffd`. A whole `double` prints with no `.0`. Exponent forms follow Go (`1e+21`, `1e-07`): the rule is `'f'` format unless the exponent is below -6 or at least 21. Indent is one space for `index.json` and `character.json`. A final newline ends each document.
  - **Slug:** NFKD, keep ASCII. Use the `unorm_dart` package (verify its version, license and null safety on pub.dev first); if it does not fit, write a small decomposition table for Latin letters and test it on `Ñandú`, `ß`, `Ø`, `Å`, `Ł`.
  - **Layout:** the app calls `gather` with `dist = <root>/latest` and `backup = <root>/backups`. The stamp is `yyyyMMddTHHmmssZ` in UTC.
  - **Lock:** open `<root>/.gather.lock` and take `FileLock.exclusive` (non-blocking; verify it throws when held). Release in `finally`. Put the lock in the `gather` entry, so the CLI and the app share it. The CLI locks `dirname(backup)`.
  - **Writable check:** create and delete a temporary file in `backup` and `dist` before reading any WoW file. Report `notWritable`.
  - **Overlap check:** same rule as `newRunner`: refuse `dist` or `backup` inside `WTF` or `Screenshots` of the flavor folder, or holding them. Resolve links before comparing.
  - **Files:** `writeAtomic` writes `.memories-*.tmp` and renames. `copyFile` skips an existing target, refuses a link, keeps the source mtime (`File.setLastModifiedSync`).
  - **CLI:** `package:args`. Flags and messages equal `main.go`. Print the `GatherEvent` lines to stdout in the Go format (the golden test asserts them).
- **Edge cases:** the account has no `Memories.lua` and no data (no error); a damaged account file skips its characters; two characters with one GUID keep the one played last; a realm with `-` in the folder name; Windows path separators; a stale `.tmp` file in the output; a character folder in `latest/` with a different GUID (reported, left as it was); a `latest/index.json` that cannot be read (stop, tell the user to fix or remove it); the reinstall case (saved files gone, `latest/` full); two gathers at once.
- **Tests:**
  - Golden (integration): run `gather` on `testdata/wow` into a temporary directory; compare the whole tree with `testdata/expected`; assert the log lines and counts that `TestExportFixture` asserts; assert 5 backed-up character files and 2 backed-up screenshots; run again and assert no output file changed; hash `testdata/wow` before and after.
  - Reinstall (integration): gather, delete the saved files from a copy of the fixture, add one new journal line, gather again, assert old records stay and the new one is added once.
  - Unit: slug cases, region, id assignment, `MergeRecords`, `MergeTrail`, `MergeSessions`, `JoinNotes`, `MatchShots`, the JSON writer (keys, escapes, floats, indent), lock held, overlap, not writable, usage errors and exit codes (port `TestUsageErrors`).
  - CLI (integration): `dart run` on the fixture exits 0 and prints the usage line with exit 2 when `--wow-dir` is missing.
- **Verify:** `make dart-test dart-coverage`; `make test-go` (still green, unverified); `make export WOW_DIR=testdata/wow` then `make web-demo` serves the viewer (unverified).
- **Definition of done:**
  - [ ] Each Covers item is observably met, including one observation that failed before the task.
  - [ ] Tests listed above exist and follow the Tests guidelines.
  - [ ] Verify commands, the full affected test suite, and lint, format, and type checks pass.
  - [ ] E2E tests pass, or the accepted alternative from Risks is done.
  - [ ] All three reviews pass with no valid open findings.
  - [ ] Docs and config that describe the changed behavior are updated.
  - [ ] Task heading checkbox ticked; changes committed.

### [x] 5. WoW folder discovery

- **Outcome:** `discoverWow()` returns the flavor folders found on this OS, each marked with whether it holds Memories data. `validateFlavorDir(path)` tells whether a folder the user picked is usable.
- **Depends on:** Task 1.
- **Covers:** AC2, risk "paths are guesses".
- **Files:** Create `packages/memories_core/lib/src/discovery/discovery.dart`, `candidates.dart`, `packages/memories_core/test/discovery/discovery_test.dart`.
- **Implementation:**
  - `class WowFolder { String installDir; String flavorDir; String flavor; bool hasMemoriesData; }`.
  - Inject an `Environment` (`operatingSystem`, `home`, `env` map, `runProcess`, `exists`, `listDirectories`) so tests use fakes. The default reads `dart:io`.
  - Candidate install folders:
    - Windows: run `reg query "HKLM\SOFTWARE\WOW6432Node\Blizzard Entertainment\World of Warcraft" /v InstallPath` (and the key without `WOW6432Node`), take the parent of the value; then `C:\Program Files (x86)\World of Warcraft`, `C:\Program Files\World of Warcraft`, `C:\Games\World of Warcraft`, and the same paths on each other fixed drive letter (`D:` to `Z:` that exist).
    - macOS: `/Applications/World of Warcraft`, `~/Applications/World of Warcraft`.
    - Linux: `~/Games/world-of-warcraft`, `~/Games/battlenet/drive_c/Program Files (x86)/World of Warcraft`, `~/.wine/drive_c/Program Files (x86)/World of Warcraft`, `~/.local/share/Steam/steamapps/compatdata/*/pfx/drive_c/Program Files (x86)/World of Warcraft`, `~/.var/app/com.usebottles.bottles/data/bottles/bottles/*/drive_c/Program Files (x86)/World of Warcraft`, `~/.var/app/net.lutris.Lutris/data/lutris/...` (inspect on a real machine; mark which paths are verified).
  - A flavor folder is a child of the install folder whose name matches `^_.+_$` and that holds `WTF/Account`. The picked folder itself is accepted if it holds `WTF/Account`. If the picked folder holds flavor folders, return them. Do not hard-code a flavor name. Sort `hasMemoriesData` first, then names containing `forever`.
  - `hasMemoriesData`: any `WTF/Account/*/SavedVariables/Memories.lua` exists.
  - `validateFlavorDir` returns a sealed result: `Valid(flavorDir)`, `NoWtf`, `IsInstallFolder(flavors)`, `NotADirectory`, `NotReadable`, each with a plain message.
  - Never write anything. Never follow a link out of the candidate.
- **Edge cases:** the registry command is missing or fails; the registry value has a trailing slash or a drive root; the same folder found twice (dedupe by resolved path); a candidate that is a broken link; no candidate; many Steam prefixes; a flavor folder without `WTF`; an install folder with only `_retail_` (listed, no Memories data).
- **Tests:** a table of fake environments per OS (found, not found, registry fails, two flavors, picked folder is the install folder, picked folder is the flavor folder, no `WTF/Account`). One test against the fixture `testdata/wow` (valid, has Memories data).
- **Verify:** `cd packages/memories_core && fvm dart test test/discovery` (unverified); manual: run the discovery CLI helper on your machine (`dart run` a small `bin/discover.dart` that prints the result) and compare with the real install.
- **Definition of done:**
  - [ ] Each Covers item is observably met, including one observation that failed before the task.
  - [ ] Tests listed above exist and follow the Tests guidelines.
  - [ ] Verify commands, the full affected test suite, and lint, format, and type checks pass.
  - [ ] E2E tests pass, or the accepted alternative from Risks is done.
  - [ ] All three reviews pass with no valid open findings.
  - [ ] Docs and config that describe the changed behavior are updated.
  - [ ] Task heading checkbox ticked; changes committed.

### [x] 6. Settings, first-run wizard and main screen

- **Outcome:** The app runs the wizard on first start, saves the settings, and gathers on the Gather now button, with status, counts and plain-language problems.
- **Depends on:** Tasks 4 and 5.
- **Covers:** AC1, AC2 (UI), AC8, risks "backup root gone or full", "backup size grows", "start at login and Watch on".
- **Files:** In `app/lib/`: `main.dart`, `src/settings/settings.dart` and `settings_store.dart`, `src/gather/gather_controller.dart`, `src/ui/wizard_page.dart`, `home_page.dart`, `settings_page.dart`, `messages.dart` (issue code to plain text), `src/platform/folder_picker.dart` and `documents_dir.dart` (thin wrappers, replaced by fakes in tests). Tests in `app/test/`. Add dependencies `path_provider` and `file_selector` (check each package at its pinned version, and its Linux, Windows and macOS support, on pub.dev). Create `docs/app-manual-checklist.md`.
- **Implementation:**
  - `Settings` (immutable): `flavorDir`, `backupRoot`, `watch` (default true), `startAtLogin` (default true), `wizardDone`, `lastSignature`. `SettingsStore` reads and writes `settings.json` in `getApplicationSupportDirectory()` through a temporary file and a rename. A damaged file gives defaults and a notice.
  - Default `backupRoot`: `getApplicationDocumentsDirectory()` + `WoW Journey`. Create it on first gather, never earlier.
  - Wizard: 3 pages with Back and Next. Step 1 runs `discoverWow()` in the background. It shows the found folder or "We could not find World of Warcraft" with a Choose folder button; an invalid pick shows the `validateFlavorDir` message; a list shows when there is more than one flavor. Step 2 shows the backup folder with Change and a one-line text: "We keep a copy of your game files and your screenshots here." Step 3 shows the Watch and Start at login switches (on) with one line each. Finish writes the settings. The Start at login switch only stores the value here; Task 8 applies it.
  - `GatherController` (`ChangeNotifier`): state `idle`, `running`, `done`, `failed`. `gatherNow()` runs `gather` through `Isolate.run`, passing plain values. It returns the result or the issues. It never throws to the UI.
  - Home page: a status card ("Up to date. Last gathered 14:32" or "Never gathered"), a Gather now button (off while running, with a progress bar), counts (characters, lines, screenshots), a list of characters (name, realm, level, class), a hint card ("The game saves your journey when you log out or type /reload."), the size of the backup root, the buttons Open backup folder and Open latest data (use `url_launcher` or `Process` per OS; check packages), and a Settings button. Each issue shows `messages.dart` text and a fix action when one exists (Choose folder, Try again).
  - Settings page: Change WoW folder, Change backup folder, Watch switch, Start at login switch, and the app version. The backup root change warns that the old folder stays as it is.
  - Accessibility: every control has a `Semantics` label and a keyboard focus order.
- **Edge cases:** the picker is cancelled; the saved WoW folder is gone at start (show the Choose folder fix); the backup root cannot be created or written; a gather with no Memories data ("No Memories data yet. Play with the Memories addons on, then log out."); the window is narrow (minimum 480 px width); text scale 1.5.
- **Tests:** Widget tests with fake `Discovery`, `FolderPicker`, `GatherService` and `SettingsStore`: wizard happy path; wizard with no folder found; invalid pick; cancel; Finish saves the settings; home states (never gathered, running, done with issues, failed); each issue code has text; the Gather now button is off while running. Unit tests: `SettingsStore` round trip, damaged file, atomic write; `GatherController` state changes; `messages.dart` covers every `GatherIssue.code` (a test iterates the enum).
- **Verify:** `cd app && fvm flutter analyze && fvm flutter test` (unverified); run on Linux with the fixture: set the WoW folder to `testdata/wow` and click Gather now (unverified); manual checks 1 to 6 in `docs/app-manual-checklist.md`.
- **Definition of done:**
  - [ ] Each Covers item is observably met, including one observation that failed before the task.
  - [ ] Tests listed above exist and follow the Tests guidelines.
  - [ ] Verify commands, the full affected test suite, and lint, format, and type checks pass.
  - [ ] E2E tests pass, or the accepted alternative from Risks is done.
  - [ ] All three reviews pass with no valid open findings.
  - [ ] Docs and config that describe the changed behavior are updated.
  - [ ] Task heading checkbox ticked; changes committed.

### [x] 7. Watch mode

- **Outcome:** With Watch on, the app gathers once after the game saves a Memories file, and never reads a half-written file.
- **Depends on:** Task 6.
- **Covers:** AC9, risk "Watch reads a file while the game writes it".
- **Files:** Create `packages/memories_core/lib/src/watch/signature.dart` (pure Dart: compute the signature of a flavor folder) and `app/lib/src/watch/watch_controller.dart`. Tests in both packages. Edit `home_page.dart` (status line "Watching for changes") and `settings_page.dart`.
- **Implementation:**
  - `signature(Directory flavorDir)`: list `WTF/Account/*/SavedVariables/Memories*.lua` and `WTF/Account/*/*/*/SavedVariables/Memories*.lua`; return a sorted list of `path|size|mtimeMs` joined into one string, or its SHA-256 (use `package:crypto`, check the version). Read file metadata only.
  - `WatchController`: a `Timer.periodic(10 s)` poll with an injected clock and signature function. State machine: `idle` → (signature differs from `lastSignature`) → `settling` → (same signature on two polls, at least 5 s apart) → `gathering` → on success save `lastSignature` (the signature taken before the gather) → `idle`. If the signature changes during `gathering`, run again after it. A failed gather does not save the signature and retries at the next change or after 5 minutes at most once.
  - Start on app start when `watch` is true. Stop when the switch is turned off. Do not start a gather while one runs (use `GatherController`).
  - Do not use `Directory.watch`.
- **Edge cases:** the flavor folder is gone; a file is deleted; a new account appears; the signature is the same after a restart (no gather); the clock moves back; a poll that fails to stat a file (treat as unchanged and retry); the user clicks Gather now during `settling`.
- **Tests:** Unit tests with a fake clock and fake signature function for each state change and edge case. Core: signature of the fixture; signature changes on a size change, an mtime change, a new file and a delete (use a temporary copy). Widget test: the Watch switch starts and stops the controller.
- **Verify:** `make dart-test app-test` (unverified); manual: with Watch on, touch a copy of a saved file and see one gather after about 15 s (checklist 7).
- **Definition of done:**
  - [ ] Each Covers item is observably met, including one observation that failed before the task.
  - [ ] Tests listed above exist and follow the Tests guidelines.
  - [ ] Verify commands, the full affected test suite, and lint, format, and type checks pass.
  - [ ] E2E tests pass, or the accepted alternative from Risks is done.
  - [ ] All three reviews pass with no valid open findings.
  - [ ] Docs and config that describe the changed behavior are updated.
  - [ ] Task heading checkbox ticked; changes committed.

### [x] 8. Tray icon, start at login and single instance

- **Outcome:** The app lives in the tray, starts hidden at login when asked, hides on close, and runs once.
- **Depends on:** Task 6 (and Task 7 for the Watch menu state).
- **Covers:** AC10, risks "GNOME tray", "dependency unmaintained", "start at login on".
- **Files:** Edit `app/pubspec.yaml` (add `tray_manager`, `window_manager`, `launch_at_startup`; verify each at its pinned version: changelog, open issues, the Linux, Windows and macOS support, and the Flutter and Dart minimum). Create `app/lib/src/platform/tray_service.dart`, `window_service.dart`, `startup_service.dart`, `single_instance.dart`, tray icon assets in `app/assets/tray/`. Edit `main.dart` and the 3 runner folders as the packages require. Edit the CI `app` job to install the Linux packages that the plugins need.
- **Implementation:**
  - Each service is an interface with a real class and a fake. The real tray class reports `available` (false when the plugin throws or when Linux has no status notifier).
  - Tray menu: Gather now, Open window, Open backup folder, Quit. Every action is a menu item (the Linux tray gives no click events).
  - Close button: if the tray is `available`, hide the window; else quit. Quit from the menu stops Watch and exits.
  - `--hidden` start argument: do not show the window at start (only when `wizardDone`). `StartupService.apply(enabled)` registers or removes the login entry with the app path and `--hidden`. Apply it on wizard Finish and when the switch changes; re-apply at each start when enabled (the app path can change after an update).
  - Single instance: take an exclusive lock on a file in the support directory (`FileLock.exclusive`). The second instance sends a "show window" message over a loopback socket on a port that it writes into the lock file, then exits; if the first does not answer in 2 s, the second shows an error and exits. Do not open any socket for other use. Bind to `127.0.0.1` only.
  - macOS: set `LSUIElement` to false so the Dock icon stays when the window is open (inspect how `window_manager` handles hide on macOS).
- **Edge cases:** tray not available; the window is hidden when Gather ends (no focus steal); start at login with a changed install path; the lock file is stale (the OS releases the lock when the process dies); a second launch while the first shows the wizard.
- **Tests:** Unit tests with fakes: close with and without tray, the menu items call the right controller method, `--hidden` parsing, `StartupService` called on Finish and on the switch and at start, the single-instance lock (two instances in one test using two lock objects on one file). Widget test: Quit stops Watch.
- **Verify:** `make app-test` (unverified); CI build passes on the 3 systems; manual checks 8 to 11 on each OS.
- **Definition of done:**
  - [ ] Each Covers item is observably met, including one observation that failed before the task.
  - [ ] Tests listed above exist and follow the Tests guidelines.
  - [ ] Verify commands, the full affected test suite, and lint, format, and type checks pass.
  - [ ] E2E tests pass, or the accepted alternative from Risks is done.
  - [ ] All three reviews pass with no valid open findings.
  - [ ] Docs and config that describe the changed behavior are updated.
  - [ ] Task heading checkbox ticked; changes committed.

### [x] 9. Remove Go

- **Outcome:** The repository has no Go code, and `make lint test coverage` and CI cover Lua and Dart only.
- **Depends on:** Task 4 (golden parity and CLI). Run it after Tasks 6 to 8 are stable, so Go stays as a reference while the app is built.
- **Covers:** AC13, AC12 (docs), risk "port drift" (Go removed only after parity).
- **Files:** `git rm -r cmd internal go.mod go.sum`. Edit `Makefile` (remove `lint-go`, `test-go`, `coverage-go`, `build`, `GO_COVERAGE_MIN`; remove `go` from `check-tools`; update the `.PHONY` line and `clean`). Edit `.github/workflows/ci.yml` (remove job `go`). Edit `.gitignore` (remove `coverage.out`, `build/` if unused). Edit `README.md` (replace the "Converter" section with the app and the CLI; update the layout and the make table). Edit `docs/` text that names `memories-export` as a Go tool. Edit `.luacheckrc` and `.styluaignore` only if they name a removed path.
- **Implementation:** Keep `testdata/` and `testdata/expected`. Before the removal, run the golden test once more. Search with `grep -rn "go test\|go vet\|memories-export\|dist-characters\|cmd/" .` and fix each hit that is no longer true. The binary name `memories-export` stays as the CLI name.
- **Edge cases:** `web-demo` and `web-data` still work; `make check-tools` still passes on a machine with no Go; CI has no job that needs Go.
- **Tests:** The existing Dart golden and CLI tests are the proof. Add a test (shell or Dart) that fails if a `*.go` file or `go.mod` exists: `scripts/no-go.sh` run by `make lint`.
- **Verify:** `make lint test coverage` (unverified); `make web-demo` serves the viewer (unverified); `git ls-files | grep -E '\.go$|go\.mod'` prints nothing.
- **Definition of done:**
  - [ ] Each Covers item is observably met, including one observation that failed before the task.
  - [ ] Tests listed above exist and follow the Tests guidelines.
  - [ ] Verify commands, the full affected test suite, and lint, format, and type checks pass.
  - [ ] E2E tests pass, or the accepted alternative from Risks is done.
  - [ ] All three reviews pass with no valid open findings.
  - [ ] Docs and config that describe the changed behavior are updated.
  - [ ] Task heading checkbox ticked; changes committed.

### [x] 10. Release workflow with macOS signing

- **Outcome:** A tag `vX.Y.Z` makes a GitHub Release with the addon zip and the app for Windows, macOS (signed, notarized) and Linux.
- **Depends on:** Tasks 1 and 8 (the plugins that affect the macOS entitlements and the Linux packages).
- **Covers:** AC15, risks "macOS sandbox", "notarization secrets".
- **Files:** Create `.github/workflows/release.yml`, `scripts/package-addons.sh`, `app/macos/Runner/Release.entitlements` changes, `docs/releasing.md`. Edit `README.md` (install from a release, and the Windows SmartScreen steps). Inspect the 6 TOCs for `## Version:`.
- **Implementation:**
  - Triggers: `push: tags: ['v*']` and `workflow_dispatch` (build only, no publish). Permissions: `contents: write` only on the publish job; `contents: read` elsewhere.
  - `scripts/package-addons.sh <version> <out.zip>`: copy `addons/*` into a staging folder, set `## Version: <version>` in each TOC of the copy, zip with the 6 folders at the zip root (`Memories/`, `Memories_Combat/`, ...). Test it locally and in `spec` or a shell test: the zip holds 6 folders, each TOC has the version, the repository files are unchanged.
  - Version: the tag without `v`. Reject a tag that is not `v` + semver. The app uses `--build-name=<version> --build-number=<run number>`.
  - Build jobs on `ubuntu-latest`, `windows-latest`, `macos-latest` with `fvm`-pinned Flutter (read `.fvmrc`). Linux: install `ninja-build libgtk-3-dev` and the plugin packages from Task 8; `flutter build linux --release`; `tar -czf WoW-Journey-<version>-linux-x64.tar.gz` of `build/linux/x64/release/bundle`. Windows: `flutter build windows --release`; zip `build/windows/x64/runner/Release`. macOS: `flutter build macos --release`; sign inside-out with `codesign --force --options runtime --timestamp --entitlements Release.entitlements --sign "Developer ID Application: ..."` on each nested framework and the app; zip with `ditto -c -k --keepParent`; `xcrun notarytool submit --wait` with an App Store Connect API key; `xcrun stapler staple`; zip again; check with `spctl --assess --type execute` and `codesign --verify --deep --strict`.
  - Entitlements: `com.apple.security.app-sandbox` is false for Release. Add only entitlements that a test proves necessary.
  - Secrets (names fixed here): `MACOS_CERTIFICATE` (base64 `.p12`), `MACOS_CERTIFICATE_PASSWORD`, `MACOS_KEYCHAIN_PASSWORD`, `MACOS_SIGNING_IDENTITY`, `APPLE_API_KEY_ID`, `APPLE_API_ISSUER_ID`, `APPLE_API_KEY` (base64 `.p8`). Import the certificate into a temporary keychain and delete it in an `always()` step. Never print a secret. If any secret is empty, the macOS job fails with a message that names the missing secret.
  - Publish job: needs all build jobs; runs only on a tag; creates the release with `gh release create --generate-notes` and uploads `Memories-addons-<version>.zip`, `WoW-Journey-<version>-windows-x64.zip`, `WoW-Journey-<version>-macos.zip`, `WoW-Journey-<version>-linux-x64.tar.gz`. A dry run (`workflow_dispatch`) uploads the same files as workflow artifacts.
  - Pin each action by SHA with a version comment.
- **Edge cases:** a tag that is not semver; a pre-release tag (`v1.0.0-rc.1`) makes a pre-release; a re-run of a tag (the release exists: update the assets, do not fail on a duplicate); a Linux bundle missing a shared library (document the packages in the README); a macOS universal build (check `lipo -archs`; record the result).
- **Tests:** `scripts/package-addons.sh` has a shell test (`scripts/test-package-addons.sh`, run by `make test`). The workflow is checked with `actionlint` (add to `make lint` if it is installed, and to CI as a pinned action). The dry run on a branch proves the builds.
- **Verify:** `bash scripts/test-package-addons.sh`; `actionlint .github/workflows/*.yml` (unverified); run the workflow with `workflow_dispatch` after the user pushes and the secrets exist; manual checks 12 to 14 on a downloaded release.
- **Definition of done:**
  - [ ] Each Covers item is observably met, including one observation that failed before the task.
  - [ ] Tests listed above exist and follow the Tests guidelines.
  - [ ] Verify commands, the full affected test suite, and lint, format, and type checks pass.
  - [ ] E2E tests pass, or the accepted alternative from Risks is done.
  - [ ] All three reviews pass with no valid open findings.
  - [ ] Docs and config that describe the changed behavior are updated.
  - [ ] Task heading checkbox ticked; changes committed.

## Validation

Run after the last task.

**Automated**
- `make lint test coverage` passes (Lua and Dart; Dart core at least 80 %).
- `git ls-files | grep -E '\.go$|^go\.(mod|sum)$'` prints nothing.
- CI passes on the 3 systems for the pull request.
- A `workflow_dispatch` run of `release.yml` builds the 4 files.

**Manual** (kept in `docs/app-manual-checklist.md`; there is no e2e suite). Run on Windows, macOS and Linux unless noted.
1. First start with no settings: the wizard shows. Step 1 shows the found folder, or the picker when none is found.
2. Choose a folder with no `WTF/Account`: a plain message shows and the folder is not saved.
3. Step 2 shows `Documents/WoW Journey`. Change it to another folder.
4. Finish: the main screen shows. Restart: the wizard does not show.
5. Click Gather now with a real flavor folder: `latest/` and `backups/<stamp>/` exist, and the counts match `/mem status` in the game.
6. Click Gather now again with no new data: no file in `latest/` changes.
7. Watch on: log out of the game. One gather runs within about 15 s of the file change.
8. Close the window: the app hides to the tray. Open it from the tray menu.
9. Quit from the tray menu: the process ends.
10. Start at login: sign out and in. The app starts hidden and the tray shows.
11. Start a second copy: the first window shows and the second exits. (Linux GNOME with no AppIndicator: closing the window quits.)
12. macOS: open the downloaded app. No Gatekeeper warning. `spctl --assess --type execute -vv` says "accepted, notarized".
13. Windows: open the downloaded zip. Follow the SmartScreen steps in the README.
14. Linux: unpack the tar.gz and run the binary on a clean machine.
15. Reinstall case: delete the saved files from a copy of the WoW folder, add a new session, gather. Old lines stay in `latest/`.
16. Open `latest/` with `make web` and see the map and the tables.

## References

- Registry key and macOS path rules: https://powershellgallery.com/packages/PSElvUI/1.6.1/Content/functions/private/Get-WoWInstallPath.ps1
- WoW file locations: https://warcraft.wiki.gg/wiki/World_of_Warcraft_File_Locations
- SavedVariables paths: https://warcraft.wiki.gg/wiki/Saved_variables
- `tray_manager` docs and Linux notes: https://pub.dev/packages/tray_manager and https://github.com/leanflutter/tray_manager/wiki
- Flutter integration tests and `xvfb-run` on Linux: https://docs.flutter.dev/testing/integration-tests
- `subosito/flutter-action`: https://github.com/subosito/flutter-action
- Apple notarization with `notarytool`: https://developer.apple.com/documentation/security/customizing-the-notarization-workflow
- Go `encoding/json` encoding rules (floats, escapes, key order): https://pkg.go.dev/encoding/json

## Open Decisions

| Decision | Impact | Default used in this spec |
|---|---|---|
| App display name and bundle id. | The signing identity, the app folder name and the artifact names use them. A rename after release is costly. | Display name "WoW Journey", package `wow_journey`, bundle id `com.fmartingr.wowjourney`. |
| Apple signing material: Developer ID Application certificate, team id, App Store Connect API key. | Task 10 cannot run its macOS job without them. | The user adds the 7 secrets named in Task 10 before the first tag. |
| Windows signing. | Windows shows SmartScreen on the first start. | Out of scope. The README documents the steps. |
| Gather of more than one flavor folder. | A player with two flavor folders must switch the setting by hand. | One flavor folder (see Decisions). |
| Flutter version to pin. | All FVM and CI jobs use it. | The stable version at the time of Task 1. |
| App icon and tray icon art. | Release looks unfinished with default icons. | Task 1 and Task 8 use a plain placeholder icon. |
| Backup pruning. | The backup folder grows with each gather. | None in this version. The main screen shows the size. |

## Completion

When every task is checked and Validation passes, move this file to `specs/done/` with `git mv` (plain `mv` when the file is untracked). Create `specs/done/` if it does not exist. Commit the move.
