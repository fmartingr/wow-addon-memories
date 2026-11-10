# Uploader

Back to the [documentation index](README.md).

`memories-upload` sends the characters of a `latest/` folder (the output of the gather) to a website, with the upload
API of [the server](server.md). It is pure Dart, so it needs no Flutter.

```sh
make upload SITE=https://wowjourney.xyz LATEST=dist-characters [INVITE=CODE] [KEY=FILE] [STATE=FILE] [DELETE=PATH] [REQUEST_SCREENSHOTS=1]
# or
fvm dart run packages/memories_core/bin/memories_upload.dart --site https://wowjourney.xyz --latest dist-characters [--invite CODE] [--key FILE] [--state FILE] [--delete PATH] [--only PATH]... [--request-screenshots]
```

- `--site` (required) is `https://host[:port]`. Plain `http://` works for `localhost`, `127.0.0.1` and `[::1]` only.
- `--key` (default `./upload-key.json`) holds the Ed25519 key that identifies you. The tool makes it when it is
  missing, with mode 600 on Linux and macOS. Keep it: without it the characters you uploaded stay with the old key.
  A damaged key file stops the run and is never overwritten.
- `--state` (default `./upload-state.json`) remembers, for each website, whether the key is registered and what was
  sent. A damaged state file gives a warning and a fresh start. The app also keeps there the characters that the
  player chose to upload (`selected`); a file with no such list, from before the choice existed, counts the characters
  it already sent as chosen.
- The tool runs these steps in this order: register (when the state says the key is not registered, or when
  `--invite` is given), upload `--latest`, `--delete PATH` (for example `wow/eu/brumamar/nandu`), and
  `--request-screenshots`. A run with no step but `--site` registers the key when the state says it is not
  registered, and otherwise does nothing.
- `--latest` uploads each character whose data changed since the last run and reports the others as `unchanged`. It
  sends every character of the folder unless `--only PATH` (repeat it for more characters, for example
  `--only wow/eu/brumamar/nandu`) names some: the others are skipped, and a path that matches no character fails the
  run. The tool ignores the selection that the app keeps in the same state file. When
  the website has approved screenshots for the key, it also uploads each screenshot that a record names. An approval
  that comes after the first upload sends each character once more, so the website stores the screenshot links.
- The tool keeps to about 25 signed requests a minute (the server allows 30). A `429` or `503` is waited out with its
  `Retry-After` (5 s without one, at most 70 s) and sent again, and a failed connection is tried 3 times; each wait
  prints `Waiting N s: the website asks to slow down.`. After 10 minutes of waiting the run stops, and the next run
  sends the rest.
- Exit code 0 is a pass, 1 a run error (a rejected upload prints its problems, a `429` that outlasted the waits prints
  `Retry-After`), 2 a usage error.
