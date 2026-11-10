# Memories documentation

Memories is a set of World of Warcraft addons for WoW Forever (Interface 16001). It records the journey of each
character into the saved files. The WoW Journey app and the converter turn those files into data for a website.

Memories is inspired by the Muddy Boots addon. Memories takes no screenshots of its own; use Paparazzi for that.

## For players

- [Install](install.md) — put the addons in the game.
- [The addons](addons.md) — what each of the 6 addons records, and how other addons write into the journal.
- [Settings and commands](settings.md) — `/mem` commands, options, backups and the data guard.
- [The WoW Journey app](app.md) — the desktop app that gathers and uploads your journey.
- [Journal kinds](kinds.md) — every kind of journal line and its fields.

## Tools and website

- [Converter](converter.md) — `memories-export`, the command line gather.
- [Uploader](uploader.md) — `memories-upload`, send characters to a website.
- [The server](server.md) — the Go web server, its API and its settings.
- [Self-host](self-host.md) — run your own site.

## For developers

- [Development](development.md) — make targets and repository layout.
- [Public API](public-api.md) and [Sub-addon API](sub-addon-api.md).
- [Releasing](releasing.md).
- Manual checks: [game](manual-checklist.md), [app](app-manual-checklist.md), [viewer](viewer-manual-checklist.md).
- The full design is in [`specs/2026-11-06-memories-addon-set.md`](../specs/2026-11-06-memories-addon-set.md).
