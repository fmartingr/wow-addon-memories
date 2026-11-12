# Settings and commands

Back to the [documentation index](README.md).

- `/memories` (or `/mem`) lists the commands.
- `/mem options` (or `/mem settings`) opens the Settings page (Options > AddOns > Memories). Settings are
  account-wide, in `MemoriesDB.settings`:
  - **General:** "Recording rate" of the trail (1, 2, 5 or 10 s; default 2 s), "Save reminder", "Minimap button"
    and "Low-health flash" (all on).
  - **Kinds:** one checkbox per kind under `<addon> — <group>`, with "Enable all" and "Disable all" for each group.
    Every kind is on by default. A kind that is off writes no line, but its counts go on.
  - **New findings only:** Gathering (`ga`, `fs`), Kills (`ki`), Loot (`lo`) and Consumables (`cu`), all off. When a
    box is on, its kinds write a line only for a first finding or a rare one.
- **Journey window:** the choices of the panel are saved per account in `MemoriesDB.settings.map`: `groups` (the
  boxes Level ups, Deaths, Travel and Dungeons, as the groups `Progress`, `Deaths`, `Travel` and `Dungeons`; a group is
  shown unless its entry is `false`), `trail` (on by default), `color` (the colour of the trail: `"way"`, `"level"` or
  `"age"`), `colorblind` (a palette for colour blindness, off by default) and `follow` (the replay moves through the
  maps, on by default). The choice of a session is not saved. When all of Memories is read-only, the choices last for
  the session only.
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
