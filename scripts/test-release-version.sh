#!/usr/bin/env bash
# Tests scripts/release-version.sh: the version and pre-release flag of a tag, the refusal of a tag that is not
# 'v' + semver, and the version of a manual run on a branch.
set -euo pipefail

script="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/release-version.sh"
failures=0

expect() {
	local want="$1"
	shift
	local got
	got="$(bash "$script" "$@" 2>/dev/null | xargs)" || {
		echo "FAIL: release-version.sh $* failed, want '$want'" >&2
		failures=$((failures + 1))
		return
	}
	if [ "$got" != "$want" ]; then
		echo "FAIL: release-version.sh $* printed '$got', want '$want'" >&2
		failures=$((failures + 1))
	fi
}

refuse() {
	local want_code="$1"
	shift
	local code=0
	bash "$script" "$@" >/dev/null 2>&1 || code=$?
	if [ "$code" != "$want_code" ]; then
		echo "FAIL: release-version.sh $* exited $code, want $want_code" >&2
		failures=$((failures + 1))
	fi
}

expect "version=1.2.3 prerelease=false" tag v1.2.3 7
expect "version=0.10.0 prerelease=false" tag v0.10.0 7
expect "version=1.0.0-rc.1 prerelease=true" tag v1.0.0-rc.1 7
expect "version=2.0.0-beta-2.x prerelease=true" tag v2.0.0-beta-2.x 7
expect "version=0.0.0-dev.42 prerelease=true" branch main 42

for tag in 1.2.3 v1.2 v1.2.3.4 v01.2.3 v1.02.3 v1.2.3- v1.2.3-rc..1 v1.2.3-01 v1.2.3+build.5 "v1.2.3 " "v1.2.3;id" vx.y.z v; do
	refuse 1 tag "$tag" 7
done
refuse 2 tag v1.2.3
refuse 2 tag v1.2.3 abc

if [ "$failures" -gt 0 ]; then
	echo "test-release-version: $failures failure(s)" >&2
	exit 1
fi
echo "test-release-version: ok"
