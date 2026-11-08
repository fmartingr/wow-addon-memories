#!/usr/bin/env bash
# Fails when the git index of the current repository holds a Go file, go.mod or go.sum.
# The converter is the Dart core; Go stays out so that the project builds with one toolchain.
set -euo pipefail

root="$(git rev-parse --show-toplevel)"
found="$(git -C "$root" ls-files -- ':(glob)**/*.go' ':(glob)**/go.mod' ':(glob)**/go.sum')"

if [ -n "$found" ]; then
	echo "no-go: the repository tracks Go files:" >&2
	echo "$found" >&2
	exit 1
fi
echo "no-go: no Go files tracked"
