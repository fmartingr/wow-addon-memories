# Merge fixture

`old/` is the data that a server (or an earlier gather) holds. `fresh/` is a new upload or gather of the same character. `expected/` is their merge. Both ports read these folders and must write the bytes of `expected/`:

- Dart: `packages/memories_core/test/gather/merge_contract_test.dart`
- Go: `server/internal/merge/merge_test.go`

`expected/` is made by the Dart functions. To remake it after a deliberate change, run `UPDATE=1 fvm dart test test/gather/merge_contract_test.dart` in `packages/memories_core`, read the diff, and keep the Go port equal.

Each folder holds `character.json`, `journey.jsonl` and `trail.jsonl` in the stored form, so each passes the Go validator. Times are Unix seconds from `1793529000`; `T` below is `1793530000`.

## Records

| Case | Where |
|---|---|
| A record in both lists appears once | `in` and `pc` at `T` |
| A record twice in old and once in fresh is kept twice | `zo` at `T+100` |
| A fresh record with no screenshot takes the screenshot and the notes of its old copy | `ss` at `T+150` |
| An `sn` of fresh is dropped when the old `ss` already carries its note within 2 s | `sn` at `T+201` (old `ss` at `T+200`) |
| An `sn` more than 2 s away stays, and so does an `sn` with no old copy | `sn` at `T+204` and `T+260` |
| A fresh screenshot that old lacks stays | `ss` at `T+250` |
| A record only in old stays | `lv` at `T+280`, `zo` at `T-100` |
| A record only in fresh is added | `pl` at `T+5000`, `ex` at `T+10400`, the session 3 records |
| Records with the same time follow the order of fresh | `ki`, `ga` at `T+10010` (old has `ga`, `ki`) |
| A record that falls in no session has `session: null` | `zo` at `T-100`, `pl` at `T+5000` |
| The session of each record comes from the merged sessions, not from the files | every record |
| Text with `<`, `>` and `&` is written as it is, and a fractional `x` keeps its digits | `zo` at `T+20100`, `ga` at `T+10010` |

## Trail

| Case | Where |
|---|---|
| A chunk that grew: the larger `n` wins | chunk at `T+10` (2 points in old, 4 in fresh) |
| A tie goes to fresh | chunk at `T+10020` (its point changed) |
| A chunk with a null session is sorted by time | chunk at `T-1000` (old only) |
| A chunk only in fresh is added | chunk at `T+20010` |

## Character

| Case | Where |
|---|---|
| The fresh document wins, so `level` is 11 | `character.json` |
| A session with a later `last` wins | the session at `T+10000` (`last` grows in fresh) |
| A session with an earlier `last` loses | the session at `T` (old keeps `last` `T+300`) |
| A session only in fresh is added; its `tz` is null | the session of computer `d4e5f6` |
| An addon entry only in old stays | `Memories_Combat` |
| The fresh addon entry wins | `Memories` (`writtenBy` 0.2.0) |
| An addon entry only in fresh is added | `Memories_Gathering` |

## Notes on the form

- A note read back from a file is a plain map in Dart and would be written with its keys sorted (`note`, `source`). The server's validator writes `source`, `note` for every note, so the Dart test turns each note into a `Note` before the merge. The Dart gather writes the sorted form only for a note that it carries from an earlier run.
- A number keeps its source text in Go and is formatted by Dart. The fixture holds only numbers that both write alike.
