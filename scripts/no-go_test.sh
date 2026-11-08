#!/usr/bin/env bash
# Tests scripts/no-go.sh in temporary git repositories: Go files under server/ pass, Go files anywhere else fail.
set -euo pipefail
# A git hook exports these; inherited, they would point the temporary repositories at the real index.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR GIT_PREFIX

script="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/no-go.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
failures=0

# check <want exit code> <description> <file>...: tracks the files in a new repository and runs the script there.
check() {
	local want="$1" desc="$2"
	shift 2
	local repo="$work/repo"
	rm -rf "$repo"
	mkdir -p "$repo"
	git -C "$repo" init --quiet
	local f
	for f in "$@"; do
		mkdir -p "$repo/$(dirname "$f")"
		: >"$repo/$f"
		git -C "$repo" add -- "$f"
	done
	local code=0
	(cd "$repo" && bash "$script") >"$work/out" 2>&1 || code=$?
	if [ "$code" != "$want" ]; then
		echo "FAIL: $desc: exit code $code, want $want" >&2
		sed 's/^/  /' "$work/out" >&2
		failures=$((failures + 1))
	elif [ "$want" = 1 ]; then
		for f in "$@"; do
			case "$f" in
			server/*)
				if grep -qxF "$f" "$work/out"; then
					echo "FAIL: $desc: the output names $f, which is allowed" >&2
					failures=$((failures + 1))
				fi
				;;
			*)
				grep -qxF "$f" "$work/out" || {
					echo "FAIL: $desc: the output does not name $f" >&2
					failures=$((failures + 1))
				}
				;;
			esac
		done
	fi
}

check 0 "no files" README.md
check 0 "a Go file in server/" server/a.go
check 0 "a nested Go file in server/" server/internal/x/a.go
check 0 "go.mod and go.sum in server/" server/go.mod server/go.sum
check 1 "a Go file outside server/" x/a.go
check 1 "a Go file at the root" a.go
check 1 "go.mod at the root" go.mod
check 1 "go.sum at the root" go.sum
check 1 "go.mod in another folder" tools/go.mod
check 1 "a Go file in a folder named server below another one" x/server/a.go
check 1 "a Go file outside server/ next to one in server/" server/a.go x/a.go

# An untracked Go file is not in the index and does not count.
repo="$work/untracked"
mkdir -p "$repo/x"
git -C "$repo" init --quiet
: >"$repo/x/a.go"
if ! (cd "$repo" && bash "$script") >/dev/null 2>&1; then
	echo "FAIL: an untracked Go file made the script fail" >&2
	failures=$((failures + 1))
fi

if [ "$failures" -ne 0 ]; then
	echo "no-go_test: $failures failure(s)" >&2
	exit 1
fi
echo "no-go_test: ok"
