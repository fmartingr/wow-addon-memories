# Memories

Memories is a set of World of Warcraft addons for WoW Forever (Interface 16001) that records each character's journey:
sessions, travel, deaths, progress and more. A Go converter (`memories-export`) turns the saved files into JSONL files.

The full design is in [`specs/2026-11-06-memories-addon-set.md`](specs/2026-11-06-memories-addon-set.md).

## Layout

- `addons/Memories/` — the core addon.
- `addons/Memories_Gathering/` — gathering, fishing, opening and pick pocket (`MemoriesGatheringCharDB`).
- `cmd/memories-export/` — the converter.
- `spec/` — busted tests and the WoW stub harness (`spec/helpers/wow.lua`).
- `docs/manual-checklist.md` — the checks to run in the game.

## In the game

- `/memories` (or `/mem`) lists the commands.
- `/mem options` (or `/mem settings`) opens the Settings page: the recording rate, the screenshot, save reminder,
  minimap and low-health settings, one checkbox per kind with "Enable all" and "Disable all" for each group, and the
  "New findings only" boxes. Settings are account-wide, in `MemoriesDB.settings`.
- `/mem status` shows each addon of the set (on, off, missing, failed or newer api), its lines, its kinds that are off
  and the age of its backup, then the login time.
- `/mem errors` shows the saved errors, ready to copy.
- The minimap button and the addon compartment entry save (reload) with a left click and open the Settings page with a
  right click.
- Every screenshot the game saves gets an `ss` line with its predicted file name, unless the `ss` kind is off or the
  shot is a silent one. Memories takes screenshots of its own only when "Screenshot at level-up" is on (off by
  default).

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

| Target | What it does |
|---|---|
| `make check-tools` | Report each missing tool. |
| `make deps` | Install busted, luacov and luacheck with luarocks (Lua 5.1). |
| `make lint` | luacheck, gofmt, go vet and the stylua format check. |
| `make fmt` | Format the Lua and Go code. |
| `make test` | Run the busted and Go tests. |
| `make coverage` | Run the tests with coverage. The core files need 80 %; the total Lua coverage is printed. |
| `make build` | Build the converter into `build/`. |
| `make install WOW_DIR=.../_forever_` | Copy each addon folder into the game. |
| `make link WOW_DIR=.../_forever_` | Link each addon folder into the game. |
| `make export WOW_DIR=.../_forever_` | Run the converter. |
