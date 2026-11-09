---
name: theme-parity
description: Compare the website theme (web/base.css, web/style.css) with the Flutter app theme (app/lib/src/theme) and fix any difference. Use after a change of colours, fonts, buttons, panels, tabs or any component of either UI, before a release, or when the user asks whether the app and the website look the same.
---

# Theme parity

The website is the source of truth for the look. The app copies it. This skill finds where the two differ and fixes the
side that is wrong.

## 1. Run the automatic check

```
make theme-check
```

It runs two scripts that need only Node:

- `scripts/gen-app-theme.mjs --check`: `app/lib/src/theme/tokens.dart` is made from `web/base.css` and `web/lib/format.mjs`.
  It fails when the file is old. Fix: `make app-theme`.
- `scripts/theme-parity.mjs`: compares six things and prints `MISMATCH` lines.

| Area | What it compares |
|---|---|
| tokens | each colour of `:root` in `web/base.css` with `Tokens` in `tokens.dart` |
| game | class colours and quality colours of `web/lib/format.mjs` with `tokens.dart` |
| fonts | the families and files of the website with `app/pubspec.yaml` and `app/assets/fonts/` |
| components | each entry of `docs/theme-parity.json`: its values must be in the CSS rule and in the Dart file |
| coverage | each class of `web/base.css` must be a component or `webOnly` in `docs/theme-parity.json` |
| hard-coded | no `Color(0x...)` or `Colors.*` in `app/lib/src` outside `app/lib/src/theme` |

`node scripts/theme-parity.mjs --json` gives the same rows as data.

## 2. Fix each mismatch

- **A token or font differs:** change `web/base.css` (the source), run `make app-theme`, then run the check again. Do not
  edit `tokens.dart` by hand.
- **A component value differs:** decide which side is right (the website, unless the user says otherwise). Change the
  other side to the same value. The Dart literals are in `ak_theme.dart` and `ak_widgets.dart`.
- **A new web class has no entry (coverage):** add a Flutter component or theme entry for it, then add it to
  `docs/theme-parity.json` as a component. If the app has no use for it, add it to `webOnly` with a one-line reason.
- **A hard-coded colour in a screen:** move it to `app/lib/src/theme` (a token or a component) and use that.
- **A new component in the app:** add it to `docs/theme-parity.json` (`components` with a web rule, or `appOnly`).

## 3. Compare the look with pictures

The check compares values, not pixels. For a change of layout or a new component, look at both:

1. App screens: `make app-shots THEME_SHOTS=/tmp/shots`. It writes `overview.png`, `website.png`, `settings.png` and
   `overview-narrow.png` with the real fonts.
2. Website: start a server and take a picture of the landing page (and a character page when one is uploaded):
   ```
   cd server && go build -o /tmp/memories-server ./cmd/memories-server
   MEMORIES_DATA_DIR=$(mktemp -d) MEMORIES_WEB_DIR=../web MEMORIES_PUBLIC_ADDR=127.0.0.1:18080 \
     MEMORIES_ADMIN_ADDR=127.0.0.1:18081 /tmp/memories-server &
   node scripts/theme-shot.mjs http://127.0.0.1:18080/ /tmp/shots/landing.png 1000 900
   ```
   Stop the server by its process ID when you are done. `theme-shot.mjs` needs Firefox and stops only its own copy.
3. Read the pictures side by side (Read tool on each PNG) and check:

| Item | Same in both? |
|---|---|
| Page background, panel fill and the double gold border | |
| Headings: Cinzel capitals, gold, letter-spaced, a line under a panel title | |
| Body text: Alegreya Sans, colour, size | |
| Primary button: gold gradient, dark Cinzel capitals | |
| Normal button: bronze gradient, gold-light Cinzel capitals, 44 px high | |
| Tabs: raised, gold edge on the selected one | |
| Tags and class colours | |
| Focus ring (gold-light) and disabled look (40 % opacity) | |
| Narrow width (400 px app, 360 px web): no overflow, tabs still readable | |

## 4. Finish

Run `make theme-check`, `make web-test` and, in `app/`, `fvm flutter test`. Say which items differed, which side you
changed, and which rows of the picture table you could not check.

## Notes

- The theme tests are `web/test/theme-parity.test.mjs` (the script catches a drift) and `app/test/theme_test.dart`.
- `FilledButton.tonal` has the same look as `FilledButton` in the app, because a Flutter button theme has one style.
- Flutter cannot draw a CSS gradient on a panel `Card`. The panel is a flat surface colour with the same border lines.
