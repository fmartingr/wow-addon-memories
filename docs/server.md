# The server

Back to the [documentation index](README.md).

`server/` is a Go web server for the WoW Journey website. It serves the home page, `robots.txt`, `/api/v1/info`
and the signed API below, and answers every other path with one 404 page (a JSON error under `/api/`). Every response carries the security
headers. Run it with `make server-run`, then open <http://localhost:8080/>. The admin page listens on
`MEMORIES_ADMIN_ADDR` (default `127.0.0.1:8081`; the log warns when the address is not loopback). It has plain HTML
forms and no JavaScript, and it accepts only `localhost:<port>` and `127.0.0.1:<port>` as `Host`, so reach it with an
SSH tunnel. There the admin makes and revokes invite codes, approves, denies and revokes screenshots (also for a key that sent no request), revokes keys
(a revoked key loses all its characters and screenshots), deletes characters, moves a claim to another key, sets the storage limits of one key and sets open registration. Every list
searches (`?q=`) and shows 25 rows a page.

A character page `/<flavor>/<region>/<realm>/<name>/` shows the viewer of `web/` with three tabs: Summary, Journey map and
Heatmaps. To see it while you work, run `make local-up`, then `make upload SITE=http://localhost:8080 LATEST=<latest folder>`,
and open the character URL that the command prints. The page loads its files from `/_/`. A character page also loads the
Wowhead tooltip script to name the gear; no other page loads a third-party script.

The server keeps its data in `MEMORIES_DATA_DIR`: the SQLite database `memories.db` (keys, invite codes, claims and
the nonces of signed requests). The upload API keeps the character files in `characters/`. The API accepts only requests that
carry the 4 `Memories-*` signature headers of an Ed25519 key. `POST /api/v1/register` registers a key (with a
single-use invite code, or with no code while open registration is on; see [`self-host.md`](self-host.md), "Open
registration"), `GET /api/v1/me` lists the key's characters, its screenshot state and `open` (true for a key with no invite), and
`POST /api/v1/screenshots/request` asks for screenshot approval. An open key gets `403 screenshots_unavailable` there,
and on a screenshot upload until the admin approves its screenshots. `POST /api/v1/characters` uploads one character (gzip, `Content-Encoding: gzip`): the server checks every record, merges it into the stored data of that address and writes the files itself; the first key to upload an address owns it, and only that key can upload it again or delete it with `DELETE /api/v1/characters/<flavor>/<region>/<realm>/<name>`. A key with no screenshot approval gets the `screenshot` field removed from the records it uploads. An upload that is too big, or that would grow the stored files of its character past twice `MEMORIES_MAX_DECODED_BYTES`, gets `413`; one over a quota of the key gets `507`. A request with a bad signature, a time more than 300 s
off or a nonce seen in the last 600 s gets `401`; a revoked key gets `403 key_revoked`. A key may send
`MEMORIES_RATE_SIGNED_PER_MINUTE` signed requests a minute, an address may try `MEMORIES_RATE_REGISTER_PER_HOUR`
registrations an hour and send `MEMORIES_RATE_PUBLIC_PER_MINUTE` requests a minute (pages and API); more gets `429` with `Retry-After`.
The viewer files under `/_/` (code, fonts and map art) are not part of that limit.
The server reads the client address from the connection, and from `X-Forwarded-For` only when the connection comes from
an address in `MEMORIES_TRUSTED_PROXIES`.

It reads these environment variables; an unset or empty one takes its default, and a bad value stops the server with
exit code 2. The size limits and quotas other than the rate limits apply to the upload API:

| Variable | Default | Meaning |
|---|---|---|
| `MEMORIES_PUBLIC_ADDR` | `:8080` | Public listener. |
| `MEMORIES_ADMIN_ADDR` | `127.0.0.1:8081` | Admin listener. |
| `MEMORIES_DATA_DIR` | `./data` | Data folder. |
| `MEMORIES_WEB_DIR` | `../web` | Folder with the viewer files. The map art is in its `map/` folder (see [`self-host.md`](self-host.md), "Map art"). |
| `MEMORIES_SITE_URL` | `http://localhost:8080` | Public address of the site: `http` or `https`, no path. A trailing `/` is dropped. |
| `MEMORIES_SITE_NAME` | `WoW Journey` | Name of the site. |
| `MEMORIES_GITHUB_URL` | `https://github.com/fmartingr/wow-addon-memories` | Repository; the home page links to it and to its `/releases/latest`. |
| `MEMORIES_CURSEFORGE_URL` | `https://www.curseforge.com/wow/addons/memories` | The addons on CurseForge; the home page links to it. |
| `MEMORIES_EXAMPLE_URL` | `https://wowjourney.xyz/forever/eu/brumamar/neral` | A character page that the home page shows as an example. |
| `MEMORIES_REGISTRATION` | `invite` | `invite` or `open`: the open registration switch on the first start. The admin Settings page changes it after that. |
| `MEMORIES_TRUSTED_PROXIES` | empty | Comma-separated CIDR list of proxies whose `X-Forwarded-For` is trusted. |
| `MEMORIES_SENTRY_DSN` | empty | Sentry DSN. When set, the server sends every error log line and every handler panic to Sentry, with no header, query, body or request path. Empty turns Sentry off. |
| `MEMORIES_SENTRY_ENVIRONMENT` | `production` | Sentry environment of the events. |
| `MEMORIES_MAX_UPLOAD_BYTES` | 16 MiB | Largest upload request. |
| `MEMORIES_MAX_SHOT_BYTES` | 15 MiB | Largest screenshot request. |
| `MEMORIES_MAX_PIXELS` | 50,000,000 | Largest screenshot, in pixels. |
| `MEMORIES_MAX_DECODED_BYTES` | 64 MiB | Largest upload after gzip is undone. |
| `MEMORIES_MAX_TEXT` | 512 | Longest text value in an upload, in bytes. Keep it at 400 or more: a player note (`un`) has up to 400 bytes. |
| `MEMORIES_MAX_RECORDS` | 500,000 | Journey records in one upload. |
| `MEMORIES_MAX_CHUNKS` | 50,000 | Trail chunks in one upload. |
| `MEMORIES_MAX_POINTS` | 20,000 | Points in one trail chunk. |
| `MEMORIES_MAX_CHARACTERS_PER_KEY` | 50 | Characters of one key. |
| `MEMORIES_MAX_DATA_BYTES_PER_KEY` | 512 MiB | Journey data of one key with an invite. The admin Settings page sets the limit of an open key. A limit set for one key on the Keys page replaces both. |
| `MEMORIES_MAX_SHOT_BYTES_PER_KEY` | 5 GiB | Screenshots of one key. A limit set for one key on the Keys page replaces it. |
| `MEMORIES_MAX_CONCURRENT_UPLOADS` | 2 | Uploads that the server unpacks and stores at the same time. A full-size upload takes about 800 MB of memory while it is handled; a further upload waits up to 10 s for a free place, then gets `503` with `Retry-After`. |
| `MEMORIES_RATE_SIGNED_PER_MINUTE` | 30 | Signed requests a minute for one key. |
| `MEMORIES_RATE_REGISTER_PER_HOUR` | 10 | Registrations an hour from one IP. |
| `MEMORIES_RATE_PUBLIC_PER_MINUTE` | 600 | Requests a minute from one IP to the public listener (pages and API). |

To run your own site, build the Docker image (`docker build -f server/Dockerfile -t memories-server .`) or use the
compose file in `deploy/` (the server behind Caddy). `memories-server backup <new folder>` copies the database and the
character files while the server runs. [`self-host.md`](self-host.md) has the setup, the admin tunnel, the
backup and the restore.

The design is in [`specs/2026-11-08-upload-backend.md`](../specs/2026-11-08-upload-backend.md).
