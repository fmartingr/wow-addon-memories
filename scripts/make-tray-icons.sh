#!/usr/bin/env bash
# Writes the placeholder tray icons of the app with ImageMagick: the Memories
# icon for Windows and Linux, and a plain black disc for macOS, whose menu bar
# draws a template image from its alpha only.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
out="$root/app/assets/tray"
mkdir -p "$out"

# No dates in the files, so a rerun writes the same bytes.
strip=(-strip -define png:exclude-chunks=date,time)

magick "$root/assets/icon.png" -resize 64x64 "${strip[@]}" "$out/tray_icon.png"
magick -size 44x44 xc:none -fill black -draw "circle 22,22 22,5" "${strip[@]}" \
  "$out/tray_icon_template.png"
