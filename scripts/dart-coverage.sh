#!/usr/bin/env bash
# Runs the tests of the Dart core with coverage and checks the line coverage of lib/.
set -euo pipefail

core="${1:-packages/memories_core}"
min="${DART_COVERAGE_MIN:-80}"

cd "$core"
rm -rf coverage
fvm dart test --coverage=coverage
fvm dart run coverage:format_coverage --lcov --in=coverage --out=coverage/lcov.info \
	--report-on=lib --packages=.dart_tool/package_config.json

if [ ! -s coverage/lcov.info ]; then
	echo "Dart core coverage: no coverage data in $core/coverage" >&2
	exit 1
fi

awk -v min="$min" '
	/^LF:/ { found += substr($0, 4) }
	/^LH:/ { hit += substr($0, 4) }
	END {
		if (found == 0) { print "Dart core coverage: no lines in the report"; exit 1 }
		pct = 100 * hit / found
		printf "Dart core coverage: %.2f%% (min %s%%)\n", pct, min
		exit (pct < min)
	}
' coverage/lcov.info
