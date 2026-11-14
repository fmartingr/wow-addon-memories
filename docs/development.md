# Development

Back to the [documentation index](README.md).

## License

GPL-3.0-or-later. See [`LICENSE`](../LICENSE).

The map art in `web/map/` is not under GPL-3.0. Blizzard Entertainment owns it. See
[`web/map/README.md`](../web/map/README.md). A full removal of the art from the repository needs a git history
rewrite.


## Make targets

`WOW_DIR` is the flavor folder, for example `.../World of Warcraft/_forever_`.

| Target | What it does |
|---|---|
| `make help` | List the targets. |
| `make check-tools` | Report each missing tool (`lua5.1`, `luarocks`, `busted`, `luacheck`, `luacov`, `stylua`, `go`, `fvm`, `curl`, `jq`, `python3`). |
| `make deps` | Install busted, luacov and luacheck with luarocks (Lua 5.1). |
| `make lint` | `lint-lua` (luacheck), `lint-no-go` (`scripts/no-go.sh`: no tracked `*.go`, `go.mod` or `go.sum` outside `server/`; `scripts/no-go_test.sh` tests it), `lint-actions` (actionlint on the workflows, skipped when it is not installed; CI always runs it), `server-lint` (`gofmt` and `go vet` in `server/`), `dart-lint` and `app-lint` (analyze and format check) and `fmt-check` (stylua). |
| `make fmt` | Format the Lua, Dart and Go code. |
| `make check` | The addon checks of CI: `lint-lua`, `fmt-check` and `coverage-lua`. Run it before an addon commit. |
| `make test` | `test-lua` (busted), `test-scripts` (the tests of `scripts/package-addons.sh` and `scripts/release-version.sh`), `server-test` (`go test -race` in `server/`), `dart-test` (Dart core tests) and `app-test` (Flutter app tests). |
| `make coverage` | `coverage-lua`, `server-coverage` and `dart-coverage`. The Lua files of `addons/` (without `Libs/`), `server/internal/...` and the Dart core `lib/` need 80 %. |
| `make server-run` | Run the Go server (see [server.md](server.md)). |
| `make server-build` | Build the static server into `build/memories-server`. |
| `make companion` | Run the WoW Journey app on this system. `COMPANION_DEVICE=linux`, `macos` or `windows` picks the device. |
| `make install WOW_DIR=...` | Copy each addon folder into the game. |
| `make link WOW_DIR=...` | Link each addon folder into the game. |
| `make export WOW_DIR=...` | Run `memories-export`; `DIST`, `BACKUP` and `DEFAULT` set `--dist`, `--backup` and `--default`. |
| `make upload SITE=...` | Run `memories-upload`; `LATEST`, `KEY`, `STATE`, `INVITE`, `DELETE`, `ONLY` (paths separated by spaces) and `REQUEST_SCREENSHOTS=1` set the matching flags. |
| `make e2e` | Build the server, start it on a temporary folder and run `memories-upload` against it: upload, page, merge, screenshot approval and delete (needs `go`, `fvm`, `curl`, `jq` and `python3`; CI runs it). |
| `make local-up` | Build the Docker image and run a test server on `http://localhost:8080` (admin page on `http://localhost:8081`, open registration, data in a Docker volume). `make local-down` deletes it; `make local-logs` follows its log. |
| `make companion-local` | Run the companion app with `http://localhost:8080` as the default website. |
| `make web-lint`, `make web-test` | Check the syntax of the viewer modules in `web/`, and run the `node --test` suite of the viewer logic with its coverage threshold (needs Node 24). |
| `make app-viewer` | Copy the viewer files of `web/` into `app/assets/viewer/` (gitignored). `make companion`, `make companion-local`, `make app-test`, `make app-lint` and `make app-shots` run it first. CI and the release jobs run `fvm dart run tool/viewer_assets.dart` in `app/`. |
| `make app-viewer-check` | Fail when `app/assets/viewer/` differs from `web/`, or when a folder of the copy has no entry in `app/pubspec.yaml`. `make lint` runs it. |
| `make web-assets MAP_SRC=...` | Update the map art in `web/map/` from a map art folder. The art is in git; the target keeps `web/map/README.md`. |
| `make clean` | Remove the coverage files and `app/build/`. |


## Layout

- `addons/` — the 6 addons.
- `packages/memories_core/` — the Dart core (no Flutter) with the `memories-export` and `memories-upload` commands
  (`bin/memories_export.dart`, `bin/memories_upload.dart`); `app/` — the WoW Journey desktop app. Both use the Flutter version in `.fvmrc` through [FVM](https://fvm.app).
- `server/` — the Go web server (its own `go.mod`; the only Go code in the repository).
- `deploy/` — the compose file, Caddyfile and `.env.example` to run the server.
- `spec/` — busted tests and the WoW stub harness (`spec/helpers/wow.lua`); `testdata/` — converter fixtures (`testdata/wow`)
  and their golden output (`testdata/expected`).
- `docs/` — [`kinds.md`](kinds.md), [`public-api.md`](public-api.md),
  [`sub-addon-api.md`](sub-addon-api.md), [`manual-checklist.md`](manual-checklist.md) (the checks to run
  in the game), [`app-manual-checklist.md`](app-manual-checklist.md) (the checks of the app) and
  [`releasing.md`](releasing.md) (how to cut a release) and [`self-host.md`](self-host.md) (run your own
  server).
