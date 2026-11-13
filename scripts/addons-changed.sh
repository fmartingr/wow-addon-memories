#!/usr/bin/env bash
# Usage: scripts/addons-changed.sh <tag>
# Prints 'previous=<tag>' and 'changed=<true|false>' for $GITHUB_OUTPUT. changed is true when the addon files
# (addons/ and .pkgmeta) differ between <tag> and the previous release tag, or when there is no previous tag.
# A release tag (v1.2.3) compares with the previous release tag and skips pre-release tags, so a release after an
# rc still uploads the files that the rc uploaded as a beta. A pre-release tag compares with the previous tag of any kind.
# Run it in a clone with the full history and the tags.
set -euo pipefail

if [ "$#" -ne 1 ]; then
	echo "usage: scripts/addons-changed.sh <tag>" >&2
	exit 2
fi
tag="$1"
git rev-parse -q --verify "refs/tags/$tag" >/dev/null || {
	echo "addons-changed: there is no tag '$tag'" >&2
	exit 2
}

exclude=()
case "$tag" in
*-*) ;;
*) exclude=(--exclude '*-*') ;;
esac
previous="$(git describe --tags --abbrev=0 --match 'v*' ${exclude[@]+"${exclude[@]}"} "$tag^" 2>/dev/null || true)"

echo "previous=$previous"
if [ -z "$previous" ] || ! git diff --quiet "$previous" "$tag" -- addons .pkgmeta; then
	echo "changed=true"
else
	echo "changed=false"
fi
