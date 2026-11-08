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

From a [GitHub release](../../releases): unpack `Memories-addons-<version>.zip` into `Interface/AddOns` of the flavor
folder (for example `.../World of Warcraft/_forever_/Interface/AddOns`). The zip holds the 6 `Memories*` folders.

From the repository, `WOW_DIR` is the flavor folder, the one that holds `Interface/AddOns`:

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

`app/` is a desktop app (Windows, macOS, Linux) that runs the converter for you. Download it from a
[GitHub release](../../releases), or start it from the repository with `make companion`. A Linux build needs
`ninja-build`, `libgtk-3-dev`, `libx11-dev` and `libxi-dev` (Debian and Ubuntu names), and a C++ compiler: the tray
plugin builds its native library with the app.

Install from a release:

- **Windows:** unpack `WoW-Journey-<version>-windows-x64.zip` and start `WoW-Journey\wow_journey.exe`. The app is not
  signed, so on the first start Windows SmartScreen shows "Windows protected your PC". Click **More info**, check that
  the file is `wow_journey.exe`, then click **Run anyway**.
- **macOS:** unpack `WoW-Journey-<version>-macos.zip` and move `wow_journey.app` to `Applications`. The app is signed
  and notarized, so it opens with no warning. It runs on Apple silicon and Intel Macs.
- **Linux:** unpack `WoW-Journey-<version>-linux-x64.tar.gz` and start `WoW-Journey/wow_journey`. Keep the `lib/`
  and `data/` folders next to it. It needs the GTK 3, X11 and Xi shared libraries: `libgtk-3-0` (`libgtk-3-0t64` on
  Ubuntu 24.04 and later), `libx11-6` and `libxi6` on Debian and Ubuntu, `gtk3`, `libX11` and `libXi` on Fedora,
  `gtk3`, `libx11` and `libxi` on Arch. `ldd WoW-Journey/wow_journey | grep "not found"` lists a missing one.

Releases are cut as described in [`docs/releasing.md`](docs/releasing.md).

- **First start:** a 3-step wizard. Step 1 finds the WoW folder (or opens a folder picker), step 2 sets the backup
  folder (default `<Documents>/WoW Journey`), step 3 has the Watch and Start at login switches (both on).
- **Main screen:** the last gather time, a Gather now button, the counts (characters, journal lines, screenshots),
  the characters, each problem in plain words with a fix button, the size of the backup folder, and Open backup
  folder and Open latest data.
- **Settings:** change the WoW folder or the backup folder (the old backup folder stays as it is), the two switches,
  the Website section and the version.
- **Website:** the Website section of the settings has the website address (default `https://wowjourney.xyz`; only
  `https://`, or `http://` for `localhost`, `127.0.0.1` and `[::1]`), a Check button, the registration (an invite code,
  or one click on a website with open registration), the Upload switch (off by default, and it stays off until the key
  is registered), Request screenshots and the key fingerprint. With Upload on, the app sends the journey after each
  gather. The main screen has a Website card with Upload now, the last result, and for each uploaded character its
  link with Copy link and Remove from website. A removed character is not uploaded again after a gather; Upload now
  sends every removed character again. Character pages are unlisted: anybody with the link can open them. The
  key is `upload-key.json` and the state `upload-state.json`, in the app support folder; after a reinstall the website
  admin moves your characters to the new key. A build can set another default address with
  `--dart-define=WOWJOURNEY_SITE=http://localhost:8080`.
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

## Uploader

`memories-upload` sends the characters of a `latest/` folder (the output of the gather) to a website, with the upload
API of [the server](#the-server). It is pure Dart, so it needs no Flutter.

```sh
make upload SITE=https://wowjourney.xyz LATEST=dist-characters [INVITE=CODE] [KEY=FILE] [STATE=FILE] [DELETE=PATH] [REQUEST_SCREENSHOTS=1]
# or
fvm dart run packages/memories_core/bin/memories_upload.dart --site https://wowjourney.xyz --latest dist-characters [--invite CODE] [--key FILE] [--state FILE] [--delete PATH] [--request-screenshots]
```

- `--site` (required) is `https://host[:port]`. Plain `http://` works for `localhost`, `127.0.0.1` and `[::1]` only.
- `--key` (default `./upload-key.json`) holds the Ed25519 key that identifies you. The tool makes it when it is
  missing, with mode 600 on Linux and macOS. Keep it: without it the characters you uploaded stay with the old key.
  A damaged key file stops the run and is never overwritten.
- `--state` (default `./upload-state.json`) remembers, for each website, whether the key is registered and what was
  sent. A damaged state file gives a warning and a fresh start.
- The tool runs these steps in this order: register (when the state says the key is not registered, or when
  `--invite` is given), upload `--latest`, `--delete PATH` (for example `wow/eu/brumamar/nandu`), and
  `--request-screenshots`. A run with no step but `--site` registers the key when the state says it is not
  registered, and otherwise does nothing.
- `--latest` uploads each character whose data changed since the last run and reports the others as `unchanged`. When
  the website has approved screenshots for the key, it also uploads each screenshot that a record names. An approval
  that comes after the first upload sends each character once more, so the website stores the screenshot links.
- Exit code 0 is a pass, 1 a run error (a rejected upload prints its problems, a `429` prints `Retry-After`), 2 a usage
  error.

## The server

`server/` is a Go web server for the WoW Journey website. It serves the home page, `robots.txt`, `/api/v1/info`
and the signed API below, and answers every other path with one 404 page (a JSON error under `/api/`). Every response carries the security
headers. Run it with `make server-run`, then open <http://localhost:8080/>. The admin page listens on
`MEMORIES_ADMIN_ADDR` (default `127.0.0.1:8081`; the log warns when the address is not loopback). It has plain HTML
forms and no JavaScript, and it accepts only `localhost:<port>` and `127.0.0.1:<port>` as `Host`, so reach it with an
SSH tunnel. There the admin makes and revokes invite codes, approves, denies and revokes screenshots, revokes keys
(with or without deleting their characters), deletes characters and moves a claim to another key.

The server keeps its data in `MEMORIES_DATA_DIR`: the SQLite database `memories.db` (keys, invite codes, claims and
the nonces of signed requests). The upload API keeps the character files in `characters/`. The API accepts only requests that
carry the 4 `Memories-*` signature headers of an Ed25519 key. `POST /api/v1/register` registers a key (with a
single-use invite code in `invite` mode), `GET /api/v1/me` lists the key's characters and its screenshot state, and
`POST /api/v1/screenshots/request` asks for screenshot approval. `POST /api/v1/characters` uploads one character (gzip, `Content-Encoding: gzip`): the server checks every record, merges it into the stored data of that address and writes the files itself; the first key to upload an address owns it, and only that key can upload it again or delete it with `DELETE /api/v1/characters/<flavor>/<region>/<realm>/<name>`. A key with no screenshot approval gets the `screenshot` field removed from the records it uploads. An upload that is too big, or that would grow the stored files of its character past twice `MEMORIES_MAX_DECODED_BYTES`, gets `413`; one over a quota of the key gets `507`. A request with a bad signature, a time more than 300 s
off or a nonce seen in the last 600 s gets `401`; a revoked key gets `403 key_revoked`. A key may send
`MEMORIES_RATE_SIGNED_PER_MINUTE` signed requests a minute, an address may try `MEMORIES_RATE_REGISTER_PER_HOUR`
registrations an hour and send `MEMORIES_RATE_PUBLIC_PER_MINUTE` requests a minute (pages and API); more gets `429` with `Retry-After`.
The server reads the client address from the connection, and from `X-Forwarded-For` only when the connection comes from
an address in `MEMORIES_TRUSTED_PROXIES`.

It reads these environment variables; an unset or empty one takes its default, and a bad value stops the server with
exit code 2. The size limits and quotas other than the rate limits apply to the upload API:

| Variable | Default | Meaning |
|---|---|---|
| `MEMORIES_PUBLIC_ADDR` | `:8080` | Public listener. |
| `MEMORIES_ADMIN_ADDR` | `127.0.0.1:8081` | Admin listener. |
| `MEMORIES_DATA_DIR` | `./data` | Data folder. |
| `MEMORIES_WEB_DIR` | `../web` | Folder with the viewer files. |
| `MEMORIES_SITE_URL` | `http://localhost:8080` | Public address of the site: `http` or `https`, no path. A trailing `/` is dropped. |
| `MEMORIES_SITE_NAME` | `WoW Journey` | Name of the site. |
| `MEMORIES_GITHUB_URL` | `https://github.com/fmartingr/wow-addon-memories` | Repository; the home page links to it and to its `/releases/latest`. |
| `MEMORIES_REGISTRATION` | `invite` | `invite` or `open`. |
| `MEMORIES_TRUSTED_PROXIES` | empty | Comma-separated CIDR list of proxies whose `X-Forwarded-For` is trusted. |
| `MEMORIES_MAX_UPLOAD_BYTES` | 16 MiB | Largest upload request. |
| `MEMORIES_MAX_SHOT_BYTES` | 15 MiB | Largest screenshot request. |
| `MEMORIES_MAX_PIXELS` | 50,000,000 | Largest screenshot, in pixels. |
| `MEMORIES_MAX_DECODED_BYTES` | 64 MiB | Largest upload after gzip is undone. |
| `MEMORIES_MAX_TEXT` | 512 | Longest text value in an upload, in bytes. |
| `MEMORIES_MAX_RECORDS` | 500,000 | Journey records in one upload. |
| `MEMORIES_MAX_CHUNKS` | 50,000 | Trail chunks in one upload. |
| `MEMORIES_MAX_POINTS` | 20,000 | Points in one trail chunk. |
| `MEMORIES_MAX_CHARACTERS_PER_KEY` | 50 | Characters of one key. |
| `MEMORIES_MAX_DATA_BYTES_PER_KEY` | 512 MiB | Journey data of one key. |
| `MEMORIES_MAX_SHOT_BYTES_PER_KEY` | 5 GiB | Screenshots of one key. |
| `MEMORIES_MAX_CONCURRENT_UPLOADS` | 2 | Uploads that the server unpacks and stores at the same time. A full-size upload takes about 800 MB of memory while it is handled; a further upload waits up to 10 s for a free place, then gets `503` with `Retry-After`. |
| `MEMORIES_RATE_SIGNED_PER_MINUTE` | 120 | Signed requests a minute for one key. |
| `MEMORIES_RATE_REGISTER_PER_HOUR` | 10 | Registrations an hour from one IP. |
| `MEMORIES_RATE_PUBLIC_PER_MINUTE` | 600 | Requests a minute from one IP to the public listener (pages and API). |

To run your own site, build the Docker image (`docker build -f server/Dockerfile -t memories-server .`) or use the
compose file in `deploy/` (the server behind Caddy). `memories-server backup <new folder>` copies the database and the
character files while the server runs. [`docs/self-host.md`](docs/self-host.md) has the setup, the admin tunnel, the
backup and the restore.

The design is in [`specs/2026-11-08-upload-backend.md`](specs/2026-11-08-upload-backend.md).

## License

GPL-3.0-or-later. See [`LICENSE`](LICENSE).

## Make targets

`WOW_DIR` is the flavor folder, for example `.../World of Warcraft/_forever_`.

| Target | What it does |
|---|---|
| `make help` | List the targets. |
| `make check-tools` | Report each missing tool (`lua5.1`, `luarocks`, `busted`, `luacheck`, `luacov`, `stylua`, `go`, `fvm`, `curl`, `jq`, `python3`). |
| `make deps` | Install busted, luacov and luacheck with luarocks (Lua 5.1). |
| `make lint` | `lint-lua` (luacheck), `lint-no-go` (`scripts/no-go.sh`: no tracked `*.go`, `go.mod` or `go.sum` outside `server/`; `scripts/no-go_test.sh` tests it), `lint-actions` (actionlint on the workflows, skipped when it is not installed; CI always runs it), `server-lint` (`gofmt` and `go vet` in `server/`), `dart-lint` and `app-lint` (analyze and format check) and `fmt-check` (stylua). |
| `make fmt` | Format the Lua, Dart and Go code. |
| `make test` | `test-lua` (busted), `test-scripts` (the tests of `scripts/package-addons.sh` and `scripts/release-version.sh`), `server-test` (`go test -race` in `server/`), `dart-test` (Dart core tests) and `app-test` (Flutter app tests). |
| `make coverage` | `coverage-lua`, `server-coverage` and `dart-coverage`. The core files (`addons/Memories/Core/`, `addons/Memories/Data/`), `server/internal/...` and the Dart core `lib/` need 80 %; the total Lua coverage is printed. |
| `make server-run` | Run the Go server (see The server). |
| `make server-build` | Build the static server into `build/memories-server`. |
| `make companion` | Run the WoW Journey app on this system. `COMPANION_DEVICE=linux`, `macos` or `windows` picks the device. |
| `make install WOW_DIR=...` | Copy each addon folder into the game. |
| `make link WOW_DIR=...` | Link each addon folder into the game. |
| `make export WOW_DIR=...` | Run `memories-export`; `DIST`, `BACKUP` and `DEFAULT` set `--dist`, `--backup` and `--default`. |
| `make upload SITE=...` | Run `memories-upload`; `LATEST`, `KEY`, `STATE`, `INVITE`, `DELETE` and `REQUEST_SCREENSHOTS=1` set the matching flags. |
| `make e2e` | Build the server, start it on a temporary folder and run `memories-upload` against it: upload, page, merge, screenshot approval and delete (needs `go`, `fvm`, `curl`, `jq` and `python3`; CI runs it). |
| `make local-up` | Build the Docker image and run a test server on `http://localhost:8080` (admin page on `http://localhost:8081`, open registration, data in a Docker volume). `make local-down` deletes it; `make local-logs` follows its log. |
| `make companion-local` | Run the companion app with `http://localhost:8080` as the default website. |
| `make clean` | Remove the coverage files and `app/build/`. |

## Layout

- `addons/` — the 6 addons.
- `packages/memories_core/` — the Dart core (no Flutter) with the `memories-export` and `memories-upload` commands
  (`bin/memories_export.dart`, `bin/memories_upload.dart`); `app/` — the WoW Journey desktop app. Both use the Flutter version in `.fvmrc` through [FVM](https://fvm.app).
- `server/` — the Go web server (its own `go.mod`; the only Go code in the repository).
- `deploy/` — the compose file, Caddyfile and `.env.example` to run the server.
- `spec/` — busted tests and the WoW stub harness (`spec/helpers/wow.lua`); `testdata/` — converter fixtures (`testdata/wow`)
  and their golden output (`testdata/expected`).
- `docs/` — [`kinds.md`](docs/kinds.md), [`public-api.md`](docs/public-api.md),
  [`sub-addon-api.md`](docs/sub-addon-api.md), [`manual-checklist.md`](docs/manual-checklist.md) (the checks to run
  in the game), [`app-manual-checklist.md`](docs/app-manual-checklist.md) (the checks of the app) and
  [`releasing.md`](docs/releasing.md) (how to cut a release) and [`self-host.md`](docs/self-host.md) (run your own
  server).
