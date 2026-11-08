#!/usr/bin/env bash
# Usage: scripts/release-version.sh <ref type> <ref name> <run number>
# Prints 'version=<version>' and 'prerelease=<true|false>' for $GITHUB_OUTPUT.
# A tag must be 'v' + semver (vMAJOR.MINOR.PATCH[-PRERELEASE]); its version is the tag without 'v', and a tag with
# a pre-release part is a pre-release. Build metadata (+...) is refused: Flutter reads '+' in --build-name as the
# build number. Any other ref (a manual run on a branch) gets 0.0.0-dev.<run number>.
set -euo pipefail

if [ "$#" -ne 3 ]; then
	echo "usage: scripts/release-version.sh <ref type> <ref name> <run number>" >&2
	exit 2
fi
ref_type="$1"
ref_name="$2"
run_number="$3"

if ! [[ "$run_number" =~ ^[0-9]+$ ]]; then
	echo "release-version: the run number '$run_number' is not a number" >&2
	exit 2
fi

if [ "$ref_type" != tag ]; then
	echo "version=0.0.0-dev.$run_number"
	echo "prerelease=true"
	exit 0
fi

num='(0|[1-9][0-9]*)'
ident='(0|[1-9][0-9]*|[0-9]*[A-Za-z-][0-9A-Za-z-]*)'
pattern="^v$num\\.$num\\.$num(-$ident(\\.$ident)*)?\$"
if ! [[ "$ref_name" =~ $pattern ]]; then
	echo "release-version: the tag '$ref_name' is not 'v' + semver, for example v1.2.3 or v1.2.3-rc.1" >&2
	exit 1
fi

version="${ref_name#v}"
echo "version=$version"
if [[ "$version" == *-* ]]; then
	echo "prerelease=true"
else
	echo "prerelease=false"
fi
