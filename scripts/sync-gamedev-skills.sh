#!/usr/bin/env bash
set -euo pipefail

# Update the vendored skills from the pinned upstream commit.
# Usage: scripts/sync-gamedev-skills.sh
# Canonical content lives in .agent/skills; .claude, .opencode and .github link to it.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHA="c6ca6c41c839b68319ffc08430b99ab768debc32"
DEST="$ROOT/.agent/skills"

SKILLS=(
  godot/godot-gdscript
  godot/godot-nodes-scenes
  godot/godot-2d-movement
  godot/godot-animation
  godot/godot-signals-groups
  godot/godot-resources
  godot/godot-tilemap
  godot/godot-ui-control
  godot/godot-export
  disciplines/create-game-assets
  disciplines/input-systems
  disciplines/game-docs
  disciplines/level-design
  disciplines/game-feel
  disciplines/save-systems
  disciplines/camera-systems
  disciplines/dialogue-systems
  disciplines/game-ui-ux
)

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

echo "Fetching awesome-gamedev-agent-skills @ $SHA"
curl -L --fail --silent --show-error \
  -o "$tmp/skills.tar.gz" \
  "https://codeload.github.com/gamedev-skills/awesome-gamedev-agent-skills/tar.gz/$SHA"
mkdir -p "$tmp/src"
tar -xzf "$tmp/skills.tar.gz" -C "$tmp/src" --strip-components=1

mkdir -p "$DEST"
for skill in "${SKILLS[@]}"; do
  name="${skill##*/}"
  src="$tmp/src/skills/$skill"
  if [ ! -f "$src/SKILL.md" ]; then
    echo "Missing SKILL.md for $skill" >&2
    exit 1
  fi
  rm -rf "$DEST/$name"
  cp -R "$src" "$DEST/$name"
  echo "  updated $name"
done

cp "$tmp/src/LICENSE" "$ROOT/docs/third-party/awesome-gamedev-agent-skills/LICENSE"
cp "$tmp/src/NOTICE" "$ROOT/docs/third-party/awesome-gamedev-agent-skills/NOTICE"

echo "Done. Skills are in .agent/skills; links were not changed."
