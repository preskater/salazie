# Salazie — agent guide

This file is the single source of project instructions for **OpenCode**, **Claude Code** and **GitHub Copilot**. All three read `AGENTS.md`; do not create parallel `CLAUDE.md` or `.github/copilot-instructions.md` copies.

## Project

Salazie is a 2D pixel-art narrative RPG made with **Godot 4.7.2** and GDScript. The story follows one family across three generations: survival, farming, then protecting the future of Salazie.

- Boot scene: `scenes/ui/menus/main_menu.tscn`; `scenes/samples/main.tscn` is the sandbox scene
- Player: `scenes/player/player.tscn`, `scripts/player/player.gd`
- Engine config: `project.godot` (features `4.7`, Jolt Physics, Forward+)
- Platform: desktop first, Web export also supported
- Language rule: **code, identifiers and technical docs in English; `README.md`, `LORE.md` and narrative docs in French.** Reply in the user's language.

## Repository map

| Path | Purpose |
|---|---|
| `scenes/` | Gameplay, UI, map and autoload scenes |
| `scripts/` | GDScript, grouped by subsystem |
| `game_resources/` | Project-authored `.tres` data: tilesets, animations, economy |
| `themes/` | UI theme and icon resources |
| `sprites/` | Pixel-art packs, `.import` files, licenses |
| `shaders/` | Shader files |
| `audio/` | Audio bus layout, `music/` and `sfx/` (generated placeholders, see `docs/AUDIO.md`) |
| `tests/unit/` | gdUnit4 test suites (`test_*.gd`) |
| `tools/` | Dev-only helpers: TileSet generator, map preview, collision checks, the coverage tool and the audio generator |
| `docs/` | Design notes, lore, third-party notices |
| `export_presets.cfg` | Linux, Windows, macOS, Web presets |
| `.github/workflows/godot-ci.yml` | CI: gdUnit4 tests, coverage gate + four exports |
| `.agent/` | Canonical agent and skill definitions |
| `opencode.json` | OpenCode config: Godot MCP server |
| `.mcp.json` | Claude Code project-scope MCP servers |
| `.vscode/mcp.json` | VS Code / Copilot workspace MCP servers |

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

If links are missing after a Windows checkout, recreate them from `.agent/`. Windows needs Developer Mode or `core.symlinks=true` for Git symlinks.

Agent files use a combined frontmatter. OpenCode reads the V2 fields and ignores `name`/`tools` with a log warning; Claude Code and Copilot use `name`/`description`/`tools` and ignore the rest. That warning is expected.

## Skills

Skills live in `.agent/skills/`. Load the relevant one before specialised work.

| Area | Skills |
|---|---|
| Structure | `salazie-structure` |
| GDScript / scenes | `godot-gdscript`, `godot-nodes-scenes`, `godot-signals-groups` |
| Player / animation | `godot-2d-movement`, `godot-animation` |
| Data / levels / UI | `godot-resources`, `godot-tilemap`, `godot-ui-control` |
| Build / verification | `godot-export`, `salazie-verify`, `salazie-coverage` |
| Art | `create-game-assets` |
| Design | `game-docs`, `level-design`, `game-feel`, `game-ui-ux`, `input-systems`, `save-systems`, `camera-systems`, `dialogue-systems` |

Rules:

- Only the skills listed above are installed. Ignore references to other skill IDs.
- `salazie-structure` is the folder contract: load it before adding, moving or reviewing files.
- This project uses **gdUnit4**. Do not replace it with the custom SceneTree runner described by generic Godot testing skills.
- `godot-export` examples may use `build/`; this project uses **`export/`**.
- `salazie-verify` is the canonical verification procedure.
- `salazie-coverage` measures statement coverage and explains the CI floor.

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

### Godot MCP

The Godot MCP server (`@coding-solo/godot-mcp`, pinned to `0.1.1`) is configured
for every agent from one package. It launches the editor, runs the project,
captures debug output and edits scenes through Godot itself.

| Agent | Config file | Scope |
|---|---|---|
| OpenCode | `opencode.json` | project (`mcp.servers.godot`) |
| Claude Code | `.mcp.json` | project, needs a one-time trust approval |
| VS Code / Copilot | `.vscode/mcp.json` | workspace |

Setup details:

- The server finds Godot by itself; `/Applications/Godot.app/Contents/MacOS/Godot`
  is its first macOS candidate. Override with `GODOT_PATH` only for a custom
  install: OpenCode `environment`, Claude Code `claude mcp add --env GODOT_PATH=…`,
  Copilot `env` in `.vscode/mcp.json`.
- The first `npx` run downloads the package. Claude Code tunes startup with
  `MCP_TIMEOUT=60000 claude`; its `.mcp.json` `timeout` field limits each tool
  call, so it is intentionally unset.
- `npx` must be on `PATH` (Node.js >= 18).

Rules for using it:

- `launch_editor` and `run_project` open real GUI windows. CI never runs the
  MCP; keep headless commands for anything reproducible.
- `update_project_uids` resaves resources wholesale and conflicts with the
  "do not hand-edit UIDs" rule. Run it only when explicitly asked, then review
  the diff.
- Use the MCP mainly for run/debug feedback. Scene tools bypass the `.tscn`
  conventions above, so review any scene they generate or change.

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

- Layout: scenes in `scenes/`, scripts in `scripts/`, project `.tres` data in `game_resources/`, UI theme in `themes/`, shaders in `shaders/`, art in `sprites/`. See `salazie-structure`.
- Use typed members, parameters and returns. Use `:=` only when the right side has a static type.
- `snake_case` for variables/functions, `PascalCase` for nodes/classes, `SCREAMING_SNAKE_CASE` for constants.
- Prefer `@onready` and `get_node_or_null()` at scene boundaries; avoid deep hardcoded paths.
- Signals: past tense (`died`, `item_picked_up`). Children emit; parents connect. Disconnect one-shot connections when the listener can outlive the emitter.
- Movement: set `velocity` and call `move_and_slide()` once per `_physics_process`.
- Input: use named actions from `project.godot`; never hardcode physical keys. The project must work on AZERTY and with rebinding.
- UI text never spells a key or a button: use `InputHints.prompt()` / `InputHints.label()`, or an `{action}` token resolved by `InputHints.format()` for text stored in scenes and data. Every gameplay action needs a keyboard and a gamepad binding.
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
- Coverage: `bash tools/coverage/run.sh --show-missed` (see `salazie-coverage`). The target
  is 100 % of statements; CI fails below `COVERAGE_MIN`, which only ever goes up.

## Assets

- Vendored packs live in `sprites/<pack>/`; project-authored art lives in `sprites/custom/`. There is no `assets/` root.
- Preserve pixel dimensions and transparency; never upscale pixel art implicitly.
- Commit the `.import` file next to each image. Moving an image requires updating `source_file`, `path` and `dest_files` (see `salazie-structure`); do not edit `.import` by hand otherwise.
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
- `coverage`: instruments a copy of the project, reruns gdUnit4 on it, publishes the
  per-script table and fails below `COVERAGE_MIN`.
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
- [ ] coverage did not drop (`tools/coverage/run.sh`) when scripts or tests changed
- [ ] headless smoke test, with log scan
- [ ] affected exports, with artifact existence checks
- [ ] `git diff` contains no generated or unrelated files
- [ ] docs and skill commands still match the repository

Full procedure: `.agent/skills/salazie-verify/SKILL.md`.
