# Memories

Memories is a set of World of Warcraft addons for WoW Forever (Interface 16001) that records each character's journey
into the saved files: sessions, travel, deaths, progress, kills, gathering, loot, money, skills, groups, PvP and more.
A Go converter (`memories-export`) turns the saved files into JSONL files for a website.

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

## Converter

`memories-export` reads the saved files of every character in one flavor folder and writes the website data. It never
runs Lua, never writes into `WTF/` or `Screenshots/` and never changes a saved file or an image. Log out of the game
or `/reload` first, so the saved files are current.

```sh
make export WOW_DIR=".../World of Warcraft/_forever_"
# or
make build && build/memories-export --wow-dir ".../World of Warcraft/_forever_" [--dist DIR] [--backup DIR] [--default ID]
```

- `--dist` (default `./dist-characters`) and `--backup` (default `./backups`) may not be inside `WTF/` or `Screenshots/`,
  nor hold them.
- `--default` picks the character the website opens first; a later run keeps that choice.
- Exit code 2 is a usage error, 1 a run error. A damaged saved file is reported with its line and skipped.
  A damaged or missing account `Memories.lua` skips the characters of that account, since their fields cannot be named.

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
| `make check-tools` | Report each missing tool (`lua5.1`, `luarocks`, `busted`, `luacheck`, `luacov`, `stylua`, `go`). |
| `make deps` | Install busted, luacov and luacheck with luarocks (Lua 5.1). |
| `make lint` | `lint-lua` (luacheck), `lint-go` (gofmt and go vet) and `fmt-check` (stylua). |
| `make fmt` | Format the Lua and Go code. |
| `make test` | `test-lua` (busted) and `test-go` (Go tests with the race detector). |
| `make coverage` | `coverage-lua` and `coverage-go`. The core files (`addons/Memories/Core/`, `addons/Memories/Data/`) and Go `internal/` need 80 %; the total Lua coverage is printed. |
| `make build` | Build the converter into `build/memories-export`. |
| `make install WOW_DIR=...` | Copy each addon folder into the game. |
| `make link WOW_DIR=...` | Link each addon folder into the game. |
| `make export WOW_DIR=...` | Run the converter. |
| `make clean` | Remove `build/` and the coverage files. |

## Layout

- `addons/` — the 6 addons.
- `cmd/memories-export/` and `internal/` — the converter.
- `spec/` — busted tests and the WoW stub harness (`spec/helpers/wow.lua`); `testdata/` — converter fixtures.
- `docs/` — [`kinds.md`](docs/kinds.md), [`public-api.md`](docs/public-api.md),
  [`sub-addon-api.md`](docs/sub-addon-api.md) and [`manual-checklist.md`](docs/manual-checklist.md) (the checks to run
  in the game).
