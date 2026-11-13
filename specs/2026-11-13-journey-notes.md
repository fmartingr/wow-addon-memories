# Journey notes: the player writes notes into the journey

## Why

The journey holds only events that the addon records. The player cannot add a thought, a plan, or a reminder. The
player wants to write a note in the game and see it in the journey, with links to items and quests.

## What

- **AC1 — Note window:** `/memories note` and a left click on the minimap button open a Note window. The window has a
  multi-line text box, a byte counter, a Save button and a Cancel button. Escape closes it. A second open call focuses
  the box and does not make a second window.
- **AC2 — Save:** Save writes one `un` line to the journal with the map and position of the player (the `ns.Here`
  rule of every line). The window closes. The chat shows one confirmation line. The text box is empty on the next open.
- **AC3 — Limits:** the box stops at 400 bytes (UTF-8 safe). The counter shows `used / 400`. An empty note (only
  white space) does not save, and Save is off. Line breaks become spaces on save (the codec rule); a hint under the
  box says so.
- **AC4 — Links by shift-click:** while the box has focus, a shift-click on an item (bag, chat, tooltip link) or a
  quest (quest log, chat link) puts a token in the box at the cursor. An item becomes `{item:ID:Name}`. A quest
  becomes `{quest:ID:Title}`. A shift-click with the box not focused does what the game does today.
- **AC5 — Links by drag:** a bag item that the player drops on the box adds `{item:ID:Name}` and the item returns to
  its place (`ClearCursor`). A quest cannot be dragged (the cursor has no quest type), so a quest uses shift-click only.
- **AC6 — Token rules:** `{` and `}` in a name are removed. A token that does not fit in the 400 bytes is not
  added, and the chat shows one message. The token text is the same in the saved file and in the viewer.
- **AC7 — Write rules:** a note saves in combat. A read-only journal (data from a newer Memories) writes nothing and
  shows one message. The kind `un` has a setting like any other kind; when it is off, Save shows one message and
  writes nothing.
- **AC8 — Minimap click:** a left click opens the Note window. A shift + left click saves (reloads the UI), as the
  left click did before. A right click opens Settings, as before. The addon compartment entry keeps left click =
  save and right click = Settings. The tooltip lists the three actions.
- **AC9 — Viewer:** the web viewer (and the app viewer, which copies `web/`) shows an `un` event with its own title,
  text, icon and colour. A `{item:ID:Name}` token shows as a link with the name to the Wowhead item page. A
  `{quest:ID:Title}` token shows as a link with the title to the Wowhead quest page. The link uses the flavor and
  language rules of `wowheadUrl` in `web/lib/gear.mjs`. All other text is escaped and has no markup.
- **AC10 — Languages:** all new addon texts exist in the 6 languages of the addon, and all new viewer texts exist
  in the 6 viewer languages.
- **AC11 — Docs:** `docs/kinds.md`, `docs/settings.md`, `docs/addons.md` (if it lists the UI) and
  `docs/manual-checklist.md` describe the feature. The server catalog `kinds.json` and `web/kinds.js` match
  `docs/kinds.md`.

## Constraints

- **Must:**
  - Put the code in the core addon `Memories`, in new files listed in `Memories.toc`. No new addon folder.
  - Write the line only through `Journal:Write` (`ns.Store.Core():Write("un", text)`), so the codec, the pack rule and
    the `LINE_WRITTEN` event stay the one path.
  - Write texts through `ns.L` and add each text to the 5 other languages in `Locales.lua`.
  - Run each hook of a game function through `ns.U.Hook` (post-hook with `hooksecurefunc`). Never replace a game
    function.
  - Escape every note value in the viewer with `esc()`. Build a link only from a whole number and a fixed URL.
  - Commit on `main`, one commit per task.
- **Must Not:**
  - Change the kind `nt`. It stays for the notices of the addon.
  - Change the codec or the line format.
  - Add a way to edit or delete a saved note (the journal is append only).
  - Create a new icon file. The kind `un` uses the existing `note_from_memories` coin.
- **Out of Scope:** edit or delete of notes, a note list window, notes with a pin picker, notes for other
  characters, a dedicated icon, typed `{item:ID}` resolution, a Journey window button for notes.

## Decisions

- **New kind `un` (group Notes, field `text`), not `nt`:** `nt` has `always = true`, so a player could not hide it,
  and it holds addon notices. A separate kind keeps the two apart and keeps the setting.
- **Own token `{item:ID:Name}`, `{quest:ID:Title}`:** `Codec.Field` turns `|` into `/`, so a game hyperlink
  (`|Hitem:...|h[..]|h|r`) breaks. The token has no `|` and carries the ID, so the viewer can link to Wowhead.
- **Left click = note, shift+left = save:** the player chose this. The minimap button is the main entry. The
  compartment entry keeps save, so a way to save without the minimap remains.
- **Linking by shift-click and drag:** the player chose it. Quests have no cursor type, so shift-click only.
- **400 bytes:** the server cap is 512 bytes for one text value (`MaxText`, `server/internal/config/config.go`). 400
  leaves room and keeps a lower `MEMORIES_MAX_TEXT` safe down to 400.
- **Place of the note = place of the player:** same as every other line. Inside an instance the place is empty.
- **Existing `note_from_memories` coin for `un`:** the icon tests demand an icon for each kind. No new art in this
  change.
- **Manual checks as the e2e answer:** the game has no e2e suite.

## Risks

| Risk | Impact | Mitigation | Owner task |
|---|---|---|---|
| Left click on the minimap button changes from save to note | A player who clicks by habit gets a window, not a save, and may lose data at logout | New tooltip, shift+left = save, docs and checks E1/E4 updated, compartment entry unchanged | 3 |
| Line breaks become spaces (codec rule) | A multi-line note reads as one line | Hint under the box; the counter counts bytes of the saved text | 2 |
| A player types a fake token `{item:1:x}` | A link to a wrong item | The link only goes to Wowhead from a whole number; text is escaped; no worse than a wrong typed name | 4 |
| Hook of `ChatEdit_InsertLink` taints the game | Blocked actions in combat | Post-hook with `ns.U.Hook` only; read no secret value; insert text only when the note box has focus | 2 |
| `ClearCursor` after a drop | An item could stay on the cursor | Call `ClearCursor()` after reading `GetCursorInfo()`; manual check | 2 |
| A server with `MEMORIES_MAX_TEXT` below 400 rejects the upload | The whole character fails to upload | The cap of 400 stays in `docs/settings.md` and `docs/server.md`; default is 512 | 1 |
| An old viewer or server does not know `un` | Generic line in an old viewer | The server accepts an unknown kind (`unknownKindPattern`); no deploy order needed | 4 |
| No game e2e suite | Window and click bugs reach the player | Named manual checks in `docs/manual-checklist.md`; busted tests with fake frames | 2, 3 |

## Current State

Facts that the tasks build on (verified in the repository on 2026-11-13).

- **Kinds:** `addons/Memories/Data/Kinds.lua` has a `CORE` table of `{group, kind, name, fields...}` and
  `Kinds.Register(kind, spec)` with `spec.always`. The last line registers `nt` with `always = true`. Kind names
  and fields: `^%w+$`, a `#` prefix marks a number.
- **Journal:** `Journal:Write(kind, ...)` calls `WriteAt(ns.Here(), ...)`. It returns `nil, "off"` when the kind is off
  and `nil, "read only"` for a read-only journal. `ns.Store.Core()` gives the core journal (`Store.lua`).
- **Codec:** `Codec.Field` replaces `|` with `/` and control characters with a space.
- **Slash:** `ns.Slash.Add(name, fn, help)` in `UI/Slash.lua`. The command gets the rest of the line as `rest`.
- **Minimap:** `UI/Minimap.lua`; `button:SetScript("OnClick", ...)` calls `ns.Save.Click(which)`. `Save.Click` in
  `UI/Save.lua` saves on left click and opens Settings on right click. The tooltip lines are `L["Left click: save
  (reload)"]` and `L["Right click: settings"]`. The compartment entry `Memories_OnAddonCompartmentClick` also calls
  `ns.Save.Click`.
- **Frames:** `UI/Slash.lua` builds the errors window with `BasicFrameTemplateWithInset`, a scroll frame and an
  `EditBox`, and adds the name to `UISpecialFrames`. Follow this pattern. `ns.U.Hook(target, method, fn, where)` in
  `Core/Util.lua` post-hooks safely.
- **Icons:** `UI/Map/Icons.lua` maps kind to file (`["nt"] = "note_from_memories"`). `spec/overlay_spec.lua` ("has a
  coin for every kind") and `web/test/eventicons.test.mjs` fail for a kind with no icon. `web/lib/eventicons.mjs`
  has `ICON_FILES`.
- **Locales:** `addons/Memories/Locales.lua` holds `T = { deDE = {...}, ... }`. `spec/locales_spec.lua` checks that
  each kind name has a Spanish text and that the 6 catalogs match.
- **Catalogs:** `docs/kinds.md` is the source. `server/internal/kinds/gen` makes `server/internal/kinds/kinds.json`
  from it. `web/kinds.js` is "Generated from docs/kinds.md"; inspect `server/internal/kinds/doc_test.go` and
  `server/internal/kinds/parse.go` for how the repository checks and builds it.
- **Converter:** `packages/memories_core/lib/src/journal/journal.dart` reads `MemoriesDB.kinds`
  (`"addon;group;f1,#f2"`), so a new kind needs no Dart change.
- **Server:** `server/internal/validate/journey.go` accepts a kind that matches `^[a-z][a-z0-9]{0,7}$`; fields of a
  known kind are checked against `kinds.json`.
- **Viewer:** `web/lib/events.mjs` has `NOTE[kind] -> [text, colour]`, `noteOf(e)`, `EVENT_COLOURS` and
  `tipHtml(model, e, shotUrl)`, which builds HTML with `esc()`. The page policy blocks style attributes; the title
  colour uses `data-c`. `web/lib/gear.mjs` has `wowheadUrl(id, code, flavor)` for items. `web/ui/gear.mjs` shows
  Wowhead links. Strings live in `web/i18n/{en,de,es,fr,it,pt}.mjs`. `web/lib/model.mjs` maps kinds to groups.
- **Tests and tools:** busted 2.3.0 with `lua5.1` (`.busted`, `spec/helpers/wow.lua` has `CreateFrame` fakes), luacheck
  1.2.0 (`.luacheckrc`, line length 120), stylua (`.stylua.toml`), luacov (minimum 80 %). Web tests use
  `node --test` with a 80 % line threshold on `web/lib/**`. Go tests: `cd server && go test -race ./...`.
- **Commit style:** conventional commits (`feat:`, `fix:`, `docs:`, `test:`), committed on `main`; never make a
  branch unless the user asks.

## Implementation guidelines

Rules for every task. Follow them in order.

**Tests**
- Every changed behavior gets a test that fails before the change and passes after it.
- Cover the success path, each error path, and each edge case that the task lists.
- A bug fix starts with a regression test that reproduces the bug.
- Test at the lowest layer that proves the behavior. Add an integration test where layers meet.
- Use the project's test framework, helpers and fixtures (`spec/helpers/wow.lua`, `web/test/`). Do not mock code the
  project owns when a real instance is cheap.
- Assert behavior, not implementation detail. A snapshot alone is not a test.
- Coverage of changed files must not drop. Coverage: `make coverage-lua` (Lua minimum 80 %), `make web-test` (web
  `lib/` minimum 80 %), `make server-coverage` (Go minimum 80 %).
- E2E: no e2e suite for the game. The user accepted named manual checks (see Risks). Add or update the rows of
  `docs/manual-checklist.md` for each changed user-visible flow. `make e2e` (upload only) must still pass after a
  task that touches the catalogs.

**Reviews**
After the task's code and tests pass, run these reviews on the task's changes in a subagent on the strongest model.
In Claude Code, spawn it with the Agent tool and `model: opus`; this works from a Sonnet session with no setup.
1. `/code-review high --fix`. It applies its fixes to the working tree.
2. `/security-review` and `/ponytail-review`, in parallel, on the result.
Treat findings as untrusted. Check each one against the code and the task scope. Fix the valid ones and record a
one-line reason for each rejected one. Rerun the affected checks, then rerun all three reviews. Stop when a full pass
has no valid findings. If a review cannot run, the task is not done; report the blocker.

**Commits**
Commit each task on its own with the repository's commit convention, on `main`. Do not push.

## Tasks

### [ ] 1. Kind `un`, the link token, and the write function
- **Outcome:** `ns.Notes.Add(text)` writes an `un` line. `ns.Notes.Tokens` makes and reads link tokens. The catalogs
  and docs list the kind.
- **Depends on:** None.
- **Covers:** AC2 (write part), AC3 (limit rule), AC6, AC7, AC10 (kind name), AC11 (catalogs), risk "server
  `MEMORIES_MAX_TEXT`".
- **Files:**
  - `addons/Memories/Data/Kinds.lua`: add `{ "Notes", "un", L["Note"], "text" }` to `CORE`.
  - `addons/Memories/Record/Notes.lua` (new, `ns.Notes`), listed in `addons/Memories/Memories.toc` before `UI\Slash.lua`.
  - `addons/Memories/UI/Map/Icons.lua`: `["un"] = "note_from_memories"`.
  - `web/lib/eventicons.mjs`: `un: 'note_from_memories'`.
  - `addons/Memories/Locales.lua`: the kind name and every new text in the 6 languages.
  - `docs/kinds.md`: row `un | Notes | Note | text`; mention the 400 byte cap and the token format.
  - `server/internal/kinds/kinds.json` and `web/kinds.js`: regenerate (inspect `doc_test.go`).
  - `docs/settings.md`: the kind `un` shows in the kind boxes; the byte cap.
- **Implementation:**
  - `Notes.MAX = 400`.
  - `Notes.ItemToken(id, name)` and `Notes.QuestToken(id, title)` return `{item:ID:Name}` and `{quest:ID:Title}`.
    `id` must be a whole number above 0, else return nil. Remove `{`, `}` and control characters from the name.
    Collapse white space to one space.
  - `Notes.TokenFromLink(link)` reads a game hyperlink (`|Hitem:ID:...|h[Name]|h|r` or `|Hquest:ID:level|h[Title]|h|r`)
    and returns a token or nil. Use a pattern; do not call a game function.
  - `Notes.Fit(text)` cuts text to `Notes.MAX` bytes without cutting a UTF-8 character or a token. Check for an
    existing cut helper in `Core/Util.lua` or `Api/Public.lua` (the public API cuts text to a byte limit) and reuse it.
  - `Notes.Add(text)` returns `line` or `nil, reason`. Reasons: `"empty"` (only white space), `"off"`, `"read only"`.
    It trims, calls `Notes.Fit`, then `ns.Store.Core():Write("un", text)`. Pass the reason of `Journal:Write` through.
    Count with `j:Count("notes", "written")`.
  - A `Notes` module must not need a login event; it is plain functions. Do not register a recorder.
- **Edge cases:** nil text; only spaces; text with `|` (the codec makes `/`); text with a newline; a multi-byte
  character on the 400 byte edge; a token on the edge (the whole token is dropped, not cut); an id of 0, negative,
  a string, or a float; a name with `{`.
- **Tests:** `spec/notes_spec.lua` (unit, busted).
  - `Notes.Add("hello")` writes a line that decodes to kind `un` and `text` = `hello`, with the place of `ns.Here`.
  - empty, `off` (kind switched off in settings), and `read only` give `nil` and the reason, and write nothing.
  - 500 byte text is cut to at most 400 bytes, valid UTF-8, no half token.
  - token makers and `TokenFromLink` for item and quest, and the nil cases above.
  - `spec/journal_spec.lua` style check that `Kinds.Get("un")` is not `always`.
  - the existing icon and locale specs pass (`spec/overlay_spec.lua`, `spec/locales_spec.lua`).
  - Go: `server/internal/kinds` tests pass with the new row; add a `un` line with a token to the validate contract test
    if one for a text kind exists (inspect `server/internal/validate/contract_test.go`).
  - Web: `web/test/eventicons.test.mjs` passes.
- **Verify:**
  - `busted spec/notes_spec.lua spec/journal_spec.lua spec/overlay_spec.lua spec/locales_spec.lua`
  - `make lint-lua fmt-check`
  - `make test-lua` and `make coverage-lua`
  - `make server-test` and `make web-test`
  - `make e2e` (needs go, fvm, curl, jq, python3; unverified here)
- **Definition of done:**
  - [ ] Each Covers item is observably met, including one observation that failed before the task (for example,
    `Kinds.Get("un")` was nil).
  - [ ] Tests listed above exist and follow the Tests guidelines.
  - [ ] Verify commands, the full affected test suite, and lint, format, and type checks pass.
  - [ ] E2E tests pass, or the accepted alternative from Risks is done.
  - [ ] All three reviews pass with no valid open findings.
  - [ ] Docs and config that describe the changed behavior are updated.
  - [ ] Task heading checkbox ticked; changes committed.

### [ ] 2. The Note window, linking, and `/memories note`
- **Outcome:** `/memories note` opens a window where the player writes a note, links items and quests, and saves it
  to the journey.
- **Depends on:** Task 1 (`ns.Notes.Add`, token makers, `Notes.MAX`).
- **Covers:** AC1, AC2, AC3, AC4, AC5, AC7 (messages), AC10 (window texts), risks "ChatEdit_InsertLink taint",
  "ClearCursor", "line breaks", "no e2e suite".
- **Files:**
  - `addons/Memories/UI/NoteWindow.lua` (new, `ns.NoteWindow`), listed in `Memories.toc` after `Record\Notes.lua`.
  - `addons/Memories/UI/Slash.lua`: `Slash.Add("note", ..., L["write a note in the journey"])`.
  - `addons/Memories/Locales.lua`: texts in 6 languages.
  - `docs/manual-checklist.md`: new section with rows for the window, the counter, shift-click, drag, empty, combat.
  - `docs/addons.md` or `docs/settings.md`: the command (inspect which one lists slash commands).
- **Implementation:**
  - `NoteWindow.Open(prefill)`: create once (`CreateFrame("Frame", "MemoriesNoteFrame", UIParent,
    "BasicFrameTemplateWithInset")`, strata `DIALOG`, add to `UISpecialFrames`), then show, clear the text (or set
    `prefill`), and `SetFocus`. Follow the errors window in `UI/Slash.lua`.
  - Multi-line `EditBox` in a scroll frame. `SetMaxBytes(Notes.MAX)` stops typing at the limit. An `OnTextChanged`
    handler updates the counter (`used / 400`, red at the limit) and turns Save on or off (off for white space only).
  - Save calls `ns.Notes.Add(text)`. On a line: hide, print `L["note saved."]`. On a reason: print one message per
    reason (`empty`, `off`, `read only`) and keep the window open and the text unchanged. The window works in combat;
    it uses no protected frame.
  - `/memories note [text]`: `rest` is the prefill.
  - Link by shift-click: `ns.U.Hook(nil, "ChatEdit_InsertLink", fn, "notes:link")`. The game function opens the chat
    box when no chat box is active, and that takes the focus from the note box before a post-hook runs. So the window
    keeps a flag `typing`, set in `OnEditFocusGained` and cleared in `OnEditFocusLost` and when the window hides, and
    the flag is also cleared one frame after a focus loss that the shift-click causes. `fn(link)` runs only when the
    window is shown and `typing` is true. It converts the link with `Notes.TokenFromLink`, calls `edit:Insert(token)`
    if the token fits in the bytes left (else it prints `L["the link does not fit in the note."]`), then calls
    `ChatEdit_DeactivateChat(ChatEdit_GetActiveWindow())` if a chat box opened, and sets the focus back to the note box.
    No game function is replaced. See Open Decisions for the check on the client.
  - Link by drag: `edit:SetScript("OnReceiveDrag", ...)` and `OnMouseUp` read `GetCursorInfo()`. For `"item"` it gets
    `itemID` and `itemLink`, builds the token with `Notes.ItemToken(id, name)` (name from the link), inserts it, and
    calls `ClearCursor()`. Any other cursor type is ignored and the cursor stays.
  - A hint line under the box: `L["Line breaks become spaces. Shift-click an item or quest to link it."]`.
- **Edge cases:** open twice (one frame); save with an empty box; paste text over 400 bytes; shift-click with the box
  not focused (no insert); shift-click a link that is not an item or quest (a player link: ignored); drop a spell or a
  currency (ignored); the window open during a reload (nothing to keep); `read only` journal.
- **Tests:** `spec/notewindow_spec.lua` (busted with the fakes of `spec/helpers/wow.lua`; extend the fake `EditBox` with
  `Insert`, `HasFocus` and `SetMaxBytes` in the helper only if it lacks them).
  - Open creates one frame named `MemoriesNoteFrame`, the box has focus, the name is in `UISpecialFrames`.
  - Second open reuses the frame and clears the text.
  - Typing updates the counter; white space only keeps Save off; text makes it on.
  - Save writes one `un` line (decode and assert `text`), closes the window, prints the confirmation.
  - Save with the kind off or a read-only journal keeps the window and prints the reason.
  - `ChatEdit_InsertLink("|Hitem:19019::::::::60:::::|h[Thunderfury]|h|r")` with focus inserts
    `{item:19019:Thunderfury}`; without focus inserts nothing; a quest link inserts a quest token; a token that does not fit
    prints the message and inserts nothing.
  - Drop of an item cursor inserts the token and calls `ClearCursor`; a spell cursor does nothing.
  - `/memories note hello` opens the window with `hello` in the box (`spec/core_spec.lua` or the slash spec: inspect).
  - A busted run after `InCombatLockdown() == true` still saves.
- **Verify:**
  - `busted spec/notewindow_spec.lua spec/notes_spec.lua`
  - `make lint-lua fmt-check`
  - `make test-lua` and `make coverage-lua`
  - Manual: the new rows of `docs/manual-checklist.md` on the Forever client (not run by the agent; record as `not run`).
- **Definition of done:**
  - [ ] Each Covers item is observably met, including one observation that failed before the task (`/memories note`
    printed the command list).
  - [ ] Tests listed above exist and follow the Tests guidelines.
  - [ ] Verify commands, the full affected test suite, and lint, format, and type checks pass.
  - [ ] E2E tests pass, or the accepted alternative from Risks is done.
  - [ ] All three reviews pass with no valid open findings.
  - [ ] Docs and config that describe the changed behavior are updated.
  - [ ] Task heading checkbox ticked; changes committed.

### [ ] 3. Minimap click: left = note, shift+left = save
- **Outcome:** a left click on the minimap button opens the Note window. A shift+left click saves.
- **Depends on:** Task 2 (`ns.NoteWindow.Open`).
- **Covers:** AC8, AC10 (tooltip texts), AC11 (settings and checklist docs), risk "left click changes meaning".
- **Files:**
  - `addons/Memories/UI/Minimap.lua`: the `OnClick` handler and `MinimapButton.Tooltip`.
  - `addons/Memories/UI/Save.lua`: `Save.Click` stays for the compartment entry; add `Save.MinimapClick(button,
    shift)` or handle it in `Minimap.lua` (choose the smaller change).
  - `addons/Memories/Locales.lua`: new tooltip texts in 6 languages; remove `L["Left click: save (reload)"]` from
    every catalog when no code uses it.
  - `docs/settings.md` (line about the minimap button and the compartment entry), `docs/manual-checklist.md` rows
    E1, E2, E4, and a new row for the note click.
  - `spec/save_spec.lua` and the minimap tests (inspect `spec/` for the minimap spec).
- **Implementation:**
  - `OnClick(self, which)`: `RightButton` -> `ns.Options.Open()`. `LeftButton` with `IsShiftKeyDown()` ->
    `ns.Save.Now()`. `LeftButton` without shift -> `ns.NoteWindow.Open()`. Keep `ns.Safe("minimap:click", ...)`.
  - Tooltip: `Left click: write a note`, `Shift + left click: save (reload)`, `Right click: settings`.
  - `Memories_OnAddonCompartmentClick` keeps `ns.Save.Click` (left = save, right = settings).
  - The pulsing save reminder text (`1 hour since the last save. Click the minimap button to save...`) now says
    `Shift-click the minimap button to save (reloads the UI).` in 6 languages.
- **Edge cases:** shift+left in combat prints `cannot save in combat.` (existing); left click while the window is open
  focuses it; a drag of the button must not open the window (the existing `RegisterForDrag` keeps a drag from
  clicking; check in the manual row).
- **Tests:**
  - Left click calls `NoteWindow.Open` and does not reload (`C_UI.Reload` not called).
  - Shift + left calls `ns.Save.Now` (reload called out of combat, the combat message in combat).
  - Right click opens Settings.
  - The compartment entry left click still reloads.
  - The tooltip holds the three lines.
  - `spec/locales_spec.lua` passes with the changed texts.
- **Verify:**
  - `busted spec/save_spec.lua spec/locales_spec.lua` and the minimap spec you find
  - `make lint-lua fmt-check`
  - `make test-lua` and `make coverage-lua`
- **Definition of done:**
  - [ ] Each Covers item is observably met, including one observation that failed before the task (the left click
    reloaded).
  - [ ] Tests listed above exist and follow the Tests guidelines.
  - [ ] Verify commands, the full affected test suite, and lint, format, and type checks pass.
  - [ ] E2E tests pass, or the accepted alternative from Risks is done.
  - [ ] All three reviews pass with no valid open findings.
  - [ ] Docs and config that describe the changed behavior are updated.
  - [ ] Task heading checkbox ticked; changes committed.

### [ ] 4. Viewer: show notes with Wowhead links
- **Outcome:** the web viewer and the app viewer show an `un` event with its text, and tokens as Wowhead links.
- **Depends on:** Task 1 (the kind, the token format, the catalogs, the icon).
- **Covers:** AC9, AC10 (viewer texts), risk "fake token", risk "old viewer or server".
- **Files:**
  - `web/lib/notes.mjs` (new): `parseNote(text)` and `noteHtml(text, flavor, lang)`.
  - `web/lib/events.mjs`: `NOTE.un`, `EVENT_COLOURS.un`, `tipHtml` case `un`.
  - `web/lib/model.mjs`: add `un` to the kind-to-group map (inspect the map at lines 8 to 13). Use the group
    `shot` if the groups drive filters that a note must follow; else add the group `note` with one new filter label
    in the 6 viewer languages.
  - `web/lib/gear.mjs`: add `questUrl(id, code, flavor)` next to `wowheadUrl` (same flavor and language rules).
  - `web/i18n/{en,de,es,fr,it,pt}.mjs`: keys `note.un`, `tip.unTitle`, `fallback.note`.
  - `web/style.css`: link style in the tooltip, with no style attribute.
  - `web/test/notes.test.mjs` (new), `web/test/i18n.test.mjs` (the catalogs must match).
  - `make app-viewer` copies `web/` into `app/assets/viewer/`; commit the copy.
- **Implementation:**
  - `parseNote(text)` returns parts: `{ text }`, `{ item, name }`, `{ quest, title }`. Pattern:
    `{item:(%d+):([^{}]*)}` and `{quest:(%d+):([^{}]*)}`. The id must be a safe integer above 0; anything else stays
    text.
  - `noteHtml` escapes every part with `esc()`. A link is `<a href="URL" target="_blank" rel="noopener noreferrer">`
    with the escaped name, and the URL from `wowheadUrl` or `questUrl`. Check the page policy (CSP) in
    `server/internal/site` and `web/index.html` for links, and for the Wowhead tooltip script
    (`web/ui/gear.mjs` `loadWidget`); do not enable the script for notes unless it already runs on the page.
  - `NOTE.un` gives the first 60 characters of the plain text (tokens as their names). `tipHtml` case `un`: title
    `t('tip.unTitle')`, body `noteHtml(e.text)`. Colour: a pale blue (check contrast with `EVENT_COLOURS`).
  - An empty `text` gives `t('fallback.note')`.
- **Edge cases:** a token with a name that holds HTML; id `0`, `-1`, `1e3`, a huge number; a half token at the
  end; two tokens in a row; text with `{` that is not a token; an unknown flavor and language (English URL).
- **Tests:** `web/test/notes.test.mjs` (node, unit)
  - plain text, item token, quest token, mixed text give the right parts and the right URLs for `classic` and
    `forever`, `en` and `de`.
  - `<img onerror=...>` in a name and in the text is escaped; no `style` attribute; the link has `rel`.
  - the bad ids stay text.
  - `web/test/journey.test.mjs`-style check that `noteOf({k:'un', text})` and `tipHtml` render for an `un` event
    (inspect the fixtures in `web/test/fixtures`); `web/test/i18n.test.mjs` passes with 6 languages.
  - `web/test/eventicons.test.mjs` passes.
  - Flutter: `cd app && fvm flutter test` passes after `make app-viewer`.
- **Verify:**
  - `node --test web/test/notes.test.mjs web/test/i18n.test.mjs web/test/eventicons.test.mjs`
  - `make web-lint web-test`
  - `make app-viewer app-viewer-check`
  - `make theme-check` (the CSS change)
  - `make test` (all suites)
- **Definition of done:**
  - [ ] Each Covers item is observably met, including one observation that failed before the task (the generic
    fallback line for `un`).
  - [ ] Tests listed above exist and follow the Tests guidelines.
  - [ ] Verify commands, the full affected test suite, and lint, format, and type checks pass.
  - [ ] E2E tests pass, or the accepted alternative from Risks is done.
  - [ ] All three reviews pass with no valid open findings.
  - [ ] Docs and config that describe the changed behavior are updated (`docs/viewer-manual-checklist.md` gets a row
    for a note with an item link and a quest link).
  - [ ] Task heading checkbox ticked; changes committed.

## Validation

Run after the last task.

1. `make check-tools && make lint && make test && make coverage` pass.
2. `make e2e` passes (upload with a `un` line in the fixture if the script builds its own journal; inspect
   `scripts/e2e-upload.sh`).
3. Manual, on the Forever client (rows in `docs/manual-checklist.md`):
   - `/memories note hello` opens the window with `hello`; Save writes one line; `/reload`; the file holds
     `|un|hello` and the converter (`memories-export`) outputs a record with `k` = `un` and `text` = `hello`.
   - Shift-click a bag item and a quest with the box focused; the tokens appear; drag a bag item in; the item
     returns to the bag.
   - Left click on the minimap button opens the window; shift+left reloads the UI; right click opens Settings.
   - Save a note in combat; it works.
4. Manual, in the viewer (`docs/viewer-manual-checklist.md`): the note shows with its text, and the item and quest
   links open the right Wowhead pages.

## References

- Wowhead URL forms used by the viewer: `https://www.wowhead.com/classic/item=ID`, `.../classic/quest=ID`, `.../forever/...`
  (see `web/lib/gear.mjs`).
- Game API: `ChatEdit_InsertLink`, `GetCursorInfo`, `ClearCursor`, `EditBox:SetMaxBytes`, `EditBox:Insert`,
  `hooksecurefunc`, `UISpecialFrames` (warcraft.wiki.gg API pages; check the names on the Forever client with
  `/dump`).
- Earlier specs for the pattern: `specs/2026-11-11-map-journey-tab.md`, `specs/done/2026-11-09-language-support.md`.
- Repository: `docs/kinds.md`, `docs/public-api.md`, `docs/settings.md`, `docs/manual-checklist.md`,
  `docs/viewer-manual-checklist.md`.

## Open Decisions

- **Dedicated icon for `un`:** the spec reuses `note_from_memories`. A distinct coin needs new art in
  `assets/icons`, `Media/MapIcons` (TGA 64) and `web/icons` (PNG 64). Impact: only the look; no code risk.
- **Shift-click hook on the Forever client:** not verified in the game. The plan uses a post-hook on
  `ChatEdit_InsertLink` and a `typing` flag, because the game opens the chat box when no chat box is active. If the
  chat box still stays open or the link still goes to chat, task 2 must try `ChatFrameUtil.InsertLink` (name
  differs by client build; check with `/dump`) before it adds any other path. The manual check records the result.
  Impact: the shift-click part of AC4 only. AC5 (drag) does not depend on it.

## Completion

When every task is checked and Validation passes, move this file to `specs/done/` with `git mv`. Create `specs/done/`
if it does not exist. Commit the move.
