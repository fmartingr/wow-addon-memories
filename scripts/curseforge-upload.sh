#!/usr/bin/env bash
# Usage: scripts/curseforge-upload.sh <addon zip> <version> <prerelease: true|false>
# Uploads the addon zip to the CurseForge project as a new file. The game version comes from the "## Interface" line
# of addons/Memories/Memories.toc: 16001 is 1.60.1, which the CurseForge game version list gives an id for.
# Environment:
#   CF_API_TOKEN              the CurseForge API token (a repository secret)
#   CURSEFORGE_PROJECT_ID     the id of the CurseForge project (a repository variable)
#   CURSEFORGE_GAME_VERSIONS  optional: the game version ids, comma-separated, in place of the lookup
#   CURSEFORGE_API            optional: the API root, https://wow.curseforge.com by default
#   RELEASE_URL               optional: the page of the GitHub release, for the changelog
set -euo pipefail

if [ "$#" -ne 3 ]; then
	echo "usage: scripts/curseforge-upload.sh <addon zip> <version> <prerelease: true|false>" >&2
	exit 2
fi
zip="$1"
version="$2"
prerelease="$3"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
api="${CURSEFORGE_API:-https://wow.curseforge.com}"

error() {
	echo "::error::curseforge-upload: $*" >&2
	exit 1
}

[ -n "${CF_API_TOKEN:-}" ] || error "the secret CF_API_TOKEN is empty or not set; see docs/releasing.md"
[[ "${CURSEFORGE_PROJECT_ID:-}" =~ ^[0-9]+$ ]] ||
	error "the variable CURSEFORGE_PROJECT_ID is not a project id ('${CURSEFORGE_PROJECT_ID:-}'); see docs/releasing.md"
[ -f "$zip" ] || error "no file $zip"
case "$prerelease" in
true) release_type=beta ;;
false) release_type=release ;;
*) error "prerelease must be true or false, not '$prerelease'" ;;
esac

# The interface number XYYZZ is the game version X.YY.ZZ without leading zeros: 16001 is 1.60.1, 11507 is 1.15.7.
interface="$(sed -n 's/^## Interface: *\([0-9]*\).*/\1/p' "$root/addons/Memories/Memories.toc" | head -n 1)"
[[ "$interface" =~ ^[0-9]{5,6}$ ]] || error "addons/Memories/Memories.toc has no '## Interface' number"
game_version="$((interface / 10000)).$((interface / 100 % 100)).$((interface % 100))"

ids="${CURSEFORGE_GAME_VERSIONS:-}"
if [ -z "$ids" ]; then
	list="$(curl -fsS -H "X-Api-Token: $CF_API_TOKEN" "$api/api/game/versions")" ||
		error "the game version list of $api did not load"
	ids="$(jq -r --arg v "$game_version" '[.[] | select(.name == $v) | .id] | map(tostring) | join(",")' <<<"$list")"
	[ -n "$ids" ] || error "CurseForge has no game version $game_version (from Interface $interface); set CURSEFORGE_GAME_VERSIONS"
fi
[[ "$ids" =~ ^[0-9]+(,[0-9]+)*$ ]] || error "the game version ids '$ids' are not a list of numbers"

changelog="Memories $version."
if [ -n "${RELEASE_URL:-}" ]; then
	changelog="$changelog See the [release notes]($RELEASE_URL)."
fi
metadata="$(mktemp)"
trap 'rm -f "$metadata"' EXIT
jq -n --arg name "Memories $version" --arg changelog "$changelog" --arg type "$release_type" --arg ids "$ids" \
	'{displayName: $name, changelog: $changelog, changelogType: "markdown", releaseType: $type,
	  gameVersions: ($ids | split(",") | map(tonumber))}' >"$metadata"

reply="$(curl -fsS -H "X-Api-Token: $CF_API_TOKEN" -F "metadata=<$metadata" -F "file=@$zip" \
	"$api/api/projects/$CURSEFORGE_PROJECT_ID/upload-file")" || error "the upload to project $CURSEFORGE_PROJECT_ID failed"
file_id="$(jq -r '.id // empty' <<<"$reply")"
[ -n "$file_id" ] || error "the upload gave no file id: $reply"
echo "Uploaded $zip to CurseForge project $CURSEFORGE_PROJECT_ID as file $file_id ($release_type, game version $game_version)."
