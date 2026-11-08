# Manual checklist for the WoW Journey app

The app has no e2e suite, so these checks run by hand. They are the manual Validation steps of
[`specs/2026-11-08-companion-app.md`](../specs/2026-11-08-companion-app.md). Run each one on Windows, macOS and Linux
unless the row names one system.

## How to run

- **Result:** `not run`, `pass`, or `fail: <what happened>`, per system.
- **Task:** the spec task that owns the behavior. Fix a fail in that task.
- **Safe test data:** for checks 1 to 7 and 15, point the app at a copy of a WoW flavor folder, or at the fixture
  `testdata/wow`. The app only reads the WoW folder, but a copy keeps the real one out of reach.
- **Fresh start:** delete `settings.json` in the app support folder to see the wizard again.
  - Linux: `~/.local/share/com.fmartingr.wow_journey/`
  - macOS: `~/Library/Application Support/com.fmartingr.wowJourney/`, or, while the app sandbox is on (until Task
    10), `~/Library/Containers/com.fmartingr.wowJourney/Data/Library/Application Support/com.fmartingr.wowJourney/`
  - Windows: `%APPDATA%\com.fmartingr\wow_journey\`
- **macOS checks 10 and 11:** run them once the app sandbox is off (Task 10). While it is on, the launch agent lands
  in the app container, where the system does not read it, and a second copy may not reach the first one.

## Checks

| # | Task | Check | Windows | macOS | Linux |
|---|---|---|---|---|---|
| 1 | 6 | First start with no settings: the wizard shows. Step 1 shows the found folder, or the picker when none is found. | not run | not run | not run |
| 2 | 6 | Choose a folder with no `WTF/Account`: a plain message shows and the folder is not saved. | not run | not run | not run |
| 3 | 6 | Step 2 shows `Documents/WoW Journey`. Change it to another folder. | not run | not run | not run |
| 4 | 6 | Finish: the main screen shows. Restart: the wizard does not show. | not run | not run | not run |
| 5 | 6 | Click Gather now with a real flavor folder: `latest/` and `backups/<stamp>/` exist, and the counts match `/mem status` in the game. | not run | not run | not run |
| 6 | 6 | Click Gather now again with no new data: no file in `latest/` changes. | not run | not run | not run |
| 7 | 7 | Watch on: log out of the game, or touch a saved file of the copy. The main screen says "Watching for changes". One gather runs within about 15 s (at most 20 s) of the file change. A restart with no change does not gather. Watch off in the settings: a change does not gather. | not run | not run | not run |
| 8 | 8 | Close the window: the app hides to the tray. Open it with Open window in the tray menu. Gather now in the tray menu gathers and the window stays hidden. Open backup folder opens it. macOS: the Dock icon stays while the window is open, and a click on it shows a hidden window. | not run | not run | not run |
| 9 | 8 | Quit from the tray menu: the process ends, and Watch stops (no gather after it). | not run | not run | not run |
| 10 | 8 | Start at login on: the login entry exists (Windows: `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`, value `WoW Journey`; Linux: `~/.config/autostart/WoW Journey.desktop`; macOS: `~/Library/LaunchAgents/com.fmartingr.wowJourney.plist`), with the app path and `--hidden`. Sign out and in: the app starts hidden and the tray shows. Switch it off: the entry is gone. Move the app and start it once: the entry has the new path. | not run | not run | not run |
| 11 | 8 | Start a second copy, also while the first one is hidden or shows the wizard: the first window shows and the second exits. Linux GNOME with no AppIndicator extension: there is no tray icon, closing the window quits, and a start with `--hidden` shows the window. | not run | not run | not run |
| 12 | 10 | macOS only: open the downloaded app. No Gatekeeper warning. `spctl --assess --type execute -vv` says "accepted, notarized". | — | not run | — |
| 13 | 10 | Windows only: open the downloaded zip. Follow the SmartScreen steps in the README. | not run | — | — |
| 14 | 10 | Linux only: unpack the tar.gz and run the binary on a clean machine. | — | — | not run |
| 15 | 4, 6 | Reinstall case: delete the saved files from a copy of the WoW folder, add a new session, gather. Old lines stay in `latest/`. | not run | not run | not run |
| 16 | 6 | Open `latest/` with `make web` and see the map and the tables. | not run | not run | not run |

## Also look at

These go with checks 1 to 6.

- The main screen at its narrowest width (480 px) and with large text (1.5×): no text is cut off.
- With the WoW folder renamed after the wizard, the main screen shows "We cannot find your WoW folder any more" with
  a Choose folder button.
- With the backup folder on a removed drive, Gather now shows a plain message with a Choose backup folder button.
- Tab moves through every control in order; a screen reader reads each button.
