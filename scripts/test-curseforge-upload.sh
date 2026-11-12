#!/usr/bin/env bash
# Tests scripts/curseforge-upload.sh with a fake curl: the game version lookup from the TOC, the metadata of the
# upload, the release type, and the errors for missing settings.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="$root/scripts/curseforge-upload.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

failures=0
fail() {
	echo "FAIL: $*" >&2
	failures=$((failures + 1))
}

# The fake curl writes each call to calls.log, the metadata of an upload to metadata.json, and answers like the API.
mkdir -p "$work/bin"
cat >"$work/bin/curl" <<'FAKE'
#!/usr/bin/env bash
echo "$*" >>"$FAKE_DIR/calls.log"
for arg in "$@"; do
	case "$arg" in
	metadata=\<*) cat "${arg#metadata=<}" >"$FAKE_DIR/metadata.json" ;;
	esac
done
case "$*" in
*/api/game/versions*) printf '%s' "${FAKE_VERSIONS:-[]}" ;;
*/upload-file*)
	[ "${FAKE_UPLOAD_FAILS:-}" = 1 ] && exit 22
	printf '{"id":4242}'
	;;
esac
FAKE
chmod +x "$work/bin/curl"
echo zip >"$work/addons.zip"

run() {
	rm -f "$work/calls.log" "$work/metadata.json"
	env PATH="$work/bin:$PATH" FAKE_DIR="$work" CF_API_TOKEN="${TOKEN-secret}" CURSEFORGE_PROJECT_ID="${PROJECT-123}" \
		CURSEFORGE_GAME_VERSIONS="${IDS-}" FAKE_VERSIONS="${VERSIONS-}" FAKE_UPLOAD_FAILS="${UPLOAD_FAILS-}" \
		RELEASE_URL="${URL-}" bash "$script" "$@"
}

interface="$(sed -n 's/^## Interface: *\([0-9]*\).*/\1/p' "$root/addons/Memories/Memories.toc" | head -n 1)"
want="$((interface / 10000)).$((interface / 100 % 100)).$((interface % 100))"
VERSIONS="[{\"id\":1,\"name\":\"1.15.7\"},{\"id\":77,\"name\":\"$want\"},{\"id\":78,\"name\":\"$want\"}]"

out="$(URL=https://example.test/r run "$work/addons.zip" 1.2.3 false 2>&1)" || fail "a release upload failed: $out"
grep -q "file 4242" <<<"$out" || fail "no file id in the output: $out"
grep -q "/api/projects/123/upload-file" "$work/calls.log" || fail "the upload did not go to project 123"
grep -q "X-Api-Token: secret" "$work/calls.log" || fail "the token was not sent"
[ "$(jq -c .gameVersions "$work/metadata.json")" = "[77,78]" ] || fail "game versions are $(jq -c .gameVersions "$work/metadata.json"), want [77,78] for $want"
[ "$(jq -r .releaseType "$work/metadata.json")" = release ] || fail "the release type is not release"
[ "$(jq -r .displayName "$work/metadata.json")" = "Memories 1.2.3" ] || fail "the display name is wrong"
grep -q "https://example.test/r" <<<"$(jq -r .changelog "$work/metadata.json")" || fail "the changelog has no link"

run "$work/addons.zip" 1.2.3-rc.1 true >/dev/null 2>&1 || fail "a pre-release upload failed"
[ "$(jq -r .releaseType "$work/metadata.json")" = beta ] || fail "a pre-release is not a beta"

IDS=5,6 run "$work/addons.zip" 1.2.3 false >/dev/null 2>&1 || fail "an upload with set game versions failed"
grep -q "game/versions" "$work/calls.log" && fail "set game versions still looked the list up"
[ "$(jq -c .gameVersions "$work/metadata.json")" = "[5,6]" ] || fail "set game versions were not used"

expect_error() {
	local what="$1" pattern="$2"
	shift 2
	if out="$("$@" 2>&1)"; then
		fail "$what did not fail"
	elif ! grep -q "$pattern" <<<"$out"; then
		fail "$what failed with '$out', want '$pattern'"
	fi
}
TOKEN='' expect_error "an empty token" "CF_API_TOKEN" run "$work/addons.zip" 1.2.3 false
PROJECT='' expect_error "a missing project id" "CURSEFORGE_PROJECT_ID" run "$work/addons.zip" 1.2.3 false
PROJECT=abc expect_error "a project id that is not a number" "CURSEFORGE_PROJECT_ID" run "$work/addons.zip" 1.2.3 false
VERSIONS='[{"id":1,"name":"9.9.9"}]' expect_error "an unknown game version" "no game version $want" run "$work/addons.zip" 1.2.3 false
expect_error "a missing zip" "no file" run "$work/none.zip" 1.2.3 false
expect_error "a bad prerelease flag" "true or false" run "$work/addons.zip" 1.2.3 maybe
IDS='5;6' expect_error "bad game version ids" "not a list of numbers" run "$work/addons.zip" 1.2.3 false
UPLOAD_FAILS=1 expect_error "a failed upload" "upload to project 123 failed" run "$work/addons.zip" 1.2.3 false

if [ "$failures" -gt 0 ]; then
	echo "test-curseforge-upload: $failures failures" >&2
	exit 1
fi
echo "test-curseforge-upload: ok (game version $want)"
