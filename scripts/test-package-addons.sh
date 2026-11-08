#!/usr/bin/env bash
# Tests scripts/package-addons.sh: the zip holds the 6 addon folders at its root, each TOC of the zip has the
# release version, the other files are copies, and the repository files stay unchanged.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="$root/scripts/package-addons.sh"
expected="Memories Memories_Character Memories_Combat Memories_Economy Memories_Gathering Memories_Social"
version="9.8.7-test.1"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

failures=0
fail() {
	echo "FAIL: $*" >&2
	failures=$((failures + 1))
}

tree_hash() {
	(cd "$1" && find . -type f -exec sha256sum {} + | LC_ALL=C sort)
}

before="$(tree_hash "$root/addons")"

zip_path="$work/out/Memories-addons-$version.zip"
bash "$script" "$version" "$zip_path"

top="$(unzip -Z1 "$zip_path" | cut -d/ -f1 | LC_ALL=C sort -u | xargs)"
[ "$top" = "$expected" ] || fail "zip root holds '$top', want '$expected'"

if unzip -Z1 "$zip_path" | grep -qv /; then
	fail "zip root holds files: $(unzip -Z1 "$zip_path" | grep -v / | xargs)"
fi

unzip -q "$zip_path" -d "$work/unzipped"
for addon in $expected; do
	toc="$work/unzipped/$addon/$addon.toc"
	if [ ! -f "$toc" ]; then
		fail "$addon/$addon.toc is missing"
		continue
	fi
	lines="$(grep -c '^## Version:' "$toc" || true)"
	[ "$lines" = 1 ] || fail "$addon.toc has $lines '## Version:' lines, want 1"
	grep -qx "## Version: $version" "$toc" || fail "$addon.toc does not have '## Version: $version'"
	if ! diff <(grep -v '^## Version:' "$root/addons/$addon/$addon.toc") <(grep -v '^## Version:' "$toc") >/dev/null; then
		fail "$addon.toc differs from the repository in more than the version line"
	fi
done

while IFS= read -r -d '' file; do
	rel="${file#"$root/addons/"}"
	case "$rel" in
	*.toc) continue ;;
	esac
	cmp -s "$file" "$work/unzipped/$rel" || fail "$rel in the zip is not a copy of the repository file"
done < <(find "$root/addons" -type f -print0)

after="$(tree_hash "$root/addons")"
[ "$before" = "$after" ] || fail "the files in addons/ changed"

# A second run to the same path replaces the zip and does not add to it.
bash "$script" "9.9.9" "$zip_path"
first="$(unzip -Z1 "$zip_path" | LC_ALL=C sort)"
expected_entries="$(cd "$root/addons" && find . -mindepth 1 | sed 's|^\./||' | while IFS= read -r p; do
	if [ -d "$p" ]; then echo "$p/"; else echo "$p"; fi
done | LC_ALL=C sort)"
[ "$first" = "$expected_entries" ] || fail "a second run did not replace the zip with the same entries"
unzip -p "$zip_path" Memories/Memories.toc | grep -qx '## Version: 9.9.9' || fail "a second run kept the old version"

# A TOC with no '## Version:' line gets one in the copy.
fake="$work/fake-addons"
mkdir -p "$fake/NoVersion"
printf '## Interface: 16001\n## Title: No Version\n\nFile.lua\n' >"$fake/NoVersion/NoVersion.toc"
printf 'print(1)\n' >"$fake/NoVersion/File.lua"
fake_before="$(tree_hash "$fake")"
MEMORIES_ADDONS_DIR="$fake" bash "$script" "1.2.3" "$work/fake.zip"
fake_toc="$(unzip -p "$work/fake.zip" NoVersion/NoVersion.toc)"
want_toc="$(printf '## Interface: 16001\n## Version: 1.2.3\n## Title: No Version\n\nFile.lua\n')"
[ "$fake_toc" = "$want_toc" ] || fail "a TOC with no version line got: $fake_toc"
[ "$fake_before" = "$(tree_hash "$fake")" ] || fail "the addon folder with no version line changed"

# A CRLF TOC keeps CRLF on the version line; a TOC with no '## Interface:' gets the version as its first line.
eol_dir="$work/eol-addons"
mkdir -p "$eol_dir/Crlf" "$eol_dir/NoInterface"
printf '## Interface: 16001\r\n## Version: 0.0.1\r\n' >"$eol_dir/Crlf/Crlf.toc"
printf '## Title: No Interface\n' >"$eol_dir/NoInterface/NoInterface.toc"
MEMORIES_ADDONS_DIR="$eol_dir" bash "$script" "1.2.3" "$work/eol.zip" >/dev/null
got="$(unzip -p "$work/eol.zip" Crlf/Crlf.toc | od -An -c | xargs)"
want="$(printf '## Interface: 16001\r\n## Version: 1.2.3\r\n' | od -An -c | xargs)"
[ "$got" = "$want" ] || fail "a CRLF TOC got: $got"
got="$(unzip -p "$work/eol.zip" NoInterface/NoInterface.toc)"
[ "$got" = "$(printf '## Version: 1.2.3\n## Title: No Interface\n')" ] || fail "a TOC with no interface line got: $got"

# Usage errors exit 2 and write no zip.
for args in "" "1.2.3" "bad/version $work/bad.zip" "-1 $work/bad.zip"; do
	code=0
	# shellcheck disable=SC2086
	bash "$script" $args >/dev/null 2>&1 || code=$?
	[ "$code" = 2 ] || fail "package-addons.sh $args exited $code, want 2"
done
[ ! -e "$work/bad.zip" ] || fail "a usage error wrote a zip"

# A folder with no TOC is an error.
mkdir -p "$work/no-toc/Empty"
code=0
MEMORIES_ADDONS_DIR="$work/no-toc" bash "$script" "1.2.3" "$work/no-toc.zip" >/dev/null 2>&1 || code=$?
[ "$code" = 1 ] || fail "an addon folder with no TOC exited $code, want 1"

if [ "$failures" -gt 0 ]; then
	echo "test-package-addons: $failures failure(s)" >&2
	exit 1
fi
echo "test-package-addons: ok"
