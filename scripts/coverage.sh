#!/usr/bin/env bash
# Checks the line coverage of the addon files (every folder of addons/, without Libs/) in a luacov report.
set -euo pipefail

report="${1:-luacov.report.out}"
min="${LUA_COVERAGE_MIN:-80}"

awk -v min="$min" '
	/^Summary/ { summary = 1 }
	!summary { next }
	index($1, "addons/") == 1 && $1 !~ /\/Libs\// { hits += $2; missed += $3 }
	END {
		if (hits + missed == 0) { print "Coverage: no addon files in the report"; exit 1 }
		cov = 100 * hits / (hits + missed)
		printf "Coverage: %.2f%% (min %s%%)\n", cov, min
		exit (cov < min)
	}
' "$report"
