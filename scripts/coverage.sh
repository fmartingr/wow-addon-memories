#!/usr/bin/env bash
# Checks the line coverage of the core files (Core/ and Data/) in a luacov report and prints the total.
set -euo pipefail

report="${1:-luacov.report.out}"
min="${LUA_COVERAGE_MIN:-80}"

awk -v min="$min" '
	/^Summary/ { summary = 1 }
	!summary { next }
	$1 ~ /^addons\/Memories\/(Core|Data)\// { hits += $2; missed += $3 }
	$1 == "Total" { total = $NF }
	END {
		if (hits + missed == 0) { print "Lua core coverage: no core files in the report"; exit 1 }
		core = 100 * hits / (hits + missed)
		printf "Lua core coverage: %.2f%% (min %s%%)\n", core, min
		printf "Lua total coverage: %s\n", total
		exit (core < min)
	}
' "$report"
