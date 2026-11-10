# Converter

Back to the [documentation index](README.md).

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
- `dist-characters/<id>/character.json` — the `char` table (including `locale`, the `GetLocale()` value of the game client
  at the last login, when the addon recorded it), `region`, `realm`, `realmLabel`, `flavor`, `sessions`,
  `flags` and `addons: {<addon>: {counts, snap, schema, writtenBy}}`.
- `dist-characters/<id>/screenshots/` — the matched screenshot files.

The id is `<region>-<realm>-<name>` in ASCII lower case (`eu-brumamar-nandu` for Ñandú on Brumamar). Each run keeps
the records, trail chunks and sessions of the runs before it, the id each character had, and the `index.json` entry of
a character this run did not write.
