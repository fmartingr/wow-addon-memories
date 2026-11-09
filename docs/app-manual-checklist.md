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
  - macOS: `~/Library/Application Support/com.fmartingr.wowJourney/` for a release build, or, for a debug build
    (`make companion`, app sandbox on),
    `~/Library/Containers/com.fmartingr.wowJourney/Data/Library/Application Support/com.fmartingr.wowJourney/`
  - Windows: `%APPDATA%\com.fmartingr\wow_journey\`
- **macOS checks 10 and 11:** run them on a release build, which has no app sandbox. A debug build keeps the sandbox:
  there the launch agent lands in the app container, where the system does not read it, and a second copy may not
  reach the first one.

## Checks

| # | Task | Check | Windows | macOS | Linux |
|---|---|---|---|---|---|
| 1 | 6 | First start with no settings: the wizard shows. Step 1 shows the found folder, or the picker when none is found. | not run | not run | not run |
| 2 | 6 | Choose a folder with no `WTF/Account`: a plain message shows and the folder is not saved. | not run | not run | not run |
| 3 | 6 | Step 2 shows `Documents/WoW Journey`. Change it to another folder. | not run | not run | not run |
| 4 | 6 | Finish: the main screen shows. Restart: the wizard does not show. | not run | not run | not run |
| 5 | 6 | Click Gather now with a real flavor folder: `latest/` and `backups/<stamp>/` exist, and the counts match `/mem status` in the game. | not run | not run | not run |
| 6 | 6 | Click Gather now again with no new data: no file in `latest/` changes. | not run | not run | not run |
| 7 | 7 | Watch on: log out of the game, or touch a saved file of the copy. The main screen says "Watching for changes". One gather runs within about 15 s (at most 20 s) of the file change. A restart with no change does not gather. Watch off in the Settings tab: a change does not gather. | not run | not run | not run |
| 8 | 8 | Close the window: the app hides to the tray. Open it with Open window in the tray menu. Gather now in the tray menu gathers and the window stays hidden. Open backup folder opens it. macOS: the Dock icon stays while the window is open, and a click on it shows a hidden window. | not run | not run | not run |
| 9 | 8 | Quit from the tray menu: the process ends, and Watch stops (no gather after it). | not run | not run | not run |
| 10 | 8 | Start at login on: the login entry exists (Windows: `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`, value `WoW Journey`; Linux: `~/.config/autostart/WoW Journey.desktop`; macOS: `~/Library/LaunchAgents/com.fmartingr.wowJourney.plist`), with the app path and `--hidden`. Sign out and in: the app starts hidden and the tray shows. Switch it off: the entry is gone. Move the app and start it once: the entry has the new path. | not run | not run | not run |
| 11 | 8 | Start a second copy, also while the first one is hidden or shows the wizard: the first window shows and the second exits. Linux GNOME with no AppIndicator extension: there is no tray icon, closing the window quits, and a start with `--hidden` shows the window. | not run | not run | not run |
| 12 | 10 | macOS only: open the downloaded app. No Gatekeeper warning. `spctl --assess --type execute -vv` says "accepted" and "source=Notarized Developer ID". | — | not run | — |
| 13 | 10 | Windows only: open the downloaded zip. Follow the SmartScreen steps in the README. | not run | — | — |
| 14 | 10 | Linux only: unpack the tar.gz and run the binary on a clean machine. | — | — | not run |
| 15 | 4, 6 | Reinstall case: delete the saved files from a copy of the WoW folder, add a new session, gather. Old lines stay in `latest/`. | not run | not run | not run |
| 16 | 6 | Upload `latest/` to the local test server (`make local-up`, `make upload`) and open the character page. | not run | not run | not run |
| 17 | 11 | Website, check and register: in the Website tab, Check on the default address shows the site name, or a plain message with no network. An address with `http://example.com` shows "must start with https://". With an invite code from the admin page, Register shows "Registered on ..." and the key fingerprint, and the Upload switch can be turned on. A wrong code shows a plain message. | not run | not run | not run |
| 18 | 11 | Website, upload: with Upload on, Gather now uploads. The Website card shows the last upload time and the character link, and the link opens the page with the journey, the trail, the sessions and the counts. Screenshots show "Screenshot not uploaded". While it runs, a progress bar and "Uploading N of M" show. A character with many screenshots (about 80) uploads with no error, even when the website slows it down: the app paces its requests and waits when the website asks. If the website stays busy for 10 minutes, the card says "Upload paused. It continues after the next gather." and shows no error. With Upload off, a gather uploads nothing and Upload now is gone. | not run | not run | not run |
| 19 | 11 | Website, screenshots: Request screenshots shows "Waiting for the website admin". After the admin approves the key, a gather (or Upload now) sends them and they show on the page. | not run | not run | not run |
| 20 | 11 | Website, links and removal: Copy link puts the link on the clipboard. Remove from website asks "Remove <name> from <site>? The page and its data are deleted." Cancel keeps it; Remove makes the link give 404. With Upload on, the next gather does not upload it again (the card says "skipped 1 removed character"); Upload now sends it again. | not run | not run | not run |
| 21 | 11 | Website, blocked key: after "Revoke key" on the admin page, Upload now shows "The website admin blocked this app's key", the Upload switch is off, and turning Upload on again, the next Upload now gives the same message and turns it off. | not run | not run | not run |
| 22 | 11 | macOS debug build (`make companion`, app sandbox on): Check and Register reach the site, so the network client entitlement works. | — | not run | — |
| 23 | 12 | The header shows the crest and the name. The tabs Overview, Website and Settings switch with a click, and with Left and Right when a tab has the focus. The Overview opens first. | not run | not run | not run |
| 24 | 12 | The fonts show (Cinzel capitals in the titles and buttons, Alegreya Sans in the text) and the panels have the gold double border. Compare with the website landing page: `make theme-check` and the review in `.claude/skills/theme-parity`. | not run | not run | not run |
| 25 | 12 | At a narrow window (about 400 px) the tabs drop their icons, nothing overflows, and every control is at least 44 px high. | not run | not run | not run |
| 26 | 12 | A settings message (for example after a damaged `settings.json`) shows above the tabs on each tab. | not run | not run | not run |
| 27 | 5 | Settings has a Language row with System, English, Deutsch, Français, Español, Italiano and Português, each in its own language. System is the default. Choosing a language saves it in `settings.json` (`"language": "<code>"`, `null` for System) and shows after a restart. | not run | not run | not run |
| 28 | 6 | Language: Settings → Language → Español. Every screen, dialog and the tray menu turn Spanish at once, and stay Spanish after a restart. Choose System with the operating system in German: the app is German. Start a second copy while the first one does not answer: the error screen has the chosen language. | not run | not run | not run |
| 29 | 6 | macOS only: set the system language to Deutsch (or Français), start the app: it shows German (or French) with Language on System. | — | not run | — |
| 30 | 6 | German, the longest language: the wizard, the main screen at its narrowest width (480 px) and the Settings tab show no cut-off text, and a long label wraps. | not run | not run | not run |

## Also look at

These go with checks 1 to 6.

- The Website section and card (checks 17 to 21) at 480 px and with large text (1.5×): no text is cut off, and a
  long address and a long error message wrap.
- The main screen at its narrowest width (480 px) and with large text (1.5×): no text is cut off.
- With the WoW folder renamed after the wizard, the main screen shows "We cannot find your WoW folder any more" with
  a Choose folder button.
- With the backup folder on a removed drive, Gather now shows a plain message with a Choose backup folder button.
- Tab moves through every control in order; a screen reader reads each button.
