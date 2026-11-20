# Salazie — agent guide

This file is the single source of project instructions for **OpenCode**, **Claude Code** and **GitHub Copilot**. All three read `AGENTS.md`; do not create parallel `CLAUDE.md` or `.github/copilot-instructions.md` copies.

## Project

Salazie is a 2D pixel-art narrative RPG made with **Godot 4.7.2** and GDScript. The story follows one family across three generations: survival, farming, then protecting the future of Salazie.

- Main scene: `game/main.tscn`
- Player: `game/player/player.tscn`, `game/player/player.gd`
- Engine config: `project.godot` (features `4.7`, Jolt Physics, Forward+)
- Platform: desktop first, Web export also supported
- Language rule: **code, identifiers and technical docs in English; `README.md`, `LORE.md` and narrative docs in French.** Reply in the user's language.

## Repository map

| Path | Purpose |
|---|---|
| `game/` | Gameplay scenes and GDScript |
| `tests/unit/` | gdUnit4 test suites (`test_*.gd`) |
| `assets/` | Pixel-art packs, `.import` files, licenses |
| `docs/` | Design notes, lore, third-party notices |
| `export_presets.cfg` | Linux, Windows, macOS, Web presets |
| `.github/workflows/godot-ci.yml` | CI: gdUnit4 tests + four exports |
| `.agent/` | Canonical agent and skill definitions |
| `scripts/` | Maintenance scripts |

## Canonical agent configuration

Everything under `.agent/` is the source of truth. **Edit only `.agent/`**, never the linked copies.

```text
.agent/skills/<id>/SKILL.md
.agent/agents/<name>.md
```

Links expose the same files to each tool:

```text
.claude/skills      -> ../.agent/skills
.claude/agents      -> ../.agent/agents
.opencode/skills    -> ../.agent/skills
.opencode/agents    -> ../.agent/agents
.github/skills      -> ../.agent/skills
.github/agents/*.agent.md -> ../../.agent/agents/*.md
```

If links are missing after a Windows checkout, run `scripts/link-agent-config.sh`. Windows needs Developer Mode or `core.symlinks=true` for Git symlinks.

Agent files use a combined frontmatter. OpenCode reads the V2 fields and ignores `name`/`tools` with a log warning; Claude Code and Copilot use `name`/`description`/`tools` and ignore the rest. That warning is expected.

## Skills

Skills live in `.agent/skills/`. Load the relevant one before specialised work.

| Area | Skills |
|---|---|
| GDScript / scenes | `godot-gdscript`, `godot-nodes-scenes`, `godot-signals-groups` |
| Player / animation | `godot-2d-movement`, `godot-animation` |
| Data / levels / UI | `godot-resources`, `godot-tilemap`, `godot-ui-control` |
| Build / verification | `godot-export`, `salazie-verify` |
| Art | `create-game-assets` |
| Design | `game-docs`, `level-design`, `game-feel`, `game-ui-ux`, `input-systems`, `save-systems`, `camera-systems`, `dialogue-systems` |

Rules:

- Only the skills listed above are installed. Ignore references to other skill IDs.
- This project uses **gdUnit4**. Do not replace it with the custom SceneTree runner described by generic Godot testing skills.
- `godot-export` examples may use `build/`; this project uses **`export/`**.
- `salazie-verify` is the canonical verification procedure.

## Agents

Use the specialised subagent when the task matches; otherwise use the normal build agent.

| Agent | Use when |
|---|---|
| `godot-verifier` | After gameplay, scene, asset or CI changes; runs checks and reports without editing |
| `gdscript-reviewer` | Before merging a GDScript or `.tscn` diff |
| `ci-fixer` | A GitHub Actions check is red |
| `asset-auditor` | Adding, importing or cleaning up pixel-art packs |
| `docs-maintainer` | README, LORE, GDD or feature notes changed |

Agents must respect their configured tool restrictions. Do not bypass a read-only agent by asking it to edit files.

## Toolchain

Target **Godot 4.7.2**, matching CI. On macOS:

```bash
GODOT_BIN=/Applications/Godot.app/Contents/MacOS/Godot
```

On Linux/CI, `godot` is on `PATH`.

```bash
# Import after a fresh checkout
"$GODOT_BIN" --headless --import

# Headless smoke run
"$GODOT_BIN" --headless --quit-after 5 --audio-driver Dummy

# Export (verify each output exists)
"$GODOT_BIN" --headless --export-release "Linux" export/linux/salazie.x86_64
"$GODOT_BIN" --headless --export-release "Windows Desktop" export/windows/salazie.exe
"$GODOT_BIN" --headless --export-release "macOS" export/macos/salazie.zip
"$GODOT_BIN" --headless --export-release "Web" export/web/index.html
```

Local gdUnit4 is not committed. Install it on demand:

```bash
tmp="$(mktemp -d)"
git clone --depth 1 --branch v6.2.3 https://github.com/godot-gdunit-labs/gdUnit4 "$tmp/gdUnit4"
mkdir -p addons
cp -R "$tmp/gdUnit4/addons/gdUnit4" addons/
rm -rf "$tmp"

GODOT_BIN="$GODOT_BIN" bash addons/gdUnit4/runtest.sh \
  --headless --audio-driver Dummy --ignoreHeadlessMode \
  --continue --add res://tests
```

## GDScript conventions

- Use typed members, parameters and returns. Use `:=` only when the right side has a static type.
- `snake_case` for variables/functions, `PascalCase` for nodes/classes, `SCREAMING_SNAKE_CASE` for constants.
- Prefer `@onready` and `get_node_or_null()` at scene boundaries; avoid deep hardcoded paths.
- Signals: past tense (`died`, `item_picked_up`). Children emit; parents connect. Disconnect one-shot connections when the listener can outlive the emitter.
- Movement: set `velocity` and call `move_and_slide()` once per `_physics_process`.
- Input: use named actions from `project.godot`; never hardcode physical keys. The project must work on AZERTY and with rebinding.
- Scenes: keep ownership clear, instance reusable `.tscn` files, and do not hand-edit UIDs.
- Do not add `class_name` casually; it becomes a global identifier.
- Keep `project.godot` changes minimal and explain them.

## Tests

- Framework: **gdUnit4** v6.2.3, suites under `tests/unit/`, files named `test_*.gd`.
- Extend `GdUnitTestSuite`; use `auto_free()` for nodes and `add_child()` when `@onready` must resolve.
- Test observable behavior: scene composition, animation selection, input actions, state transitions, save/load round-trips.
- Avoid frame-rate-dependent assertions. Await `process_frame` only when needed.
- Every gameplay change should add or update a focused test. Bug fixes should include a regression test.
- CI runs tests with the gdUnit4 action; local runs use the command above.

## Assets

- Preserve pixel dimensions and transparency; never upscale pixel art implicitly.
- Commit the `.import` file next to each image. Do not edit `.import` by hand unless the import change is intentional.
- Keep pack licenses/readmes with the assets and record new packs in `docs/`.
- Do not delete or re-encode assets without explicit approval.
- Load `create-game-assets` for art direction, sprite QA, provenance or licensing.

## Documentation

- `README.md`, `LORE.md` and narrative notes stay in **French**.
- Technical guides, code comments and this file stay in **English**.
- Use `game-docs` for a GDD or feature note; use `docs-maintainer` for keeping existing docs true.
- Every path and command in docs must exist and work.

## CI and exports

Workflow: `.github/workflows/godot-ci.yml`

- `test`: gdUnit4 on Ubuntu, report uploaded.
- `prepare`: imports the project once and runs the smoke test, then saves the `.godot` cache.
- `build`: matrix over Linux, Windows, macOS and Web; each job restores the import cache, exports one platform, and uploads a `salazie-<platform>` artifact.

macOS uses the **universal** template and requires `rendering/textures/vram_compression/import_etc2_astc=true`. Do not switch the preset back to `x86_64`: Godot issue #121170 makes single-architecture macOS export fail with `Requested template binary "godot_macos_release.x86_64" not found`.

Godot exit codes are unreliable:

- A failed `assert()` or runtime error can still exit 0; scan logs for `SCRIPT ERROR` and `ERROR:`.
- An export can print `Project export ... failed` and exit 0; check that the artifact exists.

## Git and PR rules

- Do not commit `.godot/`, `export/`, `addons/gdUnit4/`, or personal editor files.
- Do not commit, push, tag, merge or close a PR unless the user asks.
- Keep PRs focused; unrelated cleanup goes in a separate PR.
- Before proposing a commit: run the verification checklist, review `git diff`, and report any check you could not run.
- Never rewrite published history or force-push a shared branch.

## Verification checklist

Run the checks that match the change:

- [ ] `godot --headless --import`
- [ ] gdUnit4 tests
- [ ] headless smoke test, with log scan
- [ ] affected exports, with artifact existence checks
- [ ] `git diff` contains no generated or unrelated files
- [ ] docs and skill commands still match the repository

Full procedure: `.agent/skills/salazie-verify/SKILL.md`.
