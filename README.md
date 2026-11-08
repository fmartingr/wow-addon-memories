# Memories

Memories is a set of World of Warcraft addons for WoW Forever (Interface 16001) that records each character's journey
into the saved files: sessions, travel, deaths, progress, kills, gathering, loot, money, skills, groups, PvP and more.
The WoW Journey desktop app (`app/`) and the command line converter `memories-export` turn the saved files into
JSONL files for a website. Both run the same gather of the Dart core `packages/memories_core`.

The full design is in [`specs/2026-11-06-memories-addon-set.md`](specs/2026-11-06-memories-addon-set.md). Every kind
of journal line and its fields are in [`docs/kinds.md`](docs/kinds.md).

> Memories takes no screenshots of its own; use
> Paparazzi for that.

## The addons

Each addon has its own per-character saved file. A sub-addon loads only when `Memories` loads
(`## Dependencies: Memories`), and the AddOn list shows all 6 as the group "Memories". Turn a sub-addon off in the
AddOn list to stop its recording.

| Addon | Records | Saved table |
|---|---|---|
| `Memories` (core, always on) | sessions, the position trail, progress (levels, XP, quests, discoveries, rest), deaths, close calls, travel (zones, flights, boats, hearthstone, summons, portals, mounts), dungeons and bosses, screenshots, and lines from other addons | `MemoriesCharDB`, plus the account table `MemoriesDB` (settings, backups, orphans, errors, kind metadata) |
| `Memories_Combat` | kills, rare kills and long fights | `MemoriesCombatCharDB` |
| `Memories_Gathering` | gathering, fishing, opening containers and chests, pick pocket | `MemoriesGatheringCharDB` |
| `Memories_Character` | skills, spells, recipes, talents, consumables, tamed pets, reputation, accepted quests, homes, flight paths and books | `MemoriesCharacterCharDB` |
| `Memories_Economy` | loot, group rolls, gear, equipped items, money, trainers, the auction house, mail and trade | `MemoriesEconomyCharDB` |
| `Memories_Social` | group members, your guild, enemy players, PvP kills and deaths, honor, duels, battlegrounds and PvP rank | `MemoriesSocialCharDB` |

## Install

`WOW_DIR` is the flavor folder, the one that holds `Interface/AddOns`:

```sh
make install WOW_DIR=".../World of Warcraft/_forever_"   # copy the 6 addon folders
make link WOW_DIR=".../World of Warcraft/_forever_"      # or link them, for development
```

Both replace the 6 `Memories*` folders in `Interface/AddOns`. Then start the game and enable the addons you want in the
AddOn list.

## Settings and commands

- `/memories` (or `/mem`) lists the commands.
- `/mem options` (or `/mem settings`) opens the Settings page (Options > AddOns > Memories). Settings are
  account-wide, in `MemoriesDB.settings`:
  - **General:** "Recording rate" of the trail (1, 2, 5 or 10 s; default 2 s), "Save reminder", "Minimap button"
    and "Low-health flash" (all on).
  - **Kinds:** one checkbox per kind under `<addon> — <group>`, with "Enable all" and "Disable all" for each group.
    Every kind is on by default. A kind that is off writes no line, but its counts go on.
  - **New findings only:** Gathering (`ga`, `fs`), Kills (`ki`), Loot (`lo`) and Consumables (`cu`), all off. When a
    box is on, its kinds write a line only for a first finding or a rare one.
- `/mem status` shows each addon of the set (on, off, missing, failed or newer api), its lines, the number of its kinds
  that are off and the age of its backup, then the login time.
- `/mem errors` shows the saved errors, ready to copy.
- The minimap button and the addon compartment entry save (reload) with a left click and open the Settings page with a
  right click.
- After 1 hour with no save, a chat line and the pulsing minimap button remind you to save (save reminder).
- Each journal has a rolling backup in `MemoriesDB.backups`. When a journal loads empty and its backup has lines, a
  popup asks you to restore the backup or start fresh (data guard).
- Memories keeps the game's low-health flash on to record close calls. When the flash is off, a popup asks to keep it
  on or turn it off.
- Every screenshot the game saves gets an `ss` line with its predicted file name, unless the `ss` kind is off.
  Memories takes no screenshot itself.

## Other addons

Other addons write events and screenshot notes into the journal with `Memories.RecordEvent` and
`Memories.RecordScreenshot`. See [`docs/public-api.md`](docs/public-api.md). Memories sub-addons use
[`docs/sub-addon-api.md`](docs/sub-addon-api.md).

## The WoW Journey app

`app/` is a desktop app (Windows, macOS, Linux) that runs the converter for you. Start it with `make companion`.
A Linux build needs `ninja-build`, `libgtk-3-dev`, `libx11-dev` and `libxi-dev` (Debian and Ubuntu names), and a C++
compiler: the tray plugin builds its native library with the app.

- **First start:** a 3-step wizard. Step 1 finds the WoW folder (or opens a folder picker), step 2 sets the backup
  folder (default `<Documents>/WoW Journey`), step 3 has the Watch and Start at login switches (both on).
- **Main screen:** the last gather time, a Gather now button, the counts (characters, journal lines, screenshots),
  the characters, each problem in plain words with a fix button, the size of the backup folder, and Open backup
  folder and Open latest data.
- **Settings:** change the WoW folder or the backup folder (the old backup folder stays as it is), the two switches and
  the version.
- **Tray:** the tray icon has the menu Gather now, Open window, Open backup folder and Quit. Closing the window hides
  it to the tray; Quit stops Watch and ends the app. A gather from the tray leaves a hidden window hidden. When there
  is no tray, closing the window quits the app. On Linux the icon needs a panel with status notifier icons: KDE Plasma
  and most other desktops have one, GNOME only with the AppIndicator extension (Ubuntu has it on).
- **Start at login:** while it is on, the app starts hidden at login (`--hidden`), with only the tray icon. It writes
  the login entry on Finish, when the switch changes and again at each start, so a moved app still starts. The entry
  is the `Run` registry key on Windows, `~/.config/autostart/WoW Journey.desktop` on Linux and
  `~/Library/LaunchAgents/com.fmartingr.wowJourney.plist` on macOS. A hidden start shows the window anyway when the
  wizard has not run or there is no tray.
- **One copy:** a second start shows the window of the first one and ends. The first copy holds a lock on
  `instance.lock` in the app support folder and listens on a `127.0.0.1` port that it writes in that file.
- **Watch:** while it is on, the main screen says "Watching for changes". Every 10 s the app reads the size and the
  modification time of each Memories saved file. After a change it waits until the files stay the same for at least
  5 s, then gathers once. It saves the state of the last gather in the settings, so a restart with no change does not
  gather. A failed gather runs again at the next change, or once after 5 minutes.
- The backup folder holds `latest/` (the website data, the `dist-characters/` layout below) and `backups/<UTC stamp>/`.
- Manual checks: [`docs/app-manual-checklist.md`](docs/app-manual-checklist.md).

## Converter

The app gathers into its backup folder (see above). `memories-export` is the same gather on the command line: it reads
the saved files of every character in one flavor folder and writes the website data. It never runs Lua, never writes
into `WTF/` or `Screenshots/` and never changes a saved file or an image. Log out of the game or `/reload` first, so
the saved files are current.

```sh
make export WOW_DIR=".../World of Warcraft/_forever_" [DIST=DIR] [BACKUP=DIR] [DEFAULT=ID]
# or
fvm dart run packages/memories_core/bin/memories_export.dart --wow-dir ".../World of Warcraft/_forever_" [--dist DIR] [--backup DIR] [--default ID]
```

- `--wow-dir` (required) is the flavor folder. Each flag also takes the single-dash form (`-wow-dir`), and
  `--help` prints the flags.
- `--dist` (default `./dist-characters`) and `--backup` (default `./backups`) may not be inside `WTF/` or `Screenshots/`,
  nor hold them.
- `--default` picks the character the website opens first; a later run keeps that choice.
- The converter holds a lock on `.gather.lock` in the parent folder of `--backup` (after links are resolved). A
  second run with the same parent folder stops with exit code 1. Keep `--dist` next to `--backup`, as the defaults do,
  so the lock also covers `--dist`.
- Exit code 2 is a usage error, 1 a run error. A damaged saved file is reported with its line and skipped.
  A damaged or missing account `Memories.lua` skips the characters of that account, since their fields cannot be named.
  For a damaged sub-addon file, the converter keeps that addon's entry of the earlier run, so the output does not
  change. A character folder in `--dist` that is a link is left as it was.

Output:

- `backups/<UTC stamp>/savedvariables/<flavor>/...` — a copy of every saved file read;
  `backups/<UTC stamp>/screenshots/` — the matched screenshots.
- `dist-characters/index.json` — `default_character` and `characters` (id, guid, name, region, realm, flavor, class,
  race, sex, faction, level, file paths, `steps`, `sessions`, `trailPoints`, `screenshots`, `addons`, `start`, `end`).
- `dist-characters/<id>/journey.jsonl` — one record per journal line of the core and the sub-addons, sorted by time:
  `t`, `p`, `m`, `x`, `y`, `k`, `addon`, the named fields of the kind, `session`, and `extra` (`{"<field number>":
  "<text>"}`, 1-based) for values with no name or text in a numeric field. An `sn` note joins its `ss` record as
  `notes: [{source, note}]`; a matched file adds `screenshot: "screenshots/<file>"`.
- `dist-characters/<id>/trail.jsonl` — one record per trail chunk: `{s, t, m, n, pts: [[time, x, y, flags], ...]}`.
- `dist-characters/<id>/character.json` — the `char` table, `region`, `realm`, `realmLabel`, `flavor`, `sessions`,
  `flags` and `addons: {<addon>: {counts, snap, schema, writtenBy}}`.
- `dist-characters/<id>/screenshots/` — the matched screenshot files.

The id is `<region>-<realm>-<name>` in ASCII lower case (`eu-brumamar-nandu` for Ñandú on Brumamar). Each run keeps
the records, trail chunks and sessions of the runs before it, the id each character had, and the `index.json` entry of
a character this run did not write.

## Make targets

`WOW_DIR` is the flavor folder, for example `.../World of Warcraft/_forever_`.

| Target | What it does |
|---|---|
| `make help` | List the targets. |
| `make check-tools` | Report each missing tool (`lua5.1`, `luarocks`, `busted`, `luacheck`, `luacov`, `stylua`, `fvm`). |
| `make deps` | Install busted, luacov and luacheck with luarocks (Lua 5.1). |
| `make lint` | `lint-lua` (luacheck), `lint-no-go` (`scripts/no-go.sh`: no tracked `*.go`, `go.mod` or `go.sum`), `dart-lint` and `app-lint` (analyze and format check) and `fmt-check` (stylua). |
| `make fmt` | Format the Lua and Dart code. |
| `make test` | `test-lua` (busted), `dart-test` (Dart core tests) and `app-test` (Flutter app tests). |
| `make coverage` | `coverage-lua` and `dart-coverage`. The core files (`addons/Memories/Core/`, `addons/Memories/Data/`) and the Dart core `lib/` need 80 %; the total Lua coverage is printed. |
| `make companion` | Run the WoW Journey app on this system. `COMPANION_DEVICE=linux`, `macos` or `windows` picks the device. |
| `make install WOW_DIR=...` | Copy each addon folder into the game. |
| `make link WOW_DIR=...` | Link each addon folder into the game. |
| `make export WOW_DIR=...` | Run `memories-export`; `DIST`, `BACKUP` and `DEFAULT` set `--dist`, `--backup` and `--default`. |
| `make clean` | Remove the coverage files and `app/build/`. |

## Layout

- `addons/` — the 6 addons.
- `packages/memories_core/` — the Dart core (no Flutter) with the `memories-export` command
  (`bin/memories_export.dart`); `app/` — the WoW Journey desktop app. Both use the Flutter version in `.fvmrc` through [FVM](https://fvm.app).
- `spec/` — busted tests and the WoW stub harness (`spec/helpers/wow.lua`); `testdata/` — converter fixtures (`testdata/wow`)
  and their golden output (`testdata/expected`).
- `docs/` — [`kinds.md`](docs/kinds.md), [`public-api.md`](docs/public-api.md),
  [`sub-addon-api.md`](docs/sub-addon-api.md), [`manual-checklist.md`](docs/manual-checklist.md) (the checks to run
  in the game) and [`app-manual-checklist.md`](docs/app-manual-checklist.md) (the checks of the app).
