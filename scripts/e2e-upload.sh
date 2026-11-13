#!/usr/bin/env bash
# End-to-end test: the memories-upload CLI against the real Go server. Run it with `make e2e`.
# Needs go, fvm, curl, jq and python3.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXPECTED="$ROOT/testdata/expected"
MERGE="$ROOT/testdata/merge"
CORE="$ROOT/packages/memories_core"
SERVER_BIN="$ROOT/build/memories-server"
CHAR_PATH="wow/eu/brumamar/nandu"
CHAR_ID="eu-brumamar-nandu"
OTHER_PATH="wow/eu/los-errantes/nandu"
IMAGE="$ROOT/server/internal/images/testdata/small.jpg"

TMP="$(mktemp -d)"
SERVER_PID=""
STEP="setup"
REPORTED=0

report() {
	REPORTED=1
	echo "e2e: FAILED at step $STEP: $*" >&2
	if [ -f "$TMP/server.log" ]; then
		echo "--- server log ---" >&2
		cat "$TMP/server.log" >&2
		echo "--- end of server log ---" >&2
	fi
}

# A command that set -e stops the script on gets the same report as a fail call.
cleanup() {
	local code=$?
	if [ "$code" != 0 ] && [ "$REPORTED" = 0 ]; then
		report "a command exited with status $code."
	fi
	if [ -n "$SERVER_PID" ]; then
		kill "$SERVER_PID" 2>/dev/null || true
		wait "$SERVER_PID" 2>/dev/null || true
	fi
	rm -rf "$TMP"
	exit "$code"
}
trap cleanup EXIT

fail() {
	report "$@"
	exit 1
}

step() {
	STEP="$1"
	echo "==> $1"
}

for tool in go fvm curl jq python3; do
	command -v "$tool" >/dev/null || fail "$tool is required but not installed."
done

curl_() { curl --noproxy '*' -sS --max-time 20 "$@"; }

upload() {
	"$TMP/memories-upload" --site "$SITE" --key "$TMP/upload-key.json" --state "$TMP/upload-state.json" "$@"
}

# run_upload runs the CLI, prints its output and leaves it in $OUT.
run_upload() {
	local status=0
	OUT="$(upload "$@" 2>&1)" || status=$?
	echo "$OUT" | sed 's/^/    /'
	return "$status"
}

# same_journey_without_shots FILE WANT: compares the lines of FILE and WANT as parsed values with sorted keys (the server
# writes canonical JSON with escaped HTML characters; jq does not), and ignores the screenshot field of both. A changed,
# missing, extra or reordered record shows in the diff.
same_journey_without_shots() {
	jq -S -c 'del(.screenshot)' "$2" >"$TMP/journey.want" || return 1
	jq -S -c 'del(.screenshot)' "$1" >"$TMP/journey.got" || return 1
	[ -s "$TMP/journey.want" ] || fail "the expected journey $2 is empty, so the comparison would prove nothing."
	diff "$TMP/journey.want" "$TMP/journey.got" >"$TMP/journey.diff" || { head -n 20 "$TMP/journey.diff" >&2; return 1; }
}

# upload_old_then_fresh deletes the character, then uploads testdata/merge/old and testdata/merge/fresh in turn. The
# server holds the fixture, but testdata/merge/expected is the merge of old and fresh, so the test starts from old (the
# path is free again after the delete).
upload_old_then_fresh() {
	run_upload --delete "$CHAR_PATH" || fail "--delete before the merge test exited with an error."
	for version in old fresh; do
		for f in character.json journey.jsonl trail.jsonl; do
			cp "$MERGE/$version/$f" "$TMP/latest/$CHAR_ID/$f"
		done
		run_upload --latest "$TMP/latest" || fail "the upload of the $version data exited with an error."
		grep -q "^uploaded $CHAR_PATH:" <<<"$OUT" || fail "the $version data was not uploaded."
	done
	for f in character.json journey.jsonl trail.jsonl; do
		curl_ -f -o "$TMP/merged.$f" "$SITE/$CHAR_PATH/data/$f" || fail "GET data/$f failed."
	done
}

# assert_merged_bytes WHAT FILE...: each downloaded $TMP/merged.FILE equals testdata/merge/expected/FILE byte for byte.
assert_merged_bytes() {
	local what="$1" f
	shift
	for f in "$@"; do
		cmp -s "$MERGE/expected/$f" "$TMP/merged.$f" || {
			diff "$MERGE/expected/$f" "$TMP/merged.$f" | head -n 20 >&2 || true
			fail "the merged $f$what differs from testdata/merge/expected/$f."
		}
	done
}

status_of() { curl_ -o /dev/null -w '%{http_code}' "$1"; }

# assert_shots_status WANT NAME...: each screenshot NAME of the character answers WANT.
assert_shots_status() {
	local want="$1" s
	shift
	for s in "$@"; do
		[ "$(status_of "$SITE/$CHAR_PATH/data/screenshots/$s")" = "$want" ] || fail "$s does not give $want."
	done
}

# The CurseForge and example links of the home page point to neutral addresses in this run (see the server start),
# so a match below is a link to a character of this site.
assert_home_has_no_character_link() {
	curl_ -f -o "$TMP/home.html" "$SITE/" || fail "GET / did not answer 200."
	if grep -Eiq 'href="[^"]*(/wow/|brumamar|nandu|los-errantes)' "$TMP/home.html"; then
		fail "the home page links to a character."
	fi
}

step "build the server and the CLI"
make -C "$ROOT" --no-print-directory server-build >/dev/null || fail "the server did not build."
(cd "$ROOT" && fvm dart pub get --directory="$CORE" >/dev/null) || fail "dart pub get failed."
(cd "$ROOT" && fvm dart compile exe "$CORE/bin/memories_upload.dart" -o "$TMP/memories-upload" >/dev/null) \
	|| fail "memories-upload did not compile."

# The ports are chosen right before the server starts, so the build cannot take them in between. Both sockets stay
# open until both ports are chosen, so the two ports differ.
read -r PUBLIC_PORT ADMIN_PORT < <(python3 -I -c '
import socket
a, b = socket.socket(), socket.socket()
a.bind(("127.0.0.1", 0))
b.bind(("127.0.0.1", 0))
print(a.getsockname()[1], b.getsockname()[1])
')
SITE="http://127.0.0.1:$PUBLIC_PORT"
ADMIN="http://127.0.0.1:$ADMIN_PORT"

step "start the server on $SITE (admin on $ADMIN)"
mkdir -p "$TMP/data"
MEMORIES_REGISTRATION=invite \
	MEMORIES_DATA_DIR="$TMP/data" \
	MEMORIES_WEB_DIR="$ROOT/web" \
	MEMORIES_PUBLIC_ADDR="127.0.0.1:$PUBLIC_PORT" \
	MEMORIES_ADMIN_ADDR="127.0.0.1:$ADMIN_PORT" \
	MEMORIES_SITE_URL="$SITE" \
	MEMORIES_CURSEFORGE_URL="https://addons.example.test/memories" \
	MEMORIES_EXAMPLE_URL="https://journey.example.test/sample" \
	"$SERVER_BIN" >"$TMP/server.log" 2>&1 &
SERVER_PID=$!
ready=0
deadline=$((SECONDS + 30))
while [ "$SECONDS" -lt "$deadline" ]; do
	kill -0 "$SERVER_PID" 2>/dev/null || fail "the server stopped at start."
	if curl_ --max-time 1 -f -o /dev/null "$SITE/api/v1/info" 2>/dev/null; then
		ready=1
		break
	fi
	sleep 0.2
done
[ "$ready" = 1 ] || fail "the server did not answer /api/v1/info within 30 s."

cp -R "$EXPECTED" "$TMP/latest"
chmod -R u+w "$TMP/latest"

# A key that registers with no invite is an open key, and an open key cannot upload screenshots (step 6). The run
# makes an invite on the admin page, as an admin does, and the CLI registers with it.
step "make an invite on the admin page"
curl_ -f -c "$TMP/admin.cookies" -b "$TMP/admin.cookies" -o "$TMP/invites.html" "$ADMIN/invites" \
	|| fail "GET the admin invites page failed."
csrf="$(sed -n '/name="csrf" value="/{s/.*name="csrf" value="\([^"]*\)".*/\1/p;q;}' "$TMP/invites.html")"
[ -n "$csrf" ] || fail "the admin invites page has no CSRF token."
code="$(curl_ -c "$TMP/admin.cookies" -b "$TMP/admin.cookies" \
	--data-urlencode "csrf=$csrf" --data-urlencode "note=e2e" \
	-o /dev/null -w '%{http_code}' "$ADMIN/invites/create")"
[ "$code" = 303 ] || fail "the invite form answered $code, not 303."
curl_ -f -c "$TMP/admin.cookies" -b "$TMP/admin.cookies" -o "$TMP/invite.html" "$ADMIN/invites" \
	|| fail "GET the admin invites page after the invite failed."
INVITE="$(sed -n 's/.*<code>\([0-9A-Z]\{4\}\(-[0-9A-Z]\{4\}\)\{3\}\)<\/code>.*/\1/p' "$TMP/invite.html" | head -n 1)"
[ -n "$INVITE" ] || fail "the admin page does not show the new invite code."

step "1. register with the invite and upload the fixture with the CLI"
run_upload --invite "$INVITE" --latest "$TMP/latest" || fail "memories-upload exited with an error."
grep -q "^uploaded $CHAR_PATH:" <<<"$OUT" || fail "the report does not say that $CHAR_PATH was uploaded."
grep -q "^uploaded $OTHER_PATH:" <<<"$OUT" || fail "the report does not say that $OTHER_PATH was uploaded."

step "2. the character page"
code="$(curl_ -D "$TMP/page.headers" -o "$TMP/page.html" -w '%{http_code}' "$SITE/$CHAR_PATH/")" \
	|| fail "GET /$CHAR_PATH/ did not answer."
[ "$code" = 200 ] || fail "the page answered $code, not 200."
grep -q 'data-entry' "$TMP/page.html" || fail "the page has no data-entry attribute."
assets="$(grep -oE '(src|href)="/_/[^"]+"' "$TMP/page.html" | sed -E 's/^(src|href)="//; s/"$//')"
[ -n "$assets" ] || fail "the page references no /_/ asset."
for asset in $assets; do
	code="$(curl_ -o "$TMP/asset.body" -w '%{http_code}' "$SITE$asset")" || fail "GET $asset did not answer."
	case "$asset" in
	/_/map/*)
		[ "$code" = 200 ] || { [ "$code" = 404 ] && ! grep -qi '<html' "$TMP/asset.body"; } \
			|| fail "GET $asset answered $code, not 200 or a plain 404."
		;;
	*) [ "$code" = 200 ] || fail "GET $asset answered $code, not 200." ;;
	esac
done
curl_ -D "$TMP/css.headers" -o /dev/null "$SITE/_/style.css" || fail "GET /_/style.css failed."
grep -iq '^content-type: text/css' "$TMP/css.headers" || fail "/_/style.css has no text/css type."
grep -iq '^x-robots-tag:.*noindex' "$TMP/page.headers" || fail "the page has no X-Robots-Tag noindex header."
assert_home_has_no_character_link

step "3. the stored journey equals the fixture without screenshots"
curl_ -f -o "$TMP/journey.jsonl" "$SITE/$CHAR_PATH/data/journey.jsonl" || fail "GET data/journey.jsonl failed."
same_journey_without_shots "$TMP/journey.jsonl" "$EXPECTED/$CHAR_ID/journey.jsonl" \
	|| fail "the stored journey differs from the expected journey."
if jq -e 'select(has("screenshot"))' "$TMP/journey.jsonl" >/dev/null 2>&1; then
	fail "the stored journey keeps a screenshot field for a key with no approval."
fi

step "4. a second run uploads nothing"
run_upload --latest "$TMP/latest" || fail "the second run exited with an error."
[ "$(grep -c '^unchanged ' <<<"$OUT")" = 2 ] || fail "the report does not say 'unchanged' for both characters."
if grep -q '^uploaded ' <<<"$OUT"; then fail "the second run uploaded a character."; fi

step "5. a fresh upload merges into the stored data"
upload_old_then_fresh
# The key has no approval yet, so the server removed the screenshot fields; step 6 checks the journey bytes with them.
assert_merged_bytes "" character.json trail.jsonl
same_journey_without_shots "$TMP/merged.journey.jsonl" "$MERGE/expected/journey.jsonl" \
	|| fail "the merged journey.jsonl differs from testdata/merge/expected/journey.jsonl."

step "6. screenshots: request, approve on the admin page, upload"
[ "$(status_of "$SITE/$CHAR_PATH/data/screenshots/WoWScrnShot_110126_114820.jpg")" = 404 ] \
	|| fail "a screenshot is served before the approval."
run_upload --request-screenshots || fail "--request-screenshots exited with an error."
grep -q '^Screenshot state of this key: pending\.$' <<<"$OUT" || fail "the request did not give the state pending."

curl_ -f -c "$TMP/admin.cookies" -b "$TMP/admin.cookies" -o "$TMP/requests.html" "$ADMIN/requests" \
	|| fail "GET the admin requests page failed."
csrf="$(sed -n '/name="csrf" value="/{s/.*name="csrf" value="\([^"]*\)".*/\1/p;q;}' "$TMP/requests.html")"
key_id="$(sed -n '/name="key" value="[0-9]/{s/.*name="key" value="\([0-9][0-9]*\)".*/\1/p;q;}' "$TMP/requests.html")"
[ -n "$csrf" ] && [ -n "$key_id" ] || fail "the admin page has no pending request with an approve form."
code="$(curl_ -c "$TMP/admin.cookies" -b "$TMP/admin.cookies" \
	--data-urlencode "csrf=$csrf" --data-urlencode "key=$key_id" \
	-o /dev/null -w '%{http_code}' "$ADMIN/requests/approve")"
[ "$code" = 303 ] || fail "the approve form answered $code, not 303."
# The approve form also answers 303 when nothing changed or the store failed; the message on the next page tells which.
curl_ -f -c "$TMP/admin.cookies" -b "$TMP/admin.cookies" -o "$TMP/approved.html" "$ADMIN/requests" \
	|| fail "GET the admin requests page after the approval failed."
grep -q 'Screenshots approved for key' "$TMP/approved.html" || fail "the admin page does not confirm the approval."

# The fixture screenshots are 44-byte text files, which the server rightly rejects, and the merge data names more
# screenshots than the fixture holds files for (the client reports a missing file as an error). So each name gets a copy
# of a small real JPEG.
[ -f "$IMAGE" ] || fail "the test image $IMAGE is missing."
mkdir -p "$TMP/latest/$CHAR_ID/screenshots"
shots=()
while IFS= read -r name; do shots+=("$name"); done < <(jq -r '.screenshot // empty | ltrimstr("screenshots/")' "$MERGE/old/journey.jsonl" "$MERGE/fresh/journey.jsonl" | sort -u)
[ "${#shots[@]}" -gt 0 ] || fail "the merge data names no screenshots."
for s in "${shots[@]}"; do cp "$IMAGE" "$TMP/latest/$CHAR_ID/screenshots/$s"; done
upload_old_then_fresh
assert_merged_bytes " of an approved key" character.json journey.jsonl trail.jsonl
assert_shots_status 200 "${shots[@]}"

# The fixture's own screenshots: upload the fixture character again from a clean slate.
run_upload --delete "$CHAR_PATH" || fail "--delete before the fixture screenshots exited with an error."
rm -rf "$TMP/latest/$CHAR_ID"
cp -R "$EXPECTED/$CHAR_ID" "$TMP/latest/$CHAR_ID"
chmod -R u+w "$TMP/latest"
for f in "$TMP/latest/$CHAR_ID/screenshots"/*; do cp "$IMAGE" "$f"; done
run_upload --latest "$TMP/latest" || fail "the upload of the fixture with an approved key exited with an error."
fixture_shots=()
for f in "$EXPECTED/$CHAR_ID/screenshots"/*; do fixture_shots+=("$(basename "$f")"); done
assert_shots_status 200 "${fixture_shots[@]}"

step "7. delete the character"
run_upload --delete "$CHAR_PATH" || fail "--delete exited with an error."
[ "$(status_of "$SITE/$CHAR_PATH/")" = 404 ] || fail "the page of the deleted character does not give 404."
for f in character.json journey.jsonl trail.jsonl; do
	[ "$(status_of "$SITE/$CHAR_PATH/data/$f")" = 404 ] || fail "data/$f of the deleted character does not give 404."
done
assert_shots_status 404 "${fixture_shots[@]}"

step "8. the home page has no character link"
assert_home_has_no_character_link
[ "$(status_of "$SITE/$OTHER_PATH/")" = 200 ] || fail "the other character was removed by the delete."

echo "e2e: all steps passed."
