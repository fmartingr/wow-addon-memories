#!/usr/bin/env bash
# Usage: scripts/release-notes.sh <version>
# Prints the top section of CHANGELOG.md, without its heading. Fails when the top "## " heading is not <version>.
# The packager uploads its manual-changelog file whole, so the release workflow gives it this section only, and a
# stale heading cannot publish the notes of the previous release.
set -euo pipefail

version="${1:?usage: scripts/release-notes.sh <version>}"
version="${version#v}"
heading="$(grep -m1 '^## ' CHANGELOG.md | cut -c4- | tr -d '\r' || true)"
if [ "$heading" != "$version" ]; then
	echo "release-notes: the top heading of CHANGELOG.md is '${heading:-none}', expected '$version'" >&2
	exit 1
fi
awk '/^## / { n++; next } n == 1' CHANGELOG.md | sed -e '/./,$!d'
