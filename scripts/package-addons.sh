#!/usr/bin/env bash
# Usage: scripts/package-addons.sh <version> <out.zip>
# Zips each addon folder of addons/ (MEMORIES_ADDONS_DIR overrides it) with the folders at the zip root. Each TOC of
# the copy gets '## Version: <version>'; a TOC with no version line gets one after '## Interface:' (or as its first line). The
# files in addons/ stay unchanged.
set -euo pipefail

usage() {
	echo "usage: scripts/package-addons.sh <version> <out.zip>" >&2
	exit 2
}

[ "$#" -eq 2 ] || usage
version="$1"
out="$2"
if ! [[ "$version" =~ ^[0-9A-Za-z][0-9A-Za-z.+-]*$ ]]; then
	echo "package-addons: the version '$version' may hold only letters, digits, '.', '+' and '-'" >&2
	usage
fi

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
addons="${MEMORIES_ADDONS_DIR:-$root/addons}"

mkdir -p "$(dirname "$out")"
out="$(cd "$(dirname "$out")" && pwd)/$(basename "$out")"

stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT

names=()
for dir in "$addons"/*; do
	[ -d "$dir" ] || continue
	name="$(basename "$dir")"
	cp -Rp "$dir" "$stage/$name"
	names+=("$name")

	tocs=("$stage/$name"/*.toc)
	if [ ! -f "${tocs[0]}" ]; then
		echo "package-addons: $name has no .toc file" >&2
		exit 1
	fi
	for toc in "${tocs[@]}"; do
		if grep -q '^## Version:' "$toc"; then
			mode=replace
		elif grep -q '^## Interface:' "$toc"; then
			mode=after
		else
			mode=top
		fi
		# A TOC saved with CRLF keeps CRLF on the version line.
		awk -v version="$version" -v mode="$mode" '
			{ cr = /\r$/ ? "\r" : ""; line = $0; sub(/\r$/, "", line) }
			mode == "top" && NR == 1 { print "## Version: " version cr }
			mode == "replace" && line ~ /^## Version:/ { if (!done) print "## Version: " version cr; done = 1; next }
			{ print }
			mode == "after" && !done && line ~ /^## Interface:/ { print "## Version: " version cr; done = 1 }
		' "$toc" >"$toc.tmp"
		mv "$toc.tmp" "$toc"
	done
done

if [ "${#names[@]}" -eq 0 ]; then
	echo "package-addons: no addon folder in $addons" >&2
	exit 1
fi

rm -f "$out.tmp"
(cd "$stage" && zip -qrX "$out.tmp" "${names[@]}")
mv "$out.tmp" "$out"
echo "package-addons: wrote $out (${names[*]})"
