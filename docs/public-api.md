# Public API

Any addon can write two kinds of lines into the Memories journal of the current character through the global
`Memories`. Memories sub-addons use the handle of `Memories.RegisterModule` instead (see
[`sub-addon-api.md`](sub-addon-api.md)).

| Field | Value |
|---|---|
| `API_VERSION` | `1` |
| `RecordEvent(source, what, detail)` | writes an `ex` line |
| `RecordScreenshot(source, note, file)` | writes an `sn` line |

Check that the call exists first, so the addon also works without Memories:

```lua
if Memories and Memories.RecordScreenshot then
	Memories.RecordScreenshot("Paparazzi", "Level up, Boss kill", "WoWScrnShot_110626_140309.jpg")
end
```

## `Memories.RecordEvent(source, what, detail)`

Writes `ex|source|what|detail` at the player's time, played time and place.

- `source`: the calling addon's name. Required.
- `what`: what happened. Required.
- `detail`: more text. Optional.

## `Memories.RecordScreenshot(source, note, file)`

Writes `sn|source|note|file`. Call it after `SCREENSHOT_SUCCEEDED`. Memories writes its own `ss` line for every saved
screenshot while the player keeps the `ss` kind on; the converter (`memories-export`) adds the note to the `ss` line
with the same `file`, else to the nearest `ss` line within 2 s.

- `source`: the calling addon's name. Required.
- `note`: the text for the screenshot. Required.
- `file`: the file name that the caller predicts, for example `WoWScrnShot_110626_140309.jpg`. Optional. It must match
  `^WoWScrnShot_%d%d%d%d%d%d_%d%d%d%d%d%d%.%a%a%a%a?$`.

The game names a screenshot `WoWScrnShot_` + the local time as `MMDDYY_HHMMSS` + the extension of the
`screenshotFormat` CVar (`jpeg` or `jpg` → `.jpg`, `png` → `.png`, `tga` → `.tga`). The answer can come about 1 s after
the file's own time, so a predicted name can be one second late.

## Input rules

These apply to every argument of both calls:

- A number becomes text with `tostring`. Any other value that is not a string (`nil` aside) is refused, and so is a
  secret value.
- Leading and trailing space and control characters are trimmed. A required argument that is empty after the trim is
  refused. An optional one that is empty is left out.
- Text is cut to a byte limit, never inside a UTF-8 character: `source` 40, `what` 100, `detail` 200, `note` 200,
  `file` 80.
- In the stored line, `|` becomes `/`, and line breaks and other control characters become a space.

## Rate limit

- Each `source` gets 30 accepted calls in each minute (the minutes of `GetTime()`). The 31st call returns
  `false, "rate limit"`; the next minute starts at 0 again. Both calls share the limit of one source.
- A refused call does not count.
- At most 50 sources can be tracked at one time. A call from a new source past that returns `false, "rate limit"`. A
  source is no longer tracked 2 minutes after the start of its last minute.

## Return values

Each call returns `true`, or `false` and one of these reasons:

| Reason | When |
|---|---|
| `"not ready"` | before Memories finishes its `PLAYER_LOGIN` work (a `PLAYER_LOGIN` handler of another addon can run first), or the core stopped at login |
| `"read only"` | the saved data comes from a newer Memories |
| `"off"` | the player turned the kind (`ex` or `sn`) off on the Settings page |
| `"bad source"`, `"bad what"`, `"bad detail"`, `"bad note"`, `"bad file"` | that argument breaks an input rule |
| `"rate limit"` | the source is at its limit, or too many sources are tracked |
| `"error"` | an error inside the call (saved for `/memories errors`), or a call made while another one runs |

A call never raises an error into the caller.
