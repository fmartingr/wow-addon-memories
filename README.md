# Memories

<p align="center">
  <img src="assets/icon.png" alt="Memories icon" width="128">
</p>

**Memories** records the journey of each of your World of Warcraft characters. For WoW Forever (interface 16001).

## Features

- **Journey record:** the core addon writes down sessions, the position trail, levels, quests, discoveries, deaths,
  close calls, travel, dungeons and bosses, and screenshots.
- **Sub-addons:** `Memories_Combat`, `Memories_Gathering`, `Memories_Character`, `Memories_Economy` and
  `Memories_Social` record kills, gathering, skills, loot, money, groups, PvP and more. Turn one off in the AddOn
  list to stop its recording. See [The addons](docs/addons.md).
- **Journey window:** a button under the side tabs of the world map opens a replay of the journey on a map of its own.
- **Notes:** `/memories note` or a left click on the minimap button writes a note in the journey, with item and
  quest links.
- **Save reminder:** after 1 hour without a reload, a chat line and a pulse of the minimap button remind you to save.
- **Data guard:** each journal has a rolling backup. When a journal loads empty and its backup has lines, a popup
  asks you to restore the backup or start fresh.
- **WoW Journey app:** a desktop app turns the record into a web page that you can share, for example
  [Neral Brumamar (EU PvP)](https://wowjourney.xyz/forever/eu/brumamar/neral/#summary). See [the app](docs/app.md).

## Install

- CurseForge: https://www.curseforge.com/wow/addons/memories
- From a [GitHub release](https://github.com/fmartingr/wow-addon-memories/releases): unpack
  `Memories-addons-<version>.zip` into `Interface/AddOns` of the flavor folder.
- From the repository:

  ```
  make link WOW_DIR="/path/to/World of Warcraft/_forever_"
  ```

  Use `make install` to copy the 6 addon folders instead of a link. See [Install](docs/install.md).

## Commands

`/memories` and `/mem` are the same command.

- `/memories` or `/memories help` lists all commands.
- `/memories note [text]` opens the Note window.
- `/memories options` or `/memories settings` opens the settings page.
- `/memories status` shows the state of each Memories addon.
- `/memories errors` shows the saved errors in a box, ready to copy.
- `/memories minimap` shows or hides the minimap button.
- **Minimap button and addon compartment:** a left click writes a note, shift + left click saves (reloads the UI),
  and a right click opens the settings page. A drag moves the button.

## Settings

The settings page has the trail recording rate, the save reminder, the low-health flash and the minimap button, and a
checkbox for each kind of line. See [Settings and commands](docs/settings.md).

## Works with

- **[Paparazzi](https://www.curseforge.com/wow/addons/paparazzi)** (optional): Memories takes no screenshots of its
  own. Paparazzi takes them, and Memories records each shot with the reason that Paparazzi gives.

## Limits

- **SavedVariables:** the game writes them on logout or `/reload` only. A client crash loses the changes since then.
  The save reminder and shift + left click on the minimap button help with this.
- **Journey window:** it only reads the saved data. It records nothing, and it changes no game map function.

## Languages

enUS (also enGB), deDE, esES (also esMX), frFR, itIT, ptBR. Other locales use enUS.
The translations are machine translated. No native speaker reviewed them. Corrections are welcome.

## Development

`make deps`, then `make check` (luacheck, StyLua, busted with coverage). `make help` lists the targets.
The checks to run in the game are in [`docs/manual-checklist.md`](docs/manual-checklist.md).

The repository also holds the WoW Journey app, the website server and the viewer. All documentation is in
[`docs/`](docs/README.md), for example [Development](docs/development.md) and
[Self-host a website](docs/self-host.md).

## Release

1. Add a `## X.Y.Z` section at the top of `CHANGELOG.md` and push it to `main`.
2. Run `make release-patch`, `make release-minor` or `make release-major`. `DRY_RUN=1` prints the next tag only.
3. The tag starts `.github/workflows/release.yml`. It builds the addon zip and the app, creates the GitHub release,
   and the packager uploads the addons to CurseForge. See [Releasing](docs/releasing.md).

The CurseForge page text is in `.curse/description.md`.

## License

GPL-3.0-or-later, see [`LICENSE`](LICENSE). The bundled libraries keep their own licenses in
`addons/Memories/Libs/LICENSES.txt`.
