# Memories

Memories is a set of World of Warcraft addons for WoW Forever (Interface 16001) that records each character's journey:
sessions, travel, deaths, progress and more. A Go converter (`memories-export`) turns the saved files into JSONL files.

The full design is in [`specs/2026-11-06-memories-addon-set.md`](specs/2026-11-06-memories-addon-set.md).

## Layout

- `addons/Memories/` — the core addon.
- `cmd/memories-export/` — the converter.
- `spec/` — busted tests and the WoW stub harness (`spec/helpers/wow.lua`).
- `docs/manual-checklist.md` — the checks to run in the game.

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
