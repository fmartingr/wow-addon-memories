#!/usr/bin/env bash
# Fails when the git index of the current repository holds a Go file, go.mod or go.sum outside server/.
# The gather is Dart; Go is only for the server in server/.
set -euo pipefail

root="$(git rev-parse --show-toplevel)"
found="$(git -C "$root" ls-files -- ':(glob)**/*.go' ':(glob)**/go.mod' ':(glob)**/go.sum' ':(exclude)server/**')"

if [ -n "$found" ]; then
	echo "no-go: Go files are tracked outside server/:" >&2
	echo "$found" >&2
	exit 1
fi
echo "no-go: no Go files tracked outside server/"
