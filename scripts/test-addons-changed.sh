#!/usr/bin/env bash
# Tests scripts/addons-changed.sh in a new git repository: a first tag, a tag with no addon change, a tag with an
# addon change, a change of .pkgmeta, and the comparison of a release tag after a pre-release tag.
set -euo pipefail

script="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/addons-changed.sh"
repo="$(mktemp -d)"
trap 'rm -rf "$repo"' EXIT
failures=0

g() { git -C "$repo" -c user.name=test -c user.email=test@example.com -c commit.gpgsign=false -c tag.gpgsign=false "$@"; }

# commit FILE TEXT TAG: writes TEXT to FILE, commits it and tags the commit.
commit() {
	mkdir -p "$repo/$(dirname "$1")"
	echo "$2" >"$repo/$1"
	g add -A
	g commit -q -m "$3"
	g tag "$3"
}

expect() {
	local tag="$1" want="$2" got
	got="$(cd "$repo" && bash "$script" "$tag" | xargs)" || {
		echo "FAIL: addons-changed.sh $tag failed, want '$want'" >&2
		failures=$((failures + 1))
		return
	}
	if [ "$got" != "$want" ]; then
		echo "FAIL: addons-changed.sh $tag printed '$got', want '$want'" >&2
		failures=$((failures + 1))
	fi
}

g init -q
commit addons/Memories/Memories.lua "a" v0.1.0
commit server/main.go "server" v0.1.1
commit addons/Memories/Memories.lua "b" v0.2.0
commit .pkgmeta "package-as: Memories" v0.2.1
commit addons/Memories/Memories.lua "c" v0.3.0-rc.1
commit server/main.go "server 2" v0.3.0-rc.2
commit docs/x.md "docs" v0.3.0

expect v0.1.0 "previous= changed=true"
expect v0.1.1 "previous=v0.1.0 changed=false"
expect v0.2.0 "previous=v0.1.1 changed=true"
expect v0.2.1 "previous=v0.2.0 changed=true"
expect v0.3.0-rc.1 "previous=v0.2.1 changed=true"
expect v0.3.0-rc.2 "previous=v0.3.0-rc.1 changed=false"
expect v0.3.0 "previous=v0.2.1 changed=true"

code=0
(cd "$repo" && bash "$script" v9.9.9 >/dev/null 2>&1) || code=$?
if [ "$code" != 2 ]; then
	echo "FAIL: addons-changed.sh of a missing tag exited $code, want 2" >&2
	failures=$((failures + 1))
fi

if [ "$failures" -gt 0 ]; then
	echo "test-addons-changed: $failures failure(s)" >&2
	exit 1
fi
echo "test-addons-changed: ok"
