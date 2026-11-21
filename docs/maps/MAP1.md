# Map 1 — Le marron

Technical reference for the first generation of Salazie. Narrative intent lives in
[LORE.md](../../LORE.md#map-1--le-marron); this note records what is built and where.

- Scene: `game/world/maps/Maroon.tscn`, root script `game/maroon/maroon_map.gd`
- Size: 60 × 45 tiles at 48 px → 2880 × 2160 px
- Player spawn: `(360, 1900)`
- New game starts here; the chapter fade leads to `Farm.tscn` once the refuge is reached.

## Scene structure

The scene is intentionally small: a single `Node2D` root builds the world at runtime
from the existing LimeZu props.

| Node | Type | Role |
|---|---|---|
| `Maroon` | `Node2D` + `maroon_map.gd` | World layout, checkpoints, task wiring |
| `World` | `Node2D`, y-sorted | Player, guards, trees, rocks, pickups |
| `World/Player` | `CharacterBody2D` | Player with active `SurvivalComponent` |
| `SurvivalHUD` | `CanvasLayer` | Food and water bars |
| `TaskList` | `CanvasLayer` | Generation task list |
| `GenerationResult` | `CanvasLayer` | Result shown before leaving |
| `RefugeExit` | `MapExit` | Final task and transition to Map 2 |

## Layout

| Zone | Content |
|---|---|
| Southern camp | Start position and first checkpoint |
| River | Horizontal water band; the only crossing is the central bridge |
| Patrol clearing | Five guards, hide spots and forage |
| Northern checkpoint | Completes `cross_patrol` |
| North-east refuge | Cabin, final task and `MapExit` to the farm |

Forage spots are placed south of the river and in the eastern forest. Water is picked up
on the bridge. Hide spots are bushes north of the river. The refuge is reached by crossing
the bridge, following the north path and walking east.

## Tasks

| ID | Success | Failure | Retry |
|---|---|---|---|
| `find_food` | Collect 3 wild foods | — | — |
| `find_water` | Drink at the river | — | — |
| `hide_from_patrol` | Stay hidden for 1.5 s | Spotted while trying to hide | Yes |
| `cross_patrol` | Reach the northern checkpoint | Caught by a guard | Yes |
| `reach_refuge` | Enter the refuge | — | — |

Being caught records a failure for `cross_patrol` and, if not already hidden, for
`hide_from_patrol`. The player respawns at the last checkpoint, the failed tasks return to
`PENDING`, and the failure history stays in the generation result.

The refuge exit completes `reach_refuge` on entry. If other tasks are still pending, the
exit is blocked and the player can go back.

## Survival and stealth

- `SurvivalComponent`: food drains at 0.35/s, water at 0.55/s.
- Forage restores 28 food; the river restores 60 water.
- A concealed player is ignored by guards beyond 32 px.
- Running still emits noise and raises suspicion.
- Guards use the existing vision cone, chase and catch logic with `pause_on_catch = false`
  so the map can respawn the player.

## Result and carry-over

- Map result: done / failed / failure events / rank.
- Each Map 1 failure event removes 5 G from the farmer's starting money, down to 15 G.
- The generation result is shown before the chapter fade to `Farm.tscn`.

## Controls

| Action | Keys | Effect |
|---|---|---|
| `move_*` | WASD / arrows | Move |
| `run` | Shift | Run, emits noise |
| `interact` | E | Not used for pickups; kept for consistency |
| `toggle_tasks` | T / Select | Open the task list |
| `pause` | Esc / Start | Pause menu |

## Files

| Path | Purpose |
|---|---|
| `game/world/maps/Maroon.tscn` | Minimal map scene |
| `game/maroon/maroon_map.gd` | Runtime layout and game loop |
| `game/maroon/forage_spot.gd` / `.tscn` | Food and water pickups |
| `game/maroon/hide_spot.gd` / `.tscn` | Concealment and hide task |
| `game/maroon/checkpoint.gd` / `.tscn` | Respawn point and patrol crossing task |
| `game/systems/campaign/campaign_state.gd` | Task states, failures and generation result |
| `game/ui/tasks/task_list.tscn` / `.gd` | Task list UI |
| `game/ui/tasks/generation_result.tscn` / `.gd` | Generation result overlay |

## Verification

```bash
GODOT_BIN=/Applications/Godot.app/Contents/MacOS/Godot
"$GODOT_BIN" --headless --import
"$GODOT_BIN" --headless --audio-driver Dummy --quit-after 5 \
  --scene res://game/world/maps/Maroon.tscn
GODOT_BIN="$GODOT_BIN" bash addons/gdUnit4/runtest.sh \
  --headless --audio-driver Dummy --ignoreHeadlessMode \
  --continue --add res://tests
```

Focused suite: `tests/unit/test_maroon_map.gd`.
