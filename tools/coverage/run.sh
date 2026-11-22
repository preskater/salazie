#!/usr/bin/env bash
# Measures GDScript line coverage of the gdUnit4 suites.
#
#   GODOT_BIN=/path/to/godot bash tools/coverage/run.sh [--min 80] [--show-missed]
#
# The project is copied to a scratch directory, the copy is instrumented and the
# tests run there, so the working tree is never modified. Reports land in
# reports/coverage/ (ignored by Git). Extra arguments go to `coverage.py report`.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GODOT_BIN="${GODOT_BIN:-godot}"
# gdUnit4's runner insists on a file path, so a name found on PATH is resolved.
if [ ! -f "$GODOT_BIN" ]; then
	GODOT_BIN="$(command -v "$GODOT_BIN" || true)"
fi
if [ -z "$GODOT_BIN" ] || [ ! -x "$GODOT_BIN" ]; then
	echo "coverage: no Godot binary; set GODOT_BIN." >&2
	exit 2
fi
WORK="${SALAZIE_COV_WORK:-$(mktemp -d)}"
COPY="$WORK/project"
OUT="$ROOT/reports/coverage"

if [ ! -d "$ROOT/addons/gdUnit4" ]; then
	echo "coverage: addons/gdUnit4 is missing; install it first (see AGENTS.md)." >&2
	exit 2
fi

rm -rf "$COPY"
mkdir -p "$COPY" "$OUT"
# The import cache is copied too so textures are not re-imported; the import
# pass below rescans the scripts and registers the tracker class.
tar -C "$ROOT" --exclude ./.git --exclude ./export \
	--exclude ./reports -cf - . | tar -C "$COPY" -xf -

python3 "$ROOT/tools/coverage/coverage.py" instrument "$COPY"

"$GODOT_BIN" --headless --path "$COPY" --import > "$OUT/import.log" 2>&1 || true
# A first import always logs resource "Parse Error" lines for textures that are
# not imported yet; only GDScript errors mean the instrumentation broke a file.
if grep -E "SCRIPT ERROR|\.gd:[0-9]+ - Parse Error" "$OUT/import.log" >&2; then
	echo "coverage: the instrumented project does not compile; see $OUT/import.log" >&2
	exit 2
fi

export SALAZIE_COV_OUT="$OUT/hits.json"
rm -f "$SALAZIE_COV_OUT"
set +e
(cd "$COPY" && GODOT_BIN="$GODOT_BIN" bash addons/gdUnit4/runtest.sh \
	--headless --audio-driver Dummy --ignoreHeadlessMode \
	--continue --add res://tests) > "$OUT/tests.log" 2>&1
TEST_EXIT=$?
set -e
if [ "$TEST_EXIT" -ne 0 ]; then
	echo "coverage: the test run exited with $TEST_EXIT; see $OUT/tests.log" >&2
fi

python3 "$ROOT/tools/coverage/coverage.py" report "$COPY" "$SALAZIE_COV_OUT" \
	--lcov "$OUT/lcov.info" --json "$OUT/summary.json" "$@"
REPORT_EXIT=$?

if [ -z "${SALAZIE_COV_WORK:-}" ]; then
	rm -rf "$WORK"
fi
[ "$TEST_EXIT" -eq 0 ] || exit "$TEST_EXIT"
exit "$REPORT_EXIT"
