---
name: salazie-structure
description: Salazie folder contract adapted from game-base-2D, with the corrected base patterns for events, references, interaction, hitboxes, movement, camera and save. Use when adding, moving or reviewing files, or when adopting a system from the base. Not for verification (`salazie-verify`) or art direction (`create-game-assets`).
---

# Salazie structure

Salazie uses a **type-first top level, feature-first second level** layout adapted
from [game-base-2D](https://github.com/GuilhermeGSousa/game-base-2D) (MIT). This
skill is the folder contract and the reference for the base patterns in their
corrected Godot 4.7.2 form. Do not copy upstream code verbatim: the repository
still targets Godot 4.1/4.3 and contains defects listed at the end.

## Folder contract

| Path | Holds | Never holds |
|---|---|---|
| `scenes/` | `.tscn` files: maps, gameplay, UI, autoload scenes, sandbox | `.gd`, `.tres` data |
| `scripts/` | `.gd` and `.gd.uid`, grouped by subsystem | `.tscn` |
| `game_resources/` | Project-authored `.tres`: tilesets, `SpriteFrames`, economy, FX | imported images |
| `themes/salazie/` | `salazie_theme.tres` and `icons/*.tres` | scene scripts |
| `sprites/` | Pixel-art packs, `.import` sidecars, project art | gameplay code |
| `shaders/` | `.gdshader` and `.gdshader.uid` | materials (`.tres` go to `game_resources/`) |
| `audio/` | `default_bus_layout.tres`, future streams | music logic |
| `tests/unit/` | `test_*.gd` gdUnit4 suites | shipped scenes |
| `addons/` | Local gdUnit4 checkout, ignored | project code |

`scenes/` subfolders:

```text
scenes/preloads/   scenes referenced only by project.godot autoloads
scenes/maps/       maroon.tscn, farm.tscn, heir.tscn
scenes/samples/    sandbox scenes, excluded from player-facing flow
scenes/player/     player.tscn
scenes/farm/       crops, NPCs, market, HUD, animals/, ui/
scenes/maroon/     checkpoint, forage, hide spot
scenes/heir/       fragile site, decision point, town hall
scenes/world/      world_object, map_exit, ambient_leaves, ai/, fx/
scenes/ui/         menus/, hud/, dialogue/, decision/, tasks/, ending/
```

`scripts/` mirrors the feature split, plus the generic slots:
`audio/`, `camera/`, `events/`, `interaction/`, `movement/`, `references/`,
`utilities/`, and `systems/` for autoload and shared service scripts.

### Where does my file go?

| Adding | Destination |
|---|---|
| New map | `scenes/maps/<map>.tscn`, logic in `scripts/<map>/` |
| New gameplay object | `scenes/<feature>/<thing>.tscn` + `scripts/<feature>/<thing>.gd` |
| Reusable world prefab | `scenes/world/<thing>.tscn` |
| Menu, HUD, modal | `scenes/ui/<area>/` + `scripts/ui/<area>/` |
| Autoload scene | `scenes/preloads/<name>.tscn` |
| Autoload or shared service | `scripts/systems/<name>.gd` |
| Data resource | `game_resources/<kind>/<thing>.tres` |
| Theme or icon atlas | `themes/salazie/` |
| Shader | `shaders/<area>/<name>.gdshader` |
| Image | `sprites/<pack>/` for vendored art, `sprites/custom/` for authored art |
| Test | `tests/unit/test_<subject>.gd` |

Rules:

- File names are `snake_case`. `class_name` is `PascalCase` and matches the file name (`player.gd` → `Player` if it had a global class).
- One global class per file. Do not add `class_name` casually: it becomes a project-wide identifier.
- Node names are `PascalCase`; signals are past tense (`died`, `item_picked_up`).
- Scenes must work alone: instancing a scene must not require a specific parent layout.
- Put a scene in `scenes/` and its script in `scripts/`. The folder names match; the feature name matches.

## Moving files safely

- Move a `.gd` together with its `.gd.uid`. Move a `.gdshader` with its `.gdshader.uid`. Never hand-edit a `uid://` value or regenerate `.uid` files.
- Godot resolves `.tscn` references by UID first and by path second. Rewrite every `res://` path anyway; a stale path is tolerated silently and breaks external tooling.
- Every image has a committed `.import` next to it. If you move an image, update `source_file`, `path` and `dest_files`; the cached file name is `md5("res://" + source path)`. Then run `--headless --import` and confirm the `.import` file is stable on a second import.
- `assets/` no longer exists. Do not recreate it: vendored packs live in `sprites/<pack>/`.
- Do not move or re-encode a pack without explicit approval. The packs currently ship without their own licence/readme files; check `docs/` before adding or redistributing one.

## Base systems: what Salazie has

| Base 2D | Salazie equivalent | Status |
|---|---|---|
| `SceneTransitionManager` + `Transition` animations | autoload `SceneTransition` (`scenes/preloads/scene_transition.tscn`) and `SceneRouter` (`scripts/systems/scene_router.gd`) | present, different design |
| `SaveManager` (`Saveable` group, `store_var`) | autoload `SaveGame` (`scripts/systems/save/save_game.gd`), versioned JSON, atomic write, `.bak` fallback | present, keep this one |
| `AudioManager` pool | `audio/default_bus_layout.tres` only | missing |
| `CameraShakeManager` / `CameraShaker` | none; camera is a child of the player | missing |
| `CameraTargeter` / `CameraArea` | camera limits via `camera_limits` export on the player | different |
| `GameEvent` / `ValueReference` | signals, groups and autoload services | missing |
| `Interactor` / `Interactable` | `interactable` group plus proximity checks in map scripts | different |
| `HitBox` / `HurtBox` | guard damage plus `Player.apply_knockback()` | missing abstraction |
| `TopDownController` | `scripts/player/player.gd` | monolithic |
| `PlatformerController` / `GridController` | not used | n/a |
| Post-processing stack | none | missing |
| `scenes/samples/` | `scenes/samples/main.tscn` | present |

Do not add a second save manager, a second transition manager or a second audio
bus layout. Extend the existing autoload or add a new one under
`scripts/systems/`.

## Corrected base patterns

### Game events and references

Use a `Resource` so two unrelated nodes can share it without knowing each other.
One resource per file, `class_name` matching the file.

```gdscript
# scripts/events/game_event.gd
class_name GameEvent
extends Resource

signal triggered

func trigger() -> void:
	triggered.emit()
```

```gdscript
# scripts/references/float_reference.gd
class_name FloatReference
extends Resource

signal value_changed(old_value: float, new_value: float)

@export var value: float = 0.0:
	set(new_value):
		if is_equal_approx(new_value, value):
			return
		var old_value := value
		value = new_value
		value_changed.emit(old_value, new_value)
```

`BoolReference` and `IntReference` mirror this with their own type. Do **not**
reproduce upstream's `value_reference.gd` property indirection: it is untyped and
the published `float_reference.gd` actually declares `BoolReference` (and vice
versa). Mirror the typed setter instead.

Connect in `_enter_tree()`/`_exit_tree()` or `_ready()` and disconnect when the
listener can outlive the emitter. Prefer typed signals over string events.

### Interaction

```gdscript
class_name Interactor
extends Area2D

@export var action: StringName = &"interact"
signal interacted

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(action):
		interacted.emit()
		get_viewport().set_input_as_handled()
```

An `Interactable` connects to each overlapping interactor once, with a reference
count, and emits `interacted(interactor)`. Upstream connects and disconnects on
every `area_entered`/`area_exited`; overlapping interactors then disconnect each
other and the prompt dies. Keep the refcount:

```gdscript
var _overlapping: Dictionary[Interactor, int] = {}
```

Use `_unhandled_input`, not `_process` polling, so a paused menu does not trigger
interactions.

### Hit boxes and hurt boxes

- `HurtBox` asks the `HitBox` to apply damage; the `HitBox` owns HP and emits
  `damaged(amount, source)` and `killed`.
- Effects are typed arrays. Iterate with `continue` on `null`; upstream returns
  early and silently skips every remaining effect.
- `is_immune` and one-shot guards live on the `HitBox`, not on the attacker.
- Keep damage numbers and knockback in the same call so a hit cannot apply twice.

### Movement

- One `CharacterBody2D` top node, `velocity` set once, `move_and_slide()` called
  once per `_physics_process`.
- Top-down: read `Input.get_vector()` and normalise; apply knockback with a timed
  state. Upstream's `TopDownController.set_kickback()` never starts
  `_kb_timer`, so knockback never happens — set both the direction and the timer.
- Platformer: coyote time and jump buffer are timers around `is_on_floor()`;
  jump height belongs in a `BaseJump` resource. Read gravity with
  `ProjectSettings.get_setting("physics/2d/default_gravity", 980.0)` and type it.
- AI: `NavigationAgent2D.get_next_path_position()`, never a straight line through
  walls. `_get_configuration_warnings()` must not call itself (upstream recurses);
  call `super._get_configuration_warnings()` and return a `PackedStringArray`.

### Camera

- Keep the `Camera2D` out of the player. A targeter node follows a list of
  `Node2D` in `global_position` and smooths with
  `lerp(current, target, 1.0 - exp(-speed * delta))`. Do not use
  `Tween.interpolate_value` per frame: it is frame-rate dependent.
- Shake is trauma-based: accumulate, decay with `delta`, sample noise with time,
  then add the result to `offset`/`rotation` from a stored base value. Upstream
  feeds the camera offset back into the noise, which drifts.
- Limits: `RectangleShape2D` has `size`, not `get_rect()`. Upstream's
  `CameraArea` calls a method that does not exist. Clamp the camera to
  `collision_shape.global_position ± size / 2` using the viewport size.
- An area-enter event resource is optional; if present, its signal name must
  match the one the targeter connects to. Upstream ships `area_entered_even` in
  one file and `area_entered_event` in the other.

### Save

Use `SaveGame`. It already implements what the base lacks:

- `SAVE_VERSION`, `to_dict()`/`from_dict()`, migration in `_migrate()`;
- atomic `.tmp` write, `.bak` rotation, fallback read;
- plain JSON, no `store_var` and no reflection over `TYPE_OBJECT` properties.

The base's `SaveManager` also skips falsy values (`if property_data:`), so `0`,
`false` and `""` silently disappear. If a scene needs local state, add a
`Saveable` group and explicit serialisation methods; never replace the autoload.

### Audio

Add a pool managed by one autoload only when a real sound is added. Route music
to `Music`, effects to `SFX`, and set `stream` before `play()`; validate the
`load()` result instead of pushing a null stream into a player.

### Post-processing

Stack full-rect `ColorRect`s under one `CanvasLayer`; the first child draws first.
Each effect is its own material so it can be toggled independently. Keep
post-processing out of gameplay scenes; add it to the map or a dedicated overlay.

## Upstream defects to avoid

| Base defect | Correct rule |
|---|---|
| `float_reference.gd` declares `BoolReference`; `bool_reference.gd` declares `FloatReference` | one class per file, name matches file |
| `BaseHitBox.damage()` returns on the first `null` effect | `continue` |
| `TopDownController.set_kickback()` never sets `_kb_timer` | set direction **and** timer |
| `CameraArea` calls `RectangleShape2D.get_rect()` | use `shape.size` |
| `CameraAreaTargeter` signal typo and unresolved camera | typed event + `get_viewport().get_camera_2d()` |
| `CameraShaker` samples noise from the camera offset | sample from time, restore base offset |
| `CameraTargeter` `Tween.interpolate_value` each frame | exponential `lerp` with `delta` |
| `TopDownFollowAI._get_configuration_warnings()` recurses | call `super` |
| `SaveManager` uses unversioned `store_var`, drops falsy values | versioned JSON with explicit `to_dict()` |
| Wiki paths point at `scripts/common/...` | use this skill's paths |

## Adding a feature

1. Pick the feature folder in `scenes/` and `scripts/` using the tables above.
2. Add the scene and script; give the script a typed owner and typed exports.
3. Add data to `game_resources/` only if it is shared or designer-editable.
4. Add a focused `tests/unit/test_<subject>.gd` covering observable behaviour.
5. Run `salazie-verify` (import, gdUnit4, smoke, exports).
6. Update `docs/` and `AGENTS.md` when a path or command changes.
