# Upload backend: publish the journey to a website

## Why

The WoW Journey app gathers each character's journey into `latest/` on the player's disk. Players cannot share it. The viewer in `web/` only runs on a local folder.

This spec adds a website and a backend service:

1. The player uploads the data from the app, with as few steps as possible.
2. Each character gets a direct link, `/<flavor>/<region>/<realm>/<name>/`. The site has no list of characters and no search.
3. The server signs nothing on behalf of the player. It checks who sent each upload (a key signature) and checks every record (strict validation), so junk, malformed JSON and changed strings do not get in.
4. By default the server takes the journey data only. Screenshots need a manual approval from the admin.
5. The home page explains the addon set and links to the downloads on GitHub.
6. Anybody can run their own server. The app lets the player choose the target website.

## What

A Go server in `server/`, an upload client and CLI in the Dart core, the upload screens in the app, a single-character mode of the `web/` viewer, and a Docker deployment.

Acceptance criteria:

- **AC1 — Home page:** `GET /` shows a page that explains Memories and WoW Journey, lists the 6 addons, says that a character page is unlisted (not private), and links to the GitHub releases (`MEMORIES_GITHUB_URL` + `/releases/latest`) and the repository.
- **AC2 — Direct link only:** `GET /<flavor>/<region>/<realm>/<name>/` shows the viewer for one character. No page lists characters. `robots.txt` disallows all paths except `/`. Every character page and data file has `X-Robots-Tag: noindex, nofollow`. An unknown path, and the path of a deleted character, give the same 404 page.
- **AC3 — Key identity:** The app makes an Ed25519 key pair once and keeps the private key on the disk. Every API request that changes data has a valid signature of that key. A request with a bad signature, a time more than 300 s off, or a nonce seen before gets `401`.
- **AC4 — Registration:** With `MEMORIES_REGISTRATION=invite` (default), a key registers with a single-use invite code that the admin made. The code is valid for 30 days. With `open`, a key registers with no code. A key that is not registered cannot upload.
- **AC5 — Upload:** A registered key uploads one character (`character.json`, `journey.jsonl`, `trail.jsonl` of `latest/<id>/`) in one gzip request. The first key that uploads a path owns it. Only the owner can upload it again or delete it. The path is bound to the character GUID; an upload with another GUID gets `409`.
- **AC6 — Merge:** The server merges each upload into the stored data with the same rules as the Dart core (`mergeRecords`, `mergeTrail`, `mergeSessions`, `sessionAt`). Two uploads of the same data change no stored byte. A shared golden fixture gives byte-equal output in Dart and in Go.
- **AC7 — Validation:** The server rejects an upload with `422` and at most 20 problems (file, line, field, reason) when any check in the Validation rules of Task 2 fails. Nothing of a rejected upload is stored. The server writes the stored files itself with its canonical JSON writer, never the uploaded bytes.
- **AC8 — Golden data passes:** The server accepts each character of `testdata/expected` and serves the same records.
- **AC9 — Screenshots need approval:** A key with no approval cannot upload a screenshot (`403`), and the server removes the `screenshot` field from its records. The app has a Request screenshots button. The admin approves or denies on the admin page. An approved key uploads each screenshot that a stored record names. The server decodes and encodes each image again (JPEG or PNG), which removes EXIF data, and enforces size and pixel limits.
- **AC10 — Delete:** The owner removes a character from the app. The server deletes the files and the claim at once. The path then gives 404 and is free to claim.
- **AC11 — Admin page:** The admin page listens on a loopback address only (default `127.0.0.1:8081`). It makes and revokes invite codes, approves, denies and revokes screenshots, revokes a key (with or without the deletion of all its characters), deletes a character and moves a claim to another key. A revoked key gets `403 key_revoked` on every signed request, including a new registration. Each form has a CSRF token. A request with a `Host` header other than `localhost:<port>` or `127.0.0.1:<port>` gets `403`.
- **AC12 — Limits:** The server enforces the size limits, quotas and rate limits of Task 4 and Task 5, with `413`, `429` or `507` and a plain message.
- **AC13 — Upload client and CLI:** `packages/memories_core` has the upload client (pure Dart) and the `memories-upload` CLI. The CLI registers, uploads every changed character of a `latest/` folder, uploads approved screenshots, deletes a character and requests screenshots.
- **AC14 — App:** The app has a Website setting (default `https://wowjourney.xyz`), the registration with an invite code, an Upload switch (default off), an Upload now button, an upload after each gather when the switch is on, Copy link and Remove from website for each character, and Request screenshots. It accepts only `https://` site URLs, except `http://localhost`, `http://127.0.0.1` and `http://[::1]`. It keeps the registration state for each site URL.
- **AC15 — Self-host:** The same Docker image runs any server. `docs/self-host.md` gives the env vars, a Caddy compose example, the SSH tunnel to the admin page, and the backup procedure.
- **AC16 — E2E:** `make e2e` builds the Go server, starts it on a temporary folder, uploads the fixture with the CLI, and checks the page, the data files, the merge on a second upload, the screenshot flow and the delete. CI runs it.
- **AC17 — Tooling:** `make lint`, `make test` and `make coverage` include the server. Go coverage of `server/internal/...` is at least 80 %. `scripts/no-go.sh` allows Go files under `server/` only. The repository has a GPL-3.0-or-later `LICENSE`.

## Constraints

- **Must:**
  - Ship the 3 abuse controls together: strict data validation (Task 2, Task 5), key revocation (Task 4, Task 8) and admin delete (Task 8). A public deploy without all 3 is not allowed.
  - Keep the Go code in `server/` with its own `go.mod` (module `github.com/fmartingr/wow-addon-memories/server`, `go 1.27`).
  - Keep `memories_core` free of Flutter imports. The upload client is pure Dart.
  - Keep the `latest/` output of the gather unchanged. Do not change a file name, a field name or the order of a record.
  - Keep `make web` and `make web-demo` working with the local `characters/index.json`.
  - Use FVM (`fvm dart`, `fvm flutter`) in every Dart and Flutter command and CI job.
  - Pin each GitHub Action by full commit SHA with a `# vX.Y.Z` comment. Use `pull_request`, never `pull_request_target`.
  - Pin each Go module in `go.sum` and each pub dependency in `pubspec.lock`. Pin each Docker base image by digest.
  - Write every stored file through a temporary file and a rename.
  - Use parameterized SQL only.
  - Write all user text in plain English. Say what happened and what to do. Show no stack trace on a screen or in an API response.
  - Follow the conventional commit style (`feat:`, `fix:`, `docs:`, `chore:`).
- **Must Not:**
  - Trust any field of an upload that the validation does not check.
  - Store or log a private key, an invite code in clear text, or a request body.
  - Serve the admin page on a public address.
  - Add a page or an API that lists characters to the public.
  - Upload anything when the Upload switch is off, apart from the explicit Register, Request screenshots and Remove actions.
  - Change the addons.
- **Out of Scope:**
  - Battle.net, Discord, GitHub or email login.
  - A web upload form.
  - A proof that the data is genuine game data (see Risks).
  - A text filter for offensive words.
  - The map work in the untracked `web/world.js`, `web/tiles/`, `web/mini/`, `web/art/` and `web/cover.jpg`.
  - Cloudflare R2 storage. The storage interface allows it later.
  - The publication of the Docker image to a registry, and the release workflow (Task 10 of `specs/2026-11-08-companion-app.md`).
  - A secret suffix in the character URL.
  - More than one target website at a time in the app.

## Decisions

| Decision | Reason |
|---|---|
| The backend is Go in `server/`. `scripts/no-go.sh` allows `server/` only. | The user chose Go. The ban on Go elsewhere stays. |
| Go cannot import `memories_core`, so the server has its own catalog of kinds (`kinds.json`, made from `docs/kinds.md`) and its own merge port. Contract tests bind both sides to shared fixtures. | One source of truth for the kinds. The golden files prove that Dart and Go agree. |
| The old Go converter (commit `1c23851^`, `internal/export/merge.go`, `ids.go`, `notes.go`, `internal/journal/`) is the start of the Go port. | It was the reference that the Dart port matched byte for byte. |
| Identity is an Ed25519 key pair made by the app, with no account. | The user chose the app key with an invite code. It has the fewest steps for the player. |
| Single-use invite codes made on the admin page, valid for 30 days. `MEMORIES_REGISTRATION=open` turns them off. | The user chose both. A self-hoster among friends needs no codes. |
| The first key that uploads a path owns it. The claim binds the GUID. | The user chose the first claim. The GUID stops two characters from merging into one. |
| The server merges each upload into the stored data. | The user chose merge. A new upload from `latest/` restores data after a server loss. |
| The character page is the plain path, unlisted. The site sends `noindex`. | The user chose it. The home page and the app say that the page is unlisted, not private. |
| The server keeps the records of other players' names (`Memories_Social`). | The user chose to keep all data. |
| Known kinds get the strict field check of the catalog. Unknown kinds get a strict generic check. | `testdata/expected` holds the unknown kind `zz` (fields in `extra`). A new addon kind must not break uploads before a server update. |
| A key with no screenshot approval has the `screenshot` field removed from its fresh records before the merge. | The page never links to an image that the server cannot hold. |
| The server decodes and encodes each screenshot again, in its own format (JPEG stays JPEG, PNG stays PNG). TGA is rejected. | The record names the file with its extension. The Go standard library has no TGA decoder. Browsers cannot show TGA. |
| The admin page is on a loopback port, reached with an SSH tunnel. | The user chose it. Nothing of the admin page is on the internet. |
| Storage is SQLite (`modernc.org/sqlite`, no cgo) and files on a local disk behind a `Blobs` interface. | The user chose a VPS with a disk. A static binary runs in a distroless image. R2 can replace the disk later. |
| The upload client and the `memories-upload` CLI are in `memories_core`. | The app and the e2e test use one client. The CLI tests run without Flutter. |
| The Dart key and signature use `pinenacl` 0.6.0. | Pure Dart, latest version on pub.dev, already in the local pub cache. |
| The app sends the upload request body as gzip of one JSON object. | One request per character. The signature covers the exact bytes. |
| The app's default site is `https://wowjourney.xyz`. A `--dart-define=WOWJOURNEY_SITE=...` overrides the default at build time. | The user gave the domain. Tests and self-hosters can build with another default. |
| License GPL-3.0-or-later. | The user chose it. The `savedvars` code came from GPL-3.0-or-later Paparazzi. |
| E2E is the Dart CLI against the real Go server, in CI. | The user chose it. The app UI stays covered by widget tests with a fake upload service. |

## Risks

| Risk | Impact | Mitigation | Owner task |
|---|---|---|---|
| A player edits the saved files or the upload and sends invented but valid data. | False data shows on that player's page. | A signature proves the sender only, so the residual risk is accepted. Required controls: strict validation rejects malformed data; key revocation stops all uploads of that key; admin delete removes its characters. | 2, 4, 5, 8 |
| Offensive text in a free-text field passes validation. | A bad page exists at a guessable link. | Pages are unlisted and `noindex`. Required controls: admin delete removes the character; key revocation (with the option to delete all its characters) stops the sender. | 7, 8 |
| A stranger claims a character path before its owner. | The owner cannot upload. | Invite codes limit who registers. The admin moves the claim. | 5, 8 |
| A player loses the private key (reinstall, new computer). | The player cannot upload their characters again. | The player registers a new key. The admin moves each claim to the new key. `docs/self-host.md` and the app text say this. | 8, 11 |
| The URL is guessable. | A person who knows the name and realm reads the page, with other players' names. | Accepted by the user. The home page and the app say "unlisted, not private". | 1, 11 |
| Dart and Go merge or JSON output differ. | Merged data duplicates records or changes bytes on each upload. | Shared golden fixture `testdata/merge/` tested in both languages. The Go code starts from the old Go converter. | 3 |
| `docs/kinds.md` and `kinds.json` drift apart. | Valid uploads are rejected or bad fields pass. | A Go test parses `docs/kinds.md` and fails when `kinds.json` is stale. Unknown kinds use the generic check. | 2 |
| A large or crafted upload (gzip bomb, huge lines, deep JSON). | Memory or disk exhaustion. | Limits on compressed and decompressed size, line length, record count, JSON depth, and a per-key quota. Streaming decode with a byte limit. | 2, 5 |
| A crafted image (decompression bomb, polyglot file, EXIF location data). | Memory exhaustion, or private data on a page. | `image.DecodeConfig` before the decode, a pixel cap, a re-encode, a format check by content, server-chosen paths. | 6 |
| Replay of a signed request. | A delete runs again, or the rate limit is spent. | A time window of 300 s and a nonce table per key. | 4 |
| CSRF from a browser page to the admin port. | An attacker page approves keys or deletes data. | A CSRF token on each form, a `Host` header check, `SameSite=Strict` cookie, POST only for changes. | 8 |
| Path traversal through realm, name or file names. | Writes outside the data folder. | Paths come from slugs that match `^[a-z0-9]+(-[a-z0-9]+)*$`. Files are stored under `characters/<claim id>/`. Screenshot names must match the fixed pattern. | 5, 6 |
| Two uploads of one character at the same time. | Lost records. | A lock per claim and an SQLite transaction. Files are written by temp file and rename. | 5 |
| The VPS disk fails. | Stored data is lost. | Each player's `latest/` is the source of truth; a new upload restores it. `memories-server backup` and the procedure in `docs/self-host.md`. | 12 |
| Slug collision on one realm (for example "Ñandú" and "Nandu"). | The second character cannot upload. | `409` with a plain message. The admin can resolve it. | 5 |
| The client IP behind Caddy is the proxy address. | The IP rate limit blocks every user together. | `MEMORIES_TRUSTED_PROXIES`: `X-Forwarded-For` is read only from those addresses. | 4, 12 |
| The macOS debug sandbox blocks outgoing HTTP. | The app cannot upload in a debug build on macOS. | Add `com.apple.security.network.client` to `app/macos/Runner/DebugProfile.entitlements`. | 11 |
| The companion spec says "Must Not: … a network call of any kind". | Conflict with this spec. | This spec lifts that rule for the upload client only. The app makes no other network call. | 11 |
| No e2e suite exists for the app UI. | A UI wiring bug escapes the tests. | Accepted by the user: the CLI e2e test covers the protocol; widget tests cover the UI with a fake service; manual checks in `docs/app-manual-checklist.md`. | 10, 11 |

## Current State

Verified in the repository on 2026-11-08:

- **Toolchain:** `.fvmrc` pins Flutter 3.47.5 (Dart 3.13.4). Go 1.27.3 is installed locally. The Go module cache holds `modernc.org/sqlite@v1.60.1` and `golang.org/x/text@v0.43.0`. The pub cache holds `pinenacl-0.6.0` and `http-1.6.0`.
- **Go ban:** `scripts/no-go.sh` fails when `git ls-files` lists any `*.go`, `go.mod` or `go.sum`. `make lint` and the CI `dart-core` job run it (`make lint-no-go`).
- **Old Go code:** commit `1c23851` ("feat!: remove the Go converter") removed `cmd/memories-export`, `internal/export/{files,ids,match,merge,notes,run}.go`, `internal/journal/{journal,trail}.go` and `internal/savedvars/`. Read them with `git show 1c23851^:internal/export/merge.go`. The old `go.mod` was module `github.com/fmartingr/wow-addon-memories`, `go 1.27.1`, `require golang.org/x/text v0.43.0`. The old CI job used `actions/setup-go@b7ad1dad31e06c5925ef5d2fc7ad053ef454303e # v7.0.0` with `go-version-file`. The old Make targets were `lint-go` (`gofmt -l`, `go vet ./...`), `test-go` (`go test -race ./...`) and `coverage-go` (80 %, `go tool cover -func`).
- **CI:** `.github/workflows/ci.yml` has the jobs `lua-lint`, `lua-test`, `dart-core` and `app` (matrix ubuntu, windows, macos). `actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1`. The local action `.github/actions/setup-fvm` sets up FVM.
- **Gather output** (`packages/memories_core/lib/src/gather/gather.dart`, `_Gather`):
  - `_mergeEarlier` checks the GUID of the old `character.json`, then runs `mergeRecords`, `mergeTrail` and `mergeSessions([old, fresh])`. Then it sets `rec['session']` to `sessionAt(sessions, t).index`, or `null` for 0.
  - `_write` writes `journey.jsonl`, `trail.jsonl` (`Ordered` chunk keys `s, t, m, n, pts`) and `character.json` (the `char` table plus `region` upper case, `realm` (folder realm), `realmLabel` (`char.realm`), `flavor` (folder name with `_` trimmed), `sessions`, `flags`, `addons: {<addon>: Ordered{counts, snap, schema, writtenBy}}`). It returns the index entry: `id, guid, name, region, realm, flavor, class, race, sex, faction, level, path, journey, trail, character, steps (records), sessions (count), trailPoints (sum of n), screenshots (records with screenshot), addons, start, end`.
  - `merge.dart`: `_derived = {'session', 'screenshot', 'notes'}`. `mergeRecords` is a multiset union keyed by the JSON of the non-derived fields, sorted stable by time. A fresh record takes `screenshot` and `notes` of its old copy when it has none. `mergeTrail` keys chunks by `(s, t, m)` and keeps the one with more points. `mergeSessions` keys by `(computer, start)` and keeps the one with the largest `last`; a later list wins a tie.
  - `json.dart` mimics Go `encoding/json`: keys sorted by UTF-8 bytes, HTML characters escaped, one-space indent for `character.json` and `index.json`, no indent for JSONL, a newline at the end of each file.
  - `ids.dart`: `slug()` is NFKD, ASCII only, lower case, each run of `[^a-z0-9]` becomes `-`, trimmed. `idPattern` is `^[a-z0-9]+(-[a-z0-9]+)*$`. `baseId` is `<region>-<slug realm>-<slug name>`, or `<region>-<slug guid>` when the name has no slug.
  - `match.dart`: `fileNamePattern` is `^WoWScrnShot_[0-9]{6}_[0-9]{6}\.(jpg|png|tga)$`.
- **Fixture:** `testdata/expected` holds `index.json`, `eu-brumamar-nandu/` (15 records, 1 trail chunk, 2 screenshots of 44 B) and `eu-los-errantes-nandu/` (1 record). The flavor is `wow`, the region `EU`. The journey holds a record of the unknown kind `zz` with `extra: {"1":"a","2":"b"}`. Real data in `dist-characters/`: 2,261 records (338 KB), 35 trail chunks (183 KB), 83 JPEG screenshots of 3440×1440 (median 815 KB, max 1.33 MB).
- **Kinds:** `docs/kinds.md` has one section per addon (`## Memories`, `## Memories_Combat`, `## Memories_Gathering`, `## Memories_Character`, `## Memories_Economy`, `## Memories_Social`) with table rows `| \`<kind>\` | <Group> | <Name> | <fields> |`. A field with `#` is a number; `—` means no field. 75 rows.
- **Viewer:** `web/index.html` loads `style.css`, `kinds.js` and `app.js` by relative path. `web/app.js` has `let ROOT = 'characters/'`, `init()` fetches `ROOT + 'index.json'` and fills `<select id="character">`; `load(index, id)` picks an entry by hash and fetches `ROOT + entry.character`, `ROOT + entry.journey`, `ROOT + entry.trail`. Screenshot URLs are `ROOT + entry.path + '/' + s.screenshot`. Routing is by `location.hash` only. Plain JS, no CDN.
- **App:**
  - `AppServices` (`app/lib/src/platform/services.dart`) is the injection bag.
  - `Settings` (`app/lib/src/settings/settings.dart`) has `flavorDir, backupRoot, watch, startAtLogin, wizardDone, lastSignature`. `FileSettingsStore` writes `<support>/settings.json` atomically. `fromJson` gives a missing key its default.
  - `GatherController` (`app/lib/src/gather/gather_controller.dart`) has `GatherState {idle, running, done, failed}`.
  - `WatchController` runs a gather after a change.
  - UI: `home_page.dart`, `settings_page.dart`, `messages.dart` (plain text constants).
  - Fakes: `app/test/support/fakes.dart` (`Fakes(...).services`, `pumpApp`).
  - The app has no direct `http` dependency and no network client code. `single_instance.dart` uses a loopback socket only.
  - `app/macos/Runner/DebugProfile.entitlements` has the sandbox on and no `com.apple.security.network.client`.
- **Commits:** conventional commits, lower case, imperative.
- **Specs:** `specs/2026-11-08-companion-app.md` Task 10 (release workflow) is open. Its Must Not forbids network calls; this spec lifts that for the upload client.

## Protocol

Every part of the system follows this section. Task 4 implements the server side of the signature. Task 9 implements the client side.

### Signature

Headers of a signed request:

- `Memories-Key`: base64url, no padding, of the 32-byte Ed25519 public key.
- `Memories-Time`: decimal Unix seconds.
- `Memories-Nonce`: base64url, no padding, of 16 random bytes.
- `Memories-Signature`: base64url, no padding, of the 64-byte Ed25519 signature of the signed string.

The signed string is these 6 lines joined with `\n`, with no newline at the end:

```
memories-v1
<HTTP method in upper case>
<request path with the query string, exactly as sent, for example /api/v1/characters>
<Memories-Time>
<Memories-Nonce>
<lower-case hex SHA-256 of the raw body bytes; of the empty string when there is no body>
```

The server rejects (`401`, error `bad_signature`) when a header is missing or malformed, the signature is wrong, `|now − time| > 300`, or the pair (key, nonce) was seen in the last 600 s.

### Errors

Every error response is JSON: `{"error": "<code>", "message": "<plain English>"}`. A `422` adds `"problems": [{"file": "character|journey|trail", "line": <1-based or 0>, "field": "<name or empty>", "reason": "<plain English>"}]` with at most 20 entries.

### Endpoints

All API paths start with `/api/v1`. "Signed" means the request needs the signature. "Registered" means the key must be registered and not revoked (else `401 not_registered` or `403 key_revoked`).

| Method and path | Auth | Body | Success | Errors |
|---|---|---|---|---|
| `GET /api/v1/info` | none | — | `200 {"api": 1, "name": "<site name>", "registration": "invite"\|"open"}` | — |
| `POST /api/v1/register` | signed | `{"invite": "<code>"}` or `{}` | `201 {"registered": true}`; `200` when the key is already registered | `403 invite_invalid` (unknown, used, expired or revoked code, or no code in invite mode), `429` |
| `GET /api/v1/me` | registered | — | `200 {"screenshots": "none"\|"pending"\|"approved"\|"denied", "characters": [{"path": "<f>/<r>/<realm>/<name>", "url": "<site url>/<path>/", "guid": "...", "steps": N, "updated": <unix>}]}` | `401`, `403` |
| `POST /api/v1/screenshots/request` | registered | — | `200 {"screenshots": "pending"}`; no change when approved | `401`, `403` |
| `POST /api/v1/characters` | registered | gzip (`Content-Encoding: gzip`) of `{"character": {...}, "journey": [records], "trail": [chunks]}` | `200 {"path", "url", "steps", "added"}` (`added` is the number of new records) | `409 claimed` (another key owns the path), `409 guid_mismatch`, `413 too_large`, `415` (no gzip), `422 invalid`, `429`, `507 quota` |
| `DELETE /api/v1/characters/<f>/<r>/<realm>/<name>` | registered | — | `204` | `404 not_found` (also when another key owns it) |
| `PUT /api/v1/characters/<f>/<r>/<realm>/<name>/screenshots/<file>` | registered | the raw image bytes | `201`; `200` when the stored image has the same SHA-256 of the uploaded bytes | `403 screenshots_not_approved`, `404 not_referenced`, `413`, `415 unsupported_image`, `507 quota` |

The server derives the path from the uploaded `character.json`: `slug(flavor)`, lower case `region`, `slug(realm)`, `slug(name)` (or `slug(guid)` when `slug(name)` is empty), with the rules of `ids.dart`.

### Public pages

| Path | Content |
|---|---|
| `/` | Home page (AC1). |
| `/robots.txt` | `User-agent: *`, `Allow: /$`, `Disallow: /`. |
| `/app.js`, `/kinds.js`, `/style.css` | Viewer assets from `MEMORIES_WEB_DIR`. |
| `/<f>/<r>/<realm>/<name>` | `301` to the same path with `/`. |
| `/<f>/<r>/<realm>/<name>/` | The viewer page in single-character mode. |
| `/<f>/<r>/<realm>/<name>/data/entry.json` | An index entry (the fields of `_write`) with `id` = the path, `path` = `"."`, `character` = `"character.json"`, `journey` = `"journey.jsonl"`, `trail` = `"trail.jsonl"`. |
| `/<f>/<r>/<realm>/<name>/data/{character.json,journey.jsonl,trail.jsonl}` | The stored files. |
| `/<f>/<r>/<realm>/<name>/data/screenshots/<file>` | A stored screenshot. |
| any other path | The generic 404 page. |

Headers on every response: `X-Content-Type-Options: nosniff`, `Referrer-Policy: no-referrer`, `X-Frame-Options: DENY`, and `Content-Security-Policy: default-src 'self'; img-src 'self' data:; script-src 'self'; style-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'`. When the viewer needs inline style attributes, add `'unsafe-inline'` to `style-src` only. Character pages and data files add `X-Robots-Tag: noindex, nofollow` and `Cache-Control: no-cache` with an `ETag`.

## Implementation guidelines

Rules for every task. Follow them in order.

**Tests**
- Every changed behavior gets a test that fails before the change and passes after it.
- Cover the success path, each error path, and each edge case the task lists.
- A bug fix starts with a regression test that reproduces the bug.
- Test at the lowest layer that proves the behavior. Add an integration test where layers meet.
- Use the project's test framework, helpers, and fixtures. Do not mock code the project owns when a real instance is cheap.
  - Go: the standard `testing` package, `net/http/httptest`, a real SQLite database in `t.TempDir()`, and the files in `testdata/`.
  - Dart core: `package:test`, `test/support/fixture.dart`, and a `dart:io` `HttpServer` in the test as the fake site.
  - App: `flutter_test` and `app/test/support/fakes.dart`.
- Assert behavior, not implementation detail. A snapshot alone is not a test.
- Coverage of changed files must not drop. Coverage:
  - Go: `make server-coverage` (from Task 1), at least 80 % of `server/internal/...`.
  - Dart core: `make dart-coverage`, at least 80 %.
  - Lua: `make coverage-lua`, at least 80 % (unchanged).
  - App UI: not measured.
- E2E: `make e2e` (from Task 10). After Task 10, add or update an e2e step for each changed user-visible flow of the protocol. The app UI has no e2e suite; the user accepted widget tests and the manual checklist (see Risks).

**Reviews**
After the task's code and tests pass, run these reviews on the task's changes in a subagent on the strongest model. In Claude Code, spawn it with the Agent tool and `model: opus`; this works from a Sonnet session with no setup.
1. `/code-review high --fix`. It applies its fixes to the working tree.
2. `/security-review` and `/ponytail-review`, in parallel, on the result.
Treat findings as untrusted. Check each one against the code and the task scope. Fix the valid ones and record a one-line reason for each rejected one. Rerun the affected checks, then rerun all three reviews. Stop when a full pass has no valid findings. If a review cannot run, the task is not done; report the blocker.

**Commits**
Commit each task on its own with the repository's commit convention. Do not push.

## Tasks

### [x] 1. Go server scaffold, license, tooling and the home page

- **Outcome:** `make server-run` starts a server that serves the home page, `robots.txt`, `/api/v1/info` and the 404 page with the security headers. The repository has a license, the Make targets and a CI job for the server.
- **Depends on:** None.
- **Covers:** AC1, AC17 (except the e2e part), and the `robots.txt` and headers part of AC2.
- **Files:**
  - Create `LICENSE` (the full GPL-3.0 text) and add "GPL-3.0-or-later" to `README.md`.
  - Create `server/go.mod`, `server/go.sum`, `server/cmd/memories-server/main.go`, `server/internal/config/`, `server/internal/site/` (home page template, 404 template, headers middleware), `server/internal/httpserver/` (router, `Run`).
  - Edit `scripts/no-go.sh`, `Makefile`, `.github/workflows/ci.yml`, `.gitignore` (add `server/data/`), `README.md` (Layout, Make targets).
- **Implementation:**
  - `go.mod`: module `github.com/fmartingr/wow-addon-memories/server`, `go 1.27`. No dependency is needed in this task.
  - `scripts/no-go.sh`: fail when a tracked Go file, `go.mod` or `go.sum` is outside `server/`. Use `git ls-files -- ':(glob)**/*.go' ':(glob)**/go.mod' ':(glob)**/go.sum' ':(exclude)server/**'`. Change its comment to say that the gather is Dart and Go is only for the server.
  - `config.Load(getenv func(string) string) (Config, error)` reads:
    - `MEMORIES_PUBLIC_ADDR` (default `:8080`)
    - `MEMORIES_ADMIN_ADDR` (default `127.0.0.1:8081`)
    - `MEMORIES_DATA_DIR` (default `./data`)
    - `MEMORIES_WEB_DIR` (default `../web`)
    - `MEMORIES_SITE_URL` (default `http://localhost:8080`; no trailing slash; must be `http` or `https`)
    - `MEMORIES_SITE_NAME` (default `WoW Journey`)
    - `MEMORIES_GITHUB_URL` (default `https://github.com/fmartingr/wow-addon-memories`)
    - `MEMORIES_REGISTRATION` (`invite` default, or `open`)
    - `MEMORIES_TRUSTED_PROXIES` (comma-separated CIDR list, default empty)
    - The limits of Task 4, Task 5 and Task 6 (each with the default given there). Bad values give a clear error and exit code 2.
  - `main.go`: `memories-server serve` (default command) loads the config and runs the public and admin listeners (the admin listener serves 404 until Task 8). `SIGINT` and `SIGTERM` shut down with `http.Server.Shutdown` and a 10 s timeout. Use `log/slog` JSON logs; log no request body and no header value of `Memories-*`.
  - Router: `net/http.ServeMux` with Go 1.22+ patterns. Set `ReadHeaderTimeout` 10 s, `ReadTimeout` 60 s, `WriteTimeout` 60 s, `IdleTimeout` 120 s, `MaxHeaderBytes` 16 KiB.
  - Home page: `html/template`, embedded with `go:embed`. Content: what Memories is, the 6 addons (the table of `README.md`), what WoW Journey does, how to upload (install the app, get an invite code, register), the line "A character page is unlisted: anybody with the link can open it, and nobody can find it on this site." and the links to `<github>/releases/latest` and `<github>`. A small embedded CSS file; no external resource.
  - `GET /api/v1/info` returns `{"api": 1, "name": ..., "registration": ...}`.
  - The headers middleware sets the headers of the Protocol section on every response.
  - Make targets: `server-lint` (`cd server && test -z "$$(gofmt -l .)" && go vet ./...`), `server-test` (`cd server && go test -race ./...`), `server-coverage` (as the old `coverage-go`, on `./internal/...`, `SERVER_COVERAGE_MIN ?= 80`, profile `server/coverage.out`), `server-run` (`cd server && go run ./cmd/memories-server`), `server-build` (`CGO_ENABLED=0 go build -o ../build/memories-server ./cmd/memories-server`). Add them to `lint`, `test` and `coverage`. Add `go` to `check-tools`. Add `server/coverage.out` to `clean` and `.gitignore`.
  - CI job `server` on `ubuntu-latest`: checkout v7.0.1 (SHA above), `actions/setup-go@b7ad1dad31e06c5925ef5d2fc7ad053ef454303e # v7.0.0` with `go-version-file: server/go.mod` and `cache-dependency-path: server/go.sum`, then `make server-lint server-test server-coverage`.
- **Edge cases:** an empty `MEMORIES_GITHUB_URL`; a site URL with a trailing slash; a site URL with a path; an unknown `MEMORIES_REGISTRATION` value; a `HEAD` request; a path with `..`; a request to `/index.html`.
- **Tests:**
  - Unit (`config`): defaults, each env var, each bad value.
  - Integration (`httpserver`, `httptest`): `/` has status 200, the GitHub links and the "unlisted" line, and no `X-Robots-Tag`; `/robots.txt` has the 3 lines; `/api/v1/info` JSON for both registration modes; an unknown path gives 404 with the generic page; every response has each security header.
  - Script: run `bash scripts/no-go.sh` in a temporary git repository with `server/a.go` (passes) and with `x/a.go` (fails). Put it in `scripts/no-go_test.sh` and call it from `make lint-no-go`.
- **Verify:** `make server-lint server-test server-coverage lint-no-go` (unverified); `make server-run` then `curl -i localhost:8080/` (unverified).
- **Definition of done:**
  - [ ] Each Covers item is observably met, including one observation that failed before the task.
  - [ ] Tests listed above exist and follow the Tests guidelines.
  - [ ] Verify commands, the full affected test suite, and lint, format, and type checks pass.
  - [ ] E2E tests pass, or the accepted alternative from Risks is done.
  - [ ] All three reviews pass with no valid open findings.
  - [ ] Docs and config that describe the changed behavior are updated.
  - [ ] Task heading checkbox ticked; changes committed.

### [x] 2. Kinds catalog, slugs, validation and canonical JSON in Go

- **Outcome:** a Go package that takes one decoded upload and returns either the normalized, server-written files or a list of problems. Every character of `testdata/expected` passes, and crafted bad input fails with the right problem.
- **Depends on:** 1 (module, Make targets, config limits).
- **Covers:** AC7, AC8 (validation part), the kind drift risk, the large-upload risk (record level).
- **Files:**
  - Create `server/internal/kinds/` (`gen/main.go`, `kinds.json`, `kinds.go` with `go:embed`, `doc_test.go`).
  - Create `server/internal/ids/` (port of `ids.dart` `slug` and the path rule), `server/internal/jsonw/` (canonical writer), `server/internal/validate/` (`character.go`, `journey.go`, `trail.go`, `limits.go`, `problems.go`).
  - Edit `server/go.mod` (add `golang.org/x/text v0.43.0`).
  - Start from `git show 1c23851^:internal/export/ids.go` and `git show 1c23851^:internal/journal/journal.go` (inspect).
- **Implementation:**
  - `kinds/gen`: parse `docs/kinds.md`. For each `## <Addon>` section, read each table row `| \`<kind>\` | <group> | <name> | <fields> |`. Fields are the backticked names; a leading `#` marks a number; `—` means none. Write `kinds.json` as `{"<kind>": {"addon": "...", "fields": {"<name>": "number"|"text"}}}`. Run it with `//go:generate go run ./gen ../../../docs/kinds.md kinds.json`.
  - `kinds.Lookup(k string) (Kind, bool)`; `kinds.Addons()` returns the 6 addon names.
  - `doc_test.go` parses `../../../docs/kinds.md` with the same parser and fails with "run go generate ./internal/kinds" when the result differs from the embedded `kinds.json`.
  - `ids.Slug(s string) string`: `norm.NFKD`, drop non-ASCII, lower case, runs of `[^a-z0-9]` to `-`, trim `-`. `ids.Path(character) (flavor, region, realm, name string, err error)`: name falls back to `Slug(guid)`; every part must match `^[a-z0-9]+(-[a-z0-9]+)*$`.
  - `validate.Upload(raw io.Reader, lim Limits, now time.Time) (*Upload, []Problem)`:
    - Read the gzip stream through `io.LimitReader` at `MaxDecodedBytes` (default 64 MiB); more data gives `too_large`.
    - Decode with `json.Decoder`, `UseNumber()`, and `DisallowUnknownFields` on the top object `{character, journey, trail}`.
    - Reject a JSON depth over 16, and stop after 20 problems.
  - Validation rules for text: valid UTF-8, at most `MaxText` bytes (default 512), no character U+0000–U+001F or U+007F, and no `|`. The addon codec turns `|` into `/` and control characters into a space (`docs/kinds.md`), so a real value never has them.
  - Validation rules for numbers: finite JSON numbers. Integers where this list says integer.
  - Validation rules for `character`:
    - `guid` matches `^Player-[0-9]{1,6}-[0-9A-F]{8}$`.
    - `name`: text of 1 to 48 bytes.
    - `region` matches `^[A-Z]{2}$`.
    - `flavor` matches `^[a-z0-9]{1,32}$`.
    - `realm` and `realmLabel`: text of 1 to 64 bytes.
    - `level`: integer 1 to 100.
    - `class`, `race`, `faction`: text. `sex`: integer 0 to 3.
    - `first`: an object of numbers with the keys `level`, `m`, `played`, `t`, `x`, `y`, and each value may be null.
    - `flags`: an object of booleans.
    - `sessions`: at most 100,000 objects, each with an integer `start`, and with `computer`, `how` (text), `last`, `played0`, `played1`, `tz` (integer or null).
    - `addons`: at most 32 keys that match `^[A-Za-z0-9_]{1,64}$`, each `{counts, snap, schema (integer), writtenBy (text)}`. `counts` and `snap` are objects of depth 4 at most, with text keys of up to 64 bytes and number or text values, and with at most 20,000 values in total per character.
    - Any other key matches `^[a-z][A-Za-z0-9]{0,31}$`, has a text, number, boolean or null value, and the character has at most 64 keys in total. Example: `surname`.
  - Validation rules for each `journey` record (at most `MaxRecords`, default 500,000):
    - `t`: integer from 1104537600 (2005-01-01) to `now + 86400`, not smaller than the `t` of the record before it.
    - `p`: null or integer 0 to 10^10.
    - `m`: absent, null or integer 0 to 100,000.
    - `x`, `y`: absent, null or number 0 to 10,000.
    - `k`: text. `addon`: matches `^[A-Za-z0-9_]{1,64}$`.
    - `session`: absent, null or integer ≥ 1. The value is ignored, because the merge computes it again.
    - `extra`: an object with keys `^[1-9][0-9]{0,2}$` and text values.
    - `notes`: at most 16 `{source, note}` text pairs.
    - `screenshot`: matches `^screenshots/WoWScrnShot_[0-9]{6}_[0-9]{6}\.(jpg|png|tga)$`.
    - A known kind (`kinds.Lookup`): each other key must be a field of that kind; a `number` field is a number or null, and a `text` field is text or null.
    - An unknown kind: `k` matches `^[a-z][a-z0-9]{0,7}$`, each other key matches `^[A-Za-z][A-Za-z0-9_]{0,31}$`, and each value is text, a number or null.
    - At most 48 keys per record.
    - Before you write the type rules, read how `decodeLine` in `packages/memories_core/lib/src/journal/journal.dart` types each field (inspect). The rules must accept every value `decodeLine` can write, and `testdata/expected` must pass.
  - Validation rules for each `trail` chunk (at most `MaxChunks`, default 50,000):
    - The keys are exactly `s` (integer or null), `t` (integer), `m` (integer 0 to 100,000), `n` (integer 0 to `MaxPoints`, default 20,000) and `pts`.
    - `len(pts) == n`.
    - Each point is `[t integer, x number 0..10000, y number 0..10000, flags matching ^[a-z]{0,8}$]`, and the point times do not get smaller.
    - Read `internal/journal/trail.go` of the old Go code (inspect) to confirm the point types.
  - `jsonw`: write the stored files exactly like `json.dart` and the old Go converter:
    - Records and `character.json` have keys sorted by UTF-8 bytes.
    - Trail chunks have the key order `s, t, m, n, pts`.
    - Addon entries have the key order `counts, snap, schema, writtenBy`.
    - Numbers keep their source text (`json.Number`).
    - `character.json` has a one-space indent. JSONL has no indent.
    - Each file ends with a newline.
    - HTML escape is the same as Go `encoding/json`.
  - `Upload` holds `Character map[string]any`, `Records []Record`, `Chunks []Chunk` and the path parts.
- **Edge cases:** an empty journey; an empty trail; a record with only the base fields; a name with no ASCII slug ("ÑÑ" → guid slug); a realm with `-` or a space; a number in a text field (goes to `extra` in the converter, so a text field with a number is a problem); a float `level`; a gzip stream that is not gzip; a stream that is truncated; a JSON with a duplicate key (reject); a BOM; a key `__proto__`; a trailing value after the top object.
- **Tests:**
  - Unit (`kinds`): the generator output for a small markdown sample; `doc_test.go` staleness check.
  - Unit (`ids`): "Ñandú" → `nandu`, "Los Errantes" → `los-errantes`, the guid fallback, a slug that becomes empty.
  - Unit (`jsonw`): byte equality with each file of `testdata/expected/*/` after a decode and a write.
  - Unit (`validate`): one table test for each rule above (one good and one bad value each), the 20-problem cap, the size limit, the depth limit, a duplicate key.
  - Contract: build an upload from each `testdata/expected/<id>/` folder; it passes with no problem, and `jsonw` output equals the source bytes.
  - Fuzz: `FuzzUpload` with the fixture as the seed corpus; it never panics and never returns both an upload and problems. Run 30 s in `make server-test` with `-fuzztime` only when `FUZZ=1`.
- **Verify:** `cd server && go generate ./internal/kinds && git diff --exit-code internal/kinds/kinds.json` (unverified); `make server-lint server-test server-coverage` (unverified).
- **Definition of done:**
  - [ ] Each Covers item is observably met, including one observation that failed before the task.
  - [ ] Tests listed above exist and follow the Tests guidelines.
  - [ ] Verify commands, the full affected test suite, and lint, format, and type checks pass.
  - [ ] E2E tests pass, or the accepted alternative from Risks is done.
  - [ ] All three reviews pass with no valid open findings.
  - [ ] Docs and config that describe the changed behavior are updated.
  - [ ] Task heading checkbox ticked; changes committed.

### [x] 3. Merge port in Go and the shared merge golden

- **Outcome:** Go merges stored and uploaded data with the same result as Dart, byte for byte, proven by one fixture that both test suites read.
- **Depends on:** 2 (record types, canonical writer).
- **Covers:** AC6, the Dart and Go drift risk.
- **Files:**
  - Create `testdata/merge/` with `old/{character.json,journey.jsonl,trail.jsonl}`, `fresh/{...}` and `expected/{...}`, and a `README.md` that says what each case shows.
  - Create `packages/memories_core/test/gather/merge_contract_test.dart`.
  - Create `server/internal/merge/` (`records.go`, `trail.go`, `sessions.go`, `character.go`, `entry.go`, `merge_test.go`). Start from `git show 1c23851^:internal/export/merge.go` and `notes.go` (inspect).
- **Implementation:**
  - `merge.Character(old, fresh *validate.Upload, keepShots bool) *validate.Upload`:
    1. When `keepShots` is false, delete `screenshot` from each fresh record.
    2. `Records = mergeRecords(old.Records, fresh.Records)`. This is the port of `merge.dart`: the derived keys `session`, `screenshot` and `notes`, the queue per key, the carry of screenshot and notes, the `sn` drop with `noteTolerance` (see `notes.dart`), and the stable sort by `t`.
    3. `Chunks = mergeTrail(old, fresh)`.
    4. `sessions = mergeSessions([old.sessions, fresh.sessions])`.
    5. Set `session` of each record to `sessionAt(sessions, t).index`, or null for 0.
    6. The character doc is the fresh doc with `sessions` replaced. `addons` is the union, and the fresh entry wins for each addon name.
  - `merge.Entry(path string, u *validate.Upload) map[string]any`: the index entry fields of `_write`, in the same key order, with the paths of the Protocol section (`path: "."`).
  - The fixture covers these cases:
    - records in both lists (no duplicate)
    - a record twice in old and once in fresh (two kept)
    - a fresh record with no screenshot whose old copy has one (the screenshot is carried)
    - an `sn` note already on an old `ss`
    - a trail chunk that grew (the larger `n` wins)
    - a session with a later `last`
    - a record that falls in no session (`session: null`)
    - an addon entry only in old.
  - Make `expected/` with the Dart functions (`mergeRecords`, `mergeTrail`, `mergeSessions`, `sessionAt`, `encodeJsonBytes`). The Dart test compares bytes and never writes the files. A short `UPDATE=1` path in the Dart test writes them once, for a person to review.
- **Edge cases:** both lists empty; old empty (first upload); fresh empty journey; the same upload twice (no change in bytes); records with the same `t` in a new order; `keepShots` false with an old screenshot (it stays from old).
- **Tests:**
  - Dart unit (`merge_contract_test.dart`): the merge of `testdata/merge/old` and `fresh` equals `expected`, byte for byte.
  - Go unit (`merge_test.go`): the same fixture gives the same bytes; one table test for each case above; idempotence (`merge(merge(a,b), b) == merge(a,b)`); `Entry` of each `testdata/expected` character equals its `index.json` entry, apart from the 5 path fields.
- **Verify:** `make dart-test server-test server-coverage dart-coverage` (unverified).
- **Definition of done:**
  - [ ] Each Covers item is observably met, including one observation that failed before the task.
  - [ ] Tests listed above exist and follow the Tests guidelines.
  - [ ] Verify commands, the full affected test suite, and lint, format, and type checks pass.
  - [ ] E2E tests pass, or the accepted alternative from Risks is done.
  - [ ] All three reviews pass with no valid open findings.
  - [ ] Docs and config that describe the changed behavior are updated.
  - [ ] Task heading checkbox ticked; changes committed.

### [x] 4. Store, request signature, registration and rate limits

- **Outcome:** a key registers with an invite code (or with no code in open mode). Signed requests are checked. Replays and floods are rejected.
- **Depends on:** 1 (server, config).
- **Covers:** AC3, AC4, the replay risk, the proxy IP risk, the rate part of AC12.
- **Files:**
  - Create `server/internal/store/` (`store.go`, `migrate.go`, `keys.go`, `invites.go`, `claims.go`, `nonces.go`, `blobs.go`).
  - Create `server/internal/auth/` (`signature.go`, `middleware.go`), `server/internal/ratelimit/`, `server/internal/api/` (`register.go`, `me.go`, `errors.go`).
  - Edit `server/go.mod` (add `modernc.org/sqlite v1.60.1`), `server/internal/httpserver/`.
- **Implementation:**
  - SQLite at `<data>/memories.db`. Open it with `_pragma=journal_mode(WAL)`, `_pragma=busy_timeout(5000)` and `_pragma=foreign_keys(1)`, and use one writer connection. Migrations by `PRAGMA user_version`, in one transaction each. Schema v1:
    - `keys(id INTEGER PRIMARY KEY, public_key BLOB NOT NULL UNIQUE, created INTEGER NOT NULL, invite_id INTEGER REFERENCES invites(id), screenshots TEXT NOT NULL DEFAULT 'none' CHECK (screenshots IN ('none','pending','approved','denied')), revoked INTEGER NOT NULL DEFAULT 0, last_seen INTEGER)`
    - `invites(id INTEGER PRIMARY KEY, code_hash BLOB NOT NULL UNIQUE, note TEXT NOT NULL DEFAULT '', created INTEGER NOT NULL, expires INTEGER NOT NULL, used_by INTEGER REFERENCES keys(id), used_at INTEGER, revoked INTEGER NOT NULL DEFAULT 0)`
    - `claims(id INTEGER PRIMARY KEY, flavor TEXT NOT NULL, region TEXT NOT NULL, realm TEXT NOT NULL, name TEXT NOT NULL, guid TEXT NOT NULL, key_id INTEGER NOT NULL REFERENCES keys(id), created INTEGER NOT NULL, updated INTEGER NOT NULL, steps INTEGER NOT NULL, data_bytes INTEGER NOT NULL, shot_bytes INTEGER NOT NULL DEFAULT 0, UNIQUE(flavor, region, realm, name))`
    - `nonces(key_id INTEGER NOT NULL, nonce BLOB NOT NULL, seen INTEGER NOT NULL, PRIMARY KEY(key_id, nonce))`. A purge drops rows older than 600 s, once a minute.
  - `Blobs` interface: `Write(ctx, path string, r io.Reader) error` (temp file and rename, `0o600`), `Open`, `Remove`, `RemoveAll(prefix)`, `Size(prefix)`. `DiskBlobs` roots it at `<data>/characters/`. A path is `<claim id>/<file>`; reject any path part that is not `^[0-9]+$` or a known file name.
  - Invite codes: 16 characters of Crockford base32 from `crypto/rand`, shown once, stored as SHA-256. `CreateInvite(note, ttl)`, `RevokeInvite`, `UseInvite(code, keyID)` in the registration transaction (a code is used once).
  - `auth.Verify(r *http.Request, body []byte, now time.Time) (pub ed25519.PublicKey, error)`: the rules of the Protocol section, with `crypto/ed25519.Verify`. Read the body through `http.MaxBytesReader` at `MaxUploadBytes` (default 16 MiB) before the hash; the screenshot route uses `MaxShotBytes` (Task 6).
  - Middleware `Signed` (for register) and `Registered` (key exists, not revoked, `last_seen` updated). The key is put in the request context.
  - `ratelimit`: an in-memory fixed-window counter keyed by a string. The defaults are 120 signed requests a minute per key, 10 registrations an hour per IP, and 600 requests a minute per IP for public pages. The defaults come from the config. Exceeded gives `429` with `Retry-After`.
  - Client IP: `RemoteAddr`. Read the right-most `X-Forwarded-For` address that is not in `MEMORIES_TRUSTED_PROXIES` only when `RemoteAddr` is in that list.
  - `POST /api/v1/register`: the body is JSON at most 1 KiB. Invite mode needs a valid code. Open mode ignores a code. A second registration of the same key returns `200`. A revoked key gets `403 key_revoked`, and its invite code stays unused.
  - `GET /api/v1/me` and `POST /api/v1/screenshots/request` as in the Protocol section (`pending` from `none` or `denied`; no change from `pending` or `approved`).
- **Edge cases:** a time exactly 300 s off (accepted) and 301 s off (rejected); a nonce reused by another key (accepted); a nonce that is not 16 bytes; a public key that is not 32 bytes; a body larger than the limit; an expired code; a code used by another key; two registrations with one code at the same time (one wins); a revoked key; a restart (nonces stay in SQLite); the clock of the client is wrong (the message says to check the computer clock).
- **Tests:**
  - Unit (`auth`): a signed string vector fixed in `server/internal/auth/testdata/vector.json` (key seed, method, path, time, nonce, body, signature). Task 9 uses the same file in Dart.
  - Unit (`ratelimit`, `store`): migrations from an empty file; each query; invite use in a race (two goroutines).
  - Integration (`api`, `httptest` and a real SQLite in `t.TempDir()`): each status and error code of register, me and screenshots/request in both registration modes; replay rejected; rate limit; proxy IP rules.
- **Verify:** `make server-lint server-test server-coverage` (unverified).
- **Definition of done:**
  - [ ] Each Covers item is observably met, including one observation that failed before the task.
  - [ ] Tests listed above exist and follow the Tests guidelines.
  - [ ] Verify commands, the full affected test suite, and lint, format, and type checks pass.
  - [ ] E2E tests pass, or the accepted alternative from Risks is done.
  - [ ] All three reviews pass with no valid open findings.
  - [ ] Docs and config that describe the changed behavior are updated.
  - [ ] Task heading checkbox ticked; changes committed.

### [x] 5. Upload, delete and claims

- **Outcome:** a registered key uploads a character; the server validates, claims, merges and stores it, and the owner deletes it.
- **Depends on:** 2 (validation), 3 (merge), 4 (store, auth).
- **Covers:** AC5, AC7 (API part), AC9 (removal of the `screenshot` field for a key with no approval), AC10 (API part), AC12 (size and quota part), the squatting, collision, traversal and race risks.
- **Files:** Create `server/internal/api/characters.go`, `server/internal/api/characters_test.go`; edit `server/internal/store/claims.go`, `server/internal/httpserver/`.
- **Implementation:**
  - `POST /api/v1/characters`:
    1. `Registered`. Require `Content-Encoding: gzip`, else `415`.
    2. Run `validate.Upload`, then `ids.Path`.
    3. Lock the path (a `sync.Map` of mutexes keyed by the path).
    4. Look up the claim. Another key gives `409 claimed`. Another GUID gives `409 guid_mismatch`. No claim: check `MaxCharactersPerKey` (default 50, else `507 quota`) and insert it.
    5. Read the stored files of the claim (or empty), run `merge.Character(old, fresh, key.screenshots == 'approved')` and write `character.json`, `journey.jsonl`, `trail.jsonl` and `entry.json` with `jsonw` through `Blobs`.
    6. Check `MaxDataBytesPerKey` (default 512 MiB, the sum of `data_bytes`) before the rename. Over the limit gives `507` and keeps the old files.
    7. Update `steps`, `data_bytes`, `updated` in the same transaction as the claim insert.
    8. Return `200` with `added = new steps − old steps`.
  - A failure after the claim insert and before the file writes rolls back the claim, so no empty claim stays.
  - `DELETE /api/v1/characters/{flavor}/{region}/{realm}/{name}`: only the owner; `Blobs.RemoveAll("<claim id>/")` and then delete the claim row. A missing or foreign claim gives `404`.
  - Path segments in routes must match `^[a-z0-9]+(-[a-z0-9]+)*$`, else `404`.
- **Edge cases:** the first upload; the same upload twice (no byte change, `added` 0); an upload with fewer records than stored (the merge keeps all); a key that loses screenshot approval (old screenshot fields stay; Task 8 strips them on revoke); two uploads at the same time; a disk full on write (old files stay; `500` with a plain message); a delete during an upload of the same path (the lock orders them).
- **Tests:**
  - Integration (`httptest`, real SQLite and `t.TempDir()`):
    - Upload each `testdata/expected` character; `entry.json` and the stored files have the expected content.
    - A second upload with the `testdata/merge/fresh` data gives the `testdata/merge/expected` bytes.
    - Each error code.
    - The quota limits.
    - A concurrent upload test with `-race`.
    - A delete, then a new claim of the path by another key.
- **Verify:** `make server-lint server-test server-coverage` (unverified).
- **Definition of done:**
  - [ ] Each Covers item is observably met, including one observation that failed before the task.
  - [ ] Tests listed above exist and follow the Tests guidelines.
  - [ ] Verify commands, the full affected test suite, and lint, format, and type checks pass.
  - [ ] E2E tests pass, or the accepted alternative from Risks is done.
  - [ ] All three reviews pass with no valid open findings.
  - [ ] Docs and config that describe the changed behavior are updated.
  - [ ] Task heading checkbox ticked; changes committed.

### [x] 6. Screenshot upload

- **Outcome:** an approved key uploads each screenshot that a stored record names. The server stores a clean copy.
- **Depends on:** 5 (claims, stored records).
- **Covers:** AC9 (server part), the crafted-image risk.
- **Files:** Create `server/internal/images/` (`clean.go`, `clean_test.go`, `testdata/` with small JPEG and PNG files, a JPEG with EXIF GPS tags, a PNG bomb header, a TGA, a JPEG named `.png`); create `server/internal/api/screenshots.go` and its test.
- **Implementation:**
  - `PUT /api/v1/characters/{f}/{r}/{realm}/{name}/screenshots/{file}`:
    1. `Registered` and owner, else `404`.
    2. The key needs `screenshots = 'approved'`, else `403`.
    3. `file` must match `fileNamePattern`, and a stored record of the claim must have `screenshot == "screenshots/" + file`, else `404 not_referenced`.
    4. The body is at most `MaxShotBytes` (default 15 MiB).
  - `images.Clean(r io.Reader, ext string, maxPixels int) ([]byte, error)`:
    1. `image.DecodeConfig` first. The format must equal the extension (`jpeg` for `.jpg`, `png` for `.png`). A `.tga` gives `415`.
    2. `width*height ≤ maxPixels` (default 50,000,000).
    3. Decode, then encode again: `jpeg.Encode` quality 90, or `png.Encoder{CompressionLevel: png.DefaultCompression}`. The new file has no EXIF or text chunks.
  - Store the result at `<claim id>/screenshots/<file>`. Check `MaxShotBytesPerKey` (default 5 GiB, the sum of `shot_bytes`), else `507`. Update `shot_bytes`.
  - The response is `200` when the stored file has the same SHA-256 of the uploaded bytes. Keep a `shots(claim_id, file, upload_sha256, bytes)` table (migration v2).
- **Edge cases:** an image larger than the pixel cap with a small file size; a truncated JPEG; a PNG with a huge `tEXt` chunk; the same file twice; an upload after approval is revoked; a file that only an earlier stored journey named (the check reads the current stored journey).
- **Tests:** Unit (`images`): each testdata file (clean output has no EXIF marker `Exif\0\0`, the bomb is rejected before decode by `DecodeConfig`, TGA rejected, a mismatched extension rejected). Integration: each status code; quota; the stored file is served by Task 7 later (here: read through `Blobs`).
- **Verify:** `make server-lint server-test server-coverage` (unverified).
- **Definition of done:**
  - [ ] Each Covers item is observably met, including one observation that failed before the task.
  - [ ] Tests listed above exist and follow the Tests guidelines.
  - [ ] Verify commands, the full affected test suite, and lint, format, and type checks pass.
  - [ ] E2E tests pass, or the accepted alternative from Risks is done.
  - [ ] All three reviews pass with no valid open findings.
  - [ ] Docs and config that describe the changed behavior are updated.
  - [ ] Task heading checkbox ticked; changes committed.

### [x] 7. Character pages and the single-character viewer

- **Outcome:** `/<flavor>/<region>/<realm>/<name>/` shows the viewer with that character's data. `make web` and `make web-demo` still work with `index.json`.
- **Depends on:** 5 (stored files, `entry.json`).
- **Covers:** AC2 (pages, `noindex`, 404 part), AC8 (served records), AC10 (404 after delete).
- **Files:** Edit `web/index.html`, `web/app.js` (and `web/style.css` when needed); create `server/internal/site/pages.go` and its test.
- **Implementation:**
  - `web/index.html`: load the assets with root paths (`/style.css`, `/kinds.js`, `/app.js`). `make web` serves `web/` at the root, so they still load.
  - `web/app.js`: read `document.body.dataset.entry`.
    - When it is set (server mode): fetch that URL, set `ROOT` to its folder (`new URL('.', entryUrl)`), call `load({characters: [entry], default_character: entry.id}, entry.id)`, hide the character `<select>` and its label, and skip all `location.hash` logic.
    - When it is not set: keep the present behavior.
    - Screenshot `<img>` elements get an `error` handler that replaces the image with the text "Screenshot not uploaded".
    - Keep the plain JS style of the file.
  - The server reads `web/index.html` once at start. For a character page it writes the file with `data-entry="data/entry.json"` added to `<body>`, and `<title>` set to `<name> — <realm label> — Memories` (HTML-escaped). If `index.html` has no `<body>` tag, the server fails at start.
  - Data routes stream from `Blobs` with `http.ServeContent`. The `ETag` is the quoted hex SHA-256 of the file. Compute it on the first request and cache it in memory, keyed by (claim id, file, size, modification time). `Content-Type`: `application/json`, `application/x-ndjson`, `image/jpeg`, `image/png`.
  - Unknown path, deleted character, a file that does not exist: the generic 404 page from Task 1.
- **Edge cases:** a path in upper case (404, slugs are lower case); a trailing `/index.html`; a request for `data/../memories.db`; a character with no trail; a screenshot field with no uploaded file (the image shows the text); `make web-demo`.
- **Tests:**
  - Integration (Go): page and data URLs after an upload; headers (`noindex`, CSP, `ETag` with `304` on `If-None-Match`); 404 cases; 301 without the slash.
  - Viewer: there is no JS test harness. Run `make web-demo` and the server page by hand (Validation steps 3 and 4). The e2e test (Task 10) checks the page HTML and the data URLs.
- **Verify:** `make server-test server-coverage` (unverified); `make web-demo` and open `http://localhost:8765/` (unverified).
- **Definition of done:**
  - [ ] Each Covers item is observably met, including one observation that failed before the task.
  - [ ] Tests listed above exist and follow the Tests guidelines.
  - [ ] Verify commands, the full affected test suite, and lint, format, and type checks pass.
  - [ ] E2E tests pass, or the accepted alternative from Risks is done.
  - [ ] All three reviews pass with no valid open findings.
  - [ ] Docs and config that describe the changed behavior are updated.
  - [ ] Task heading checkbox ticked; changes committed.

### [x] 8. Admin page on the loopback port

- **Outcome:** the admin manages invites, screenshot approvals, keys, characters and claims from a browser through an SSH tunnel.
- **Depends on:** 4 (store), 5 (claims), 6 (screenshots).
- **Covers:** AC11, AC9 (approval part), the CSRF risk, the lost-key, squatting and offensive-text mitigations.
- **Files:** Create `server/internal/admin/` (`admin.go`, `templates/*.html`, `admin_test.go`); edit `server/cmd/memories-server/main.go`.
- **Implementation:**
  - A separate `http.Server` on `MEMORIES_ADMIN_ADDR`. At start, warn in the log when the address is not a loopback address. Inside Docker the address is `0.0.0.0:8081`, and the host publishes it on `127.0.0.1` only (Task 12).
  - `Host` check: accept only `localhost:<port>` and `127.0.0.1:<port>` of the configured port, else `403`.
  - CSRF: a random 32-byte token in a cookie (`HttpOnly`, `SameSite=Strict`, `Path=/`) and a hidden form field. Each POST compares them in constant time and checks that `Origin`, when present, matches the Host. All changes are POST forms that redirect after the change (PRG).
  - Pages (`html/template`, no JS):
    - **Requests:** keys with `pending`, with Approve and Deny.
    - **Keys:** the fingerprint (first 16 hex characters of SHA-256 of the public key), created, last seen, invite note, screenshot state, characters, data and screenshot bytes. Actions: Revoke key, Revoke key and delete its characters, Revoke screenshots.
    - **Invites:** create (note, days valid, default 30), list with state, revoke. The new code shows once, on the page after the create.
    - **Characters:** search by path or guid (admin only). Actions: Delete, Move claim (to a key fingerprint).
  - Revoke screenshots: set `denied`, delete the files under `<claim>/screenshots/` of each claim of the key, remove `screenshot` from the stored records (write the files again with `jsonw`), and set `shot_bytes` to 0.
  - Revoke key: set `revoked`. The key's next signed request gets `403 key_revoked`, and an upload that already runs finishes. The characters stay until an admin deletes them.
  - Revoke key and delete its characters: set `revoked`, then delete each claim of the key with the same code as the owner delete of Task 5 (files first, then the row). Each path then gives 404 and is free to claim.
  - Delete (a character): the same code as the owner delete of Task 5.
  - Move claim: change `key_id`. The target key must exist and not be revoked.
  - Log each admin action with its target (no secret).
- **Edge cases:** a POST with no token; a token from another session; a wrong Host (`evil.example:8081`, a DNS rebind); an approve of a revoked key; a move to the same key; a double submit.
- **Tests:** Integration (`httptest`, real SQLite): each action and its result in the store; CSRF missing or wrong (`403`); Host check; revoke screenshots strips fields and files; move claim lets the new key upload and stops the old one; a revoked key gets `403 key_revoked` on upload, delete, `me` and register; revoke and delete removes every file and claim of the key and its pages give 404; admin delete of one character leaves the key's other characters.
- **Verify:** `make server-test server-coverage` (unverified); `make server-run` and open `http://127.0.0.1:8081/` (unverified).
- **Definition of done:**
  - [ ] Each Covers item is observably met, including one observation that failed before the task.
  - [ ] Tests listed above exist and follow the Tests guidelines.
  - [ ] Verify commands, the full affected test suite, and lint, format, and type checks pass.
  - [ ] E2E tests pass, or the accepted alternative from Risks is done.
  - [ ] All three reviews pass with no valid open findings.
  - [ ] Docs and config that describe the changed behavior are updated.
  - [ ] Task heading checkbox ticked; changes committed.

### [x] 9. Dart upload client and the `memories-upload` CLI

- **Outcome:** pure Dart code registers a key, uploads every changed character of a `latest/` folder, uploads approved screenshots, deletes a character and requests screenshots. A CLI runs it.
- **Depends on:** 5 (upload API), 6 (screenshot API). The signature vector file comes from Task 4.
- **Covers:** AC13, the client side of AC3.
- **Files:**
  - Create `packages/memories_core/lib/src/upload/` (`site.dart`, `key.dart`, `signer.dart`, `client.dart`, `sync.dart`, `state.dart`, `cli.dart`) and `packages/memories_core/bin/memories_upload.dart`.
  - Export the public API from `lib/memories_core.dart`.
  - Edit `packages/memories_core/pubspec.yaml` and `pubspec.lock`: add `http: ^1.6.0` and `pinenacl: ^0.6.0`. Run `fvm dart pub get`.
  - Add tests in `packages/memories_core/test/upload/`.
  - Edit `Makefile` (an `upload` target like `export`) and `README.md`.
- **Implementation:**
  - `parseSite(String) Uri`: accept `https://host[:port]`, and `http://` only for `localhost`, `127.0.0.1` or `[::1]`. Drop a trailing `/`. Reject a path, a query or user info with a plain `FormatException` message.
  - `UploadKey`:
    - `UploadKey.generate()` uses `Random.secure()` for the 32-byte seed and `pinenacl` `SigningKey.fromSeed`.
    - `UploadKey.load(File)` and `save(File)` read and write `{"v": 1, "seed": "<base64url>"}`. The write uses a temp file and a rename. On Linux and macOS, run `chmod 600` on the temp file before the rename.
    - `publicKey` is base64url with no padding.
    - `fingerprint` is the first 16 hex characters of SHA-256 of the public key, the same as Task 8.
  - `signRequest(key, method, pathAndQuery, body, now, nonce)` builds the 4 headers of the Protocol section. The test uses `server/internal/auth/testdata/vector.json` (path `../../server/internal/auth/testdata/vector.json` from the package) and must give the same signature.
  - `UploadClient(Uri site, UploadKey key, {http.Client? client, DateTime Function()? clock})` has these methods: `info()`, `register({String? invite})`, `me()`, `requestScreenshots()`, `uploadCharacter(Directory charDir) → UploadOutcome`, `uploadScreenshot(path, File)`, `deleteCharacter(path)`. Each error becomes an `UploadException(code, message, problems)` with the server's plain message. A network error says "Could not reach <host>. Check the internet connection and the website address."
  - `uploadCharacter` reads the 3 files and builds the JSON body `{"character": ..., "journey": [...], "trail": [...]}`. It gzips the body with `GZipCodec` and sends it.
  - `syncLatest(Directory latest, UploadClient client, UploadState state) → SyncReport`:
    1. Read `latest/index.json`.
    2. For each entry, compute the SHA-256 of the body before gzip. Skip the character when the hash equals `state.sent[path]`. Else upload it and update the state.
    3. When `me().screenshots == 'approved'`, upload each referenced screenshot file of `latest/<id>/screenshots/` whose SHA-256 is not in `state.shots[path]`.
    4. A failure of one character does not stop the others.
    5. The report lists each character's result.
  - `UploadState` is JSON with `{"v": 1, "sites": {"<site>": {"registered": bool, "sent": {...}, "shots": {...}}}}`. One site never uses the state of another site.
  - CLI flags:
    - `--site` (required)
    - `--key FILE` (default `./upload-key.json`; created when missing)
    - `--state FILE` (default `./upload-state.json`)
    - `--latest DIR`
    - `--invite CODE`
    - `--delete PATH`
    - `--request-screenshots`
    - `--help`
  - CLI behavior: run register, then the other actions, in the order of the flags above. The exit codes are 0 (ok), 1 (run error) and 2 (usage). Follow the style of `cli.dart` of the gather.
- **Edge cases:** a site with `http://` on another host (usage error); the key file is damaged (exit 1, it is never overwritten); the state file is damaged (start fresh, warn); a `422` (print the problems); a `409`; a `429` with `Retry-After` (print it); a missing `latest/index.json`; a character folder with no screenshots folder; the clock is wrong (the `401` message).
- **Tests:**
  - Unit: `parseSite`; key round trip and file mode on POSIX; the signature vector; the body and hash are stable across runs.
  - Integration: a `dart:io` `HttpServer` in the test plays the server. It checks each header and records each call. It covers each method, each error code mapping, `syncLatest` skip and resume, the screenshot step on and off, and the CLI exit codes with `testdata/expected` as `latest`.
- **Verify:** `make dart-lint dart-test dart-coverage` (unverified).
- **Definition of done:**
  - [ ] Each Covers item is observably met, including one observation that failed before the task.
  - [ ] Tests listed above exist and follow the Tests guidelines.
  - [ ] Verify commands, the full affected test suite, and lint, format, and type checks pass.
  - [ ] E2E tests pass, or the accepted alternative from Risks is done.
  - [ ] All three reviews pass with no valid open findings.
  - [ ] Docs and config that describe the changed behavior are updated.
  - [ ] Task heading checkbox ticked; changes committed.

### [ ] 10. End-to-end test: the CLI against the real server

- **Outcome:** `make e2e` proves the whole protocol with the real Go server and the real Dart client, locally and in CI.
- **Depends on:** 7 (pages), 8 (the admin approve form for step 6), 9 (client and CLI).
- **Covers:** AC16, the e2e risk.
- **Files:** Create `scripts/e2e-upload.sh`; edit `Makefile` (`e2e` target) and `.github/workflows/ci.yml` (job `e2e`: checkout, setup-go, `./.github/actions/setup-fvm`, `make e2e`).
- **Implementation:**
  - Run with `set -euo pipefail`. Keep all files in `mktemp -d`, and remove them on exit with `trap`.
  - Build `build/memories-server`. Start it with `MEMORIES_REGISTRATION=open`, `MEMORIES_DATA_DIR=<tmp>/data`, `MEMORIES_PUBLIC_ADDR=127.0.0.1:<free port>`, `MEMORIES_ADMIN_ADDR=127.0.0.1:<free port>` and `MEMORIES_SITE_URL=http://127.0.0.1:<port>`. Wait for `/api/v1/info` (30 s at most).
  - Make a writable copy of `testdata/expected` as `latest`.
  - Run these steps. Each step prints its name and fails the script with a clear message:
    1. `memories-upload --site ... --latest <copy>` exits 0.
    2. `curl` checks the page `/wow/eu/brumamar/nandu/`: 200, `data-entry`, and `X-Robots-Tag`.
    3. `data/journey.jsonl` equals `testdata/expected/eu-brumamar-nandu/journey.jsonl` with the `screenshot` fields removed (`jq`), because the key has no approval.
    4. A second run uploads nothing: its report says "unchanged".
    5. Copy `testdata/merge/fresh/journey.jsonl` and the other two files over the copy, run again, and check the bytes against `testdata/merge/expected`.
    6. Run `--request-screenshots`. Approve through the admin page with `curl`: GET the page for the CSRF cookie and token, then POST with `Host: 127.0.0.1:<port>`. Then run an upload again. Both screenshots now give 200 at `data/screenshots/<file>`.
    7. Run `--delete wow/eu/brumamar/nandu`. The page gives 404.
    8. Check that `/` has no character link.
  - Kill the server in the `trap`.
  - Needs `curl` and `jq`; `make check-tools` reports them.
- **Edge cases:** a port in use (pick a free port with a short Python or Go helper); the server fails at start (print its log); a slow CI runner (timeouts).
- **Tests:** the script is the test. Make it fail once on purpose (a wrong expected file) while you write it, to prove it detects a mismatch.
- **Verify:** `make e2e` (unverified).
- **Definition of done:**
  - [ ] Each Covers item is observably met, including one observation that failed before the task.
  - [ ] Tests listed above exist and follow the Tests guidelines.
  - [ ] Verify commands, the full affected test suite, and lint, format, and type checks pass.
  - [ ] E2E tests pass, or the accepted alternative from Risks is done.
  - [ ] All three reviews pass with no valid open findings.
  - [ ] Docs and config that describe the changed behavior are updated.
  - [ ] Task heading checkbox ticked; changes committed.

### [x] 11. App: Website settings, registration and upload

- **Outcome:** a player chooses the website, registers with an invite code, turns on Upload, and the app uploads after each gather. The player copies each character link, removes a character and requests screenshots.
- **Depends on:** 9 (client, state, key).
- **Covers:** AC14, the client part of AC9 and AC10, the macOS sandbox risk, the companion-spec conflict, the lost-key and guessable-URL text.
- **Files:**
  - Create `app/lib/src/upload/upload_service.dart` (interface and `CoreUploadService`) and `app/lib/src/upload/upload_controller.dart`.
  - Create `app/lib/src/ui/website_section.dart` (settings) and `app/lib/src/ui/website_card.dart` (home).
  - Edit `app/lib/src/settings/settings.dart` (add `site`, default `const String.fromEnvironment('WOWJOURNEY_SITE', defaultValue: 'https://wowjourney.xyz')`, and `upload`, default false), `app/lib/src/platform/services.dart` (add `uploader`), `app/lib/src/app.dart` (create the controller; after `GatherController` reaches `done` and `settings.upload` is on and the site is registered, run `syncLatest`), `app/lib/src/ui/home_page.dart`, `app/lib/src/ui/settings_page.dart`, `app/lib/src/ui/messages.dart`, `app/lib/main.dart`.
  - Edit `app/test/support/fakes.dart` (add `FakeUploadService`) and add tests `app/test/upload_controller_test.dart`, `app/test/website_test.dart`.
  - Edit `app/macos/Runner/DebugProfile.entitlements` (add `com.apple.security.network.client`). Check `Release.entitlements` (inspect: the sandbox is off there).
  - Edit `app/pubspec.yaml` only if the app imports `http` directly (it should not; the core holds it). Edit `app/pubspec.lock` after `fvm flutter pub get`.
  - Edit `docs/app-manual-checklist.md`, `README.md` (the WoW Journey app section) and `specs/2026-11-08-companion-app.md` (one line in Must Not: "This rule is lifted for the upload client by `specs/2026-11-08-upload-backend.md`").
- **Implementation:**
  - `UploadService` wraps the core so tests can fake it. It has `info(site)`, `register(site, invite)`, `me(site)`, `sync(site, latestDir)`, `delete(site, path)` and `requestScreenshots(site)`. `CoreUploadService` keeps the key in `<support>/upload-key.json` and the state in `<support>/upload-state.json`, and runs `syncLatest` in `Isolate.run`, like `IsolateGatherService`.
  - `UploadController` (`ChangeNotifier`):
    - States are `UploadState {off, unregistered, idle, uploading, done, failed}`.
    - Fields: `lastUpload`, `characters` (from `me`), `screenshots`, `issues` (plain messages).
    - `uploadNow()` returns null when an upload already runs and never throws.
    - After a failed upload it waits for the next gather. No timer.
  - Settings page, Website section:
    - The website address field, with a Check button that calls `info` and shows the site name, or a plain error.
    - The registration state. In invite mode it has an invite code field and a Register button. In open mode it has a Register button only.
    - The Upload switch. It is disabled until the key is registered.
    - Request screenshots, with the state text.
    - The key fingerprint and the line "If you reinstall the app, ask the website admin to move your characters to your new key."
    - A site change keeps the old site's state and starts as unregistered for a new site.
  - Home page, Website card:
    - The last upload time, an Upload now button and the last result.
    - For each uploaded character: its link with Copy link (`Clipboard.setData`) and Remove from website, with a confirm dialog "Remove <name> from <site>? The page and its data are deleted."
    - The line "Your character pages are unlisted: anybody with the link can open them."
  - All text goes in `messages.dart`. A `422` shows the first 3 problems in plain words. A `409 claimed` says "Another player already uploaded <name> on <realm>. Ask the website admin." A `403 key_revoked` says "The website admin blocked this app's key. Uploads to <site> are off." and turns the Upload switch off.
- **Edge cases:** Upload switch on with no registration (it cannot happen; the switch is off); a gather that fails (no upload); a Watch gather while an upload runs (the next gather starts the next upload); the app quits during an upload (the state is written per character, so the next sync resumes); a site that is not a Memories server (`info` fails with a plain message); the clock is wrong.
- **Tests:**
  - Unit (`upload_controller_test.dart` with `FakeUploadService` and a fake clock): each state change, the upload after a gather, no upload when the switch is off, failure messages.
  - Widget (`website_test.dart`, `pumpApp`): the Website section in both registration modes, the invalid URL message, Register, the Upload switch, Copy link, Remove with the dialog, Request screenshots.
  - Update `settings_store_test.dart` for the new keys and their defaults.
- **Verify:** `make app-lint app-test` (unverified); `make companion` with `make server-run` and `--dart-define=WOWJOURNEY_SITE=http://localhost:8080` (unverified).
- **Definition of done:**
  - [ ] Each Covers item is observably met, including one observation that failed before the task.
  - [ ] Tests listed above exist and follow the Tests guidelines.
  - [ ] Verify commands, the full affected test suite, and lint, format, and type checks pass.
  - [ ] E2E tests pass, or the accepted alternative from Risks is done.
  - [ ] All three reviews pass with no valid open findings.
  - [ ] Docs and config that describe the changed behavior are updated.
  - [ ] Task heading checkbox ticked; changes committed.

### [x] 12. Docker image, deployment example, backup and self-host docs

- **Outcome:** one Docker image runs the server. A compose file with Caddy runs `wowjourney.xyz` or any self-hosted site. The docs explain the setup, the admin tunnel and the backups.
- **Depends on:** 7 (pages need `web/` in the image), 8 (admin port).
- **Covers:** AC15, the disk-loss risk, the proxy IP risk (deployment part).
- **Files:**
  - Create `server/Dockerfile` (build context: the repository root), `deploy/compose.yaml`, `deploy/Caddyfile`, `deploy/.env.example` and `docs/self-host.md`.
  - Create `server/internal/backup/` and edit `server/cmd/memories-server/main.go` (subcommand `backup`).
  - Create `.dockerignore`.
  - Edit `.github/workflows/ci.yml` (a step `docker build -f server/Dockerfile .` in the `server` job) and `README.md`.
- **Implementation:**
  - `Dockerfile`:
    - Build stage: `golang:1.27` pinned by digest, `CGO_ENABLED=0 go build -trimpath -ldflags=-s`.
    - Final stage: `gcr.io/distroless/static-debian12:nonroot` pinned by digest.
    - Copy only `web/index.html`, `web/app.js`, `web/kinds.js` and `web/style.css` to `/app/web`.
    - Set `MEMORIES_WEB_DIR=/app/web`, `MEMORIES_DATA_DIR=/data`, `MEMORIES_ADMIN_ADDR=0.0.0.0:8081`.
    - `VOLUME /data`, `USER nonroot`, `EXPOSE 8080`.
  - `.dockerignore` keeps out `dist-characters/`, `backups/`, `web/tiles/`, `web/mini/`, `web/art/`, `app/`, `addons/` and `.git/`.
  - `compose.yaml` has these services:
    - `server`: the volume `data:/data`, ports `127.0.0.1:8081:8081` only, and env from `.env`.
    - `caddy` (pinned by digest): ports 80 and 443, the volumes `caddy_data` and `caddy_config`.
    - `MEMORIES_TRUSTED_PROXIES` is set to the compose network CIDR.
  - `Caddyfile`: `{$MEMORIES_DOMAIN} { encode zstd gzip; reverse_proxy server:8080 }`.
  - `memories-server backup <dest folder>` writes `memories.db` with `VACUUM INTO`, then copies `characters/` with each file through a temp file. It never stops the server.
  - `docs/self-host.md` covers:
    - The requirements: a VPS, Docker and a domain.
    - Each env var and its default.
    - The first start.
    - The admin tunnel: `ssh -L 8081:127.0.0.1:8081 <host>`, then open `http://127.0.0.1:8081/`.
    - How to make the first invite.
    - The open registration mode.
    - The backup: `docker compose exec server /app/memories-server backup /data/backup-<date>`, then copy the folder off the host. Run it from a daily cron.
    - The restore steps.
    - A note that the players' `latest/` folders can fill the server again.
    - The update order: deploy the server before you release an addon version that adds kinds.
    - The lost-key procedure (move claim).
- **Edge cases:** the data volume is not writable (a clear start error); the admin port is published on `0.0.0.0` by mistake. The Host check does not stop a remote client that sends a forged `Host` header, so the docs warn in bold to publish the port on `127.0.0.1` only; a backup into a folder that exists (error).
- **Tests:** Unit (`backup`): the backup of a live database during writes opens and has the rows; the files are copied. CI: the image builds. Manual: Validation step 8.
- **Verify:** `docker build -f server/Dockerfile -t memories-server .` (unverified); `cd deploy && docker compose config` (unverified); `make server-test` (unverified).
- **Definition of done:**
  - [ ] Each Covers item is observably met, including one observation that failed before the task.
  - [ ] Tests listed above exist and follow the Tests guidelines.
  - [ ] Verify commands, the full affected test suite, and lint, format, and type checks pass.
  - [ ] E2E tests pass, or the accepted alternative from Risks is done.
  - [ ] All three reviews pass with no valid open findings.
  - [ ] Docs and config that describe the changed behavior are updated.
  - [ ] Task heading checkbox ticked; changes committed.

## Validation

Run these checks after the last task.

Automated:

1. `make lint test coverage` passes, including `lint-no-go`, `server-lint`, `server-test` and `server-coverage` (80 %).
2. `make e2e` passes.

Manual:

3. Run `make web-demo`. The local viewer still lists both fixture characters and changes between them by hash.
4. Run `docker compose up` in `deploy/` with `MEMORIES_DOMAIN=localhost`. Then do these checks:
   - `/` shows the home page with the GitHub links.
   - `/robots.txt` disallows all paths but `/`.
   - An unknown character path shows the 404 page.
5. In the app (built with `--dart-define=WOWJOURNEY_SITE=https://localhost`, or with the site field set):
   1. Check the site.
   2. Make an invite on the admin page through the tunnel, then register.
   3. Turn on Upload, then gather.
   4. The character link opens the page with the journey, the trail, the sessions and the counts.
   5. The screenshots show "Screenshot not uploaded".
6. Request screenshots in the app. Approve the key on the admin page, then use Upload now. The screenshots show, and a downloaded screenshot has no EXIF data (`exiftool` shows none).
7. Edit one string in `latest/<id>/journey.jsonl` to hold `|`. Upload now shows a plain problem message, and the page does not change.
8. Remove the character from the app. Its link gives 404. Run `memories-server backup` and restore the backup into an empty volume. The other characters show again.
9. Run the steps of `docs/app-manual-checklist.md` for the Website section.
10. On the admin page, use "Revoke key and delete its characters" on the app's key. Each of its links gives 404. Upload now in the app shows the plain "key revoked" message, and Register gives the same message.

## References

- Ed25519, RFC 8032: https://datatracker.ietf.org/doc/html/rfc8032
- Go `crypto/ed25519`: https://pkg.go.dev/crypto/ed25519
- Go `image.DecodeConfig` (decode the header before the full decode): https://pkg.go.dev/image#DecodeConfig
- Go `image/jpeg` (the encoder writes no EXIF): https://pkg.go.dev/image/jpeg
- OWASP File Upload Cheat Sheet: https://cheatsheetseries.owasp.org/cheatsheets/File_Upload_Cheat_Sheet.html
- `pinenacl` 0.6.0: https://pub.dev/packages/pinenacl — source: https://github.com/ilap/pinenacl-dart
- `modernc.org/sqlite` (pure Go SQLite): https://gitlab.com/cznic/sqlite
- SQLite `VACUUM INTO`: https://sqlite.org/lang_vacuum.html#vacuuminto
- WoW encoding API (no hash function in the game): https://warcraft.wiki.gg/wiki/Category:API_systems/EncodingUtil
- Prior art for account-bound uploads: Warcraft Logs (https://warcraftlogs.com/help/start), wowaudit API keys (https://www.curseforge.com/wow/addons/rclootcouncil-wowaudit)
- WoW Forever in the Battle.net profile API (undocumented, no realm field): https://us.forums.blizzard.com/en/blizzard/t/world-of-warcraft-forever-api-namespace/59774
- Litestream (a backup option for later): https://litestream.io/
- Cloudflare R2 pricing (storage option for later): https://developers.cloudflare.com/r2/pricing/

## Open Decisions

| Decision | Impact |
|---|---|
| The public GitHub repository URL. The repository has no remote. The default `https://github.com/fmartingr/wow-addon-memories` comes from the old Go module path. | The home page links break if the repository has another URL. The value is an env var, so only `deploy/.env.example` and the config default change. |

## Completion

When every task is checked and Validation passes, move this file to `specs/done/` with `git mv` (plain `mv` when the file is untracked). Create `specs/done/` if it does not exist. Commit the move.
