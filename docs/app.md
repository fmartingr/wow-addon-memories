# The WoW Journey app

Back to the [documentation index](README.md).

`app/` is a desktop app (Windows, macOS, Linux) that runs the converter for you. Download it from a
[GitHub release](https://github.com/fmartingr/wow-addon-memories/releases), or start it from the repository with `make companion`. A Linux build needs
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

Releases are cut as described in [`releasing.md`](releasing.md).

- **First start:** a 3-step wizard. Step 1 finds the WoW folder (or opens a folder picker), step 2 sets the backup
  folder (default `<Documents>/WoW Journey`), step 3 has the Watch and Start at login switches (both on).
- **Look:** the app has the look of the website: a dark theme, gold double borders, Cinzel capitals and Alegreya Sans. The
  tokens come from `web/base.css`; `make app-theme` writes them to `app/lib/src/theme/tokens.dart`, and `make
  theme-check` compares the two themes (see `.claude/skills/theme-parity`).
- **Main window:** a header and three tabs at the top: Overview, Website and Settings. A message about the settings
  file shows above the tabs.
- **Overview:** the last gather time, a Gather now button, the counts (characters, journal lines, screenshots), the
  characters, each problem in plain words with a fix button, the size of the backup folder, and Open backup folder
  and Open latest data.
- **Settings tab:** change the WoW folder or the backup folder (the old backup folder stays as it is), the two
  switches and the version.
- **Website tab:** the Registration panel has the website address (default `https://wowjourney.xyz`; only
  `https://`, or `http://` for `localhost`, `127.0.0.1` and `[::1]`), a Check button, the registration (an invite code,
  or one click on a website with open registration), the Upload switch (off by default, and it stays off until the key
  is registered), Request screenshots, and the key fingerprint with a Copy button and Make a new key. With Upload on, the app sends the journey of the ticked characters after each
  gather. The Website panel above it lists every character of the backup folder with a box: you choose which
  characters to upload (Select all and Select none help), and until you tick one the card says "Choose the characters
  to upload." and Upload now is disabled. A character gathered later is not uploaded until you tick it. The choice is
  kept for each website in `upload-state.json`. Unticking a character only stops later uploads; the page stays on the
  website. Each uploaded character shows its link with Copy link and Remove from website, which deletes the page and
  unticks the character. Character pages are unlisted: anybody with the link can open them. The
  key is `upload-key.json` and the state `upload-state.json`, in the app support folder; after a reinstall the website
  admin moves your characters to the new key. Make a new key is for a key that the website blocked or refused: it
  keeps the old key as `upload-key.<UTC time>.json` next to it, makes a new one, turns Upload off and forgets every
  registration, so you register again and the app sends the ticked characters again. A build can set another default address with
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
- The backup folder holds `latest/` (the website data, the `dist-characters/` layout in [Converter](converter.md)) and `backups/<UTC stamp>/`.
- Manual checks: [`app-manual-checklist.md`](app-manual-checklist.md).
