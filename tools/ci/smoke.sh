#!/usr/bin/env bash
# Headless smoke run of every scene a player can reach.
#
#   GODOT_BIN=/path/to/godot bash tools/ci/smoke.sh [frames]
#
# Godot exits 0 after a script error, so the exit code proves nothing: each
# log is scanned, and one "SCRIPT ERROR" or "ERROR:" line fails the run.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GODOT_BIN="${GODOT_BIN:-godot}"
FRAMES="${1:-60}"
LOG_DIR="$ROOT/reports/smoke"
# An empty entry is the project's boot scene.
SCENES=(
	""
	"res://scenes/maps/maroon.tscn"
	"res://scenes/maps/farm.tscn"
	"res://scenes/maps/heir.tscn"
	"res://scenes/ui/ending/ending_screen.tscn"
	"res://scenes/samples/main.tscn"
)

mkdir -p "$LOG_DIR"
failed=0
for scene in "${SCENES[@]}"; do
	name="$(basename "${scene:-boot}" .tscn)"
	log="$LOG_DIR/$name.log"
	args=(--headless --path "$ROOT" --quit-after "$FRAMES" --audio-driver Dummy)
	if [ -n "$scene" ]; then
		args+=(--scene "$scene")
	fi
	# `timeout` guards CI against a scene that never quits; macOS has none.
	if command -v timeout > /dev/null; then
		timeout 120 "$GODOT_BIN" "${args[@]}" > "$log" 2>&1
	else
		"$GODOT_BIN" "${args[@]}" > "$log" 2>&1
	fi
	code=$?
	if [ "$code" -ne 0 ]; then
		echo "FAIL $name: exit code $code"
		failed=1
	elif grep -nE "SCRIPT ERROR|ERROR:" "$log"; then
		echo "FAIL $name: errors in the log above ($log)"
		failed=1
	else
		echo "ok   $name"
	fi
done
exit "$failed"
