# awesome-gamedev-agent-skills

Vendored game-development skills used by Salazie's coding agents.

- Upstream: https://github.com/gamedev-skills/awesome-gamedev-agent-skills
- Commit: `c6ca6c41c839b68319ffc08430b99ab768debc32`
- Retrieved: 2026-11-20
- License: Apache-2.0 (see `LICENSE` and `NOTICE` in this directory)

The skills are copied to `.agent/skills/` by `scripts/sync-gamedev-skills.sh`.
Only the upstream `SKILL.md`, `references/`, `assets/`, `scripts/` and
supporting files are vendored; the upstream router, evals and tests are not.

## Selected skills

Godot:

- `godot-gdscript`
- `godot-nodes-scenes`
- `godot-2d-movement`
- `godot-animation`
- `godot-signals-groups`
- `godot-resources`
- `godot-tilemap`
- `godot-ui-control`
- `godot-export`

Design and workflows:

- `create-game-assets`
- `input-systems`
- `game-docs`
- `level-design`
- `game-feel`
- `save-systems`
- `camera-systems`
- `dialogue-systems`
- `game-ui-ux`

## Local skills

`salazie-verify` is project-specific and is not part of the upstream pack. It
documents Salazie's import, gdUnit4, smoke-test and export commands.

## Updating

```bash
scripts/sync-gamedev-skills.sh
```

To change the pinned revision or the selected list, edit the `SHA` and
`SKILLS` values in that script and update this file.
