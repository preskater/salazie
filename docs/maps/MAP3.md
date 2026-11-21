# Map 3 — L'héritier

Technical reference for the final generation of Salazie. Narrative intent lives in
[LORE.md](../../LORE.md#map-3--lhéritier); this note records what is built and where.

- Scene: `game/world/maps/Heir.tscn`, root script `game/heir/heir_map.gd`
- Size: 50 × 37.5 tiles at 48 px → 2400 × 1800 px
- Player spawn: `(1200, 1600)`
- Entered from `Farm.tscn` after the farm generation is resolved.

## Scene structure

| Node | Type | Role |
|---|---|---|
| `Heir` | `Node2D` + `heir_map.gd` | Modern village, interactions, final vote |
| `World` | `Node2D`, y-sorted | Player, NPCs, buildings, sites |
| `TaskList` | `CanvasLayer` | Generation task list |
| `GenerationResult` | `CanvasLayer` | Result shown before the epilogue |
| `DialogueBox` | `CanvasLayer` | NPC lines and site descriptions |
| `DecisionPanel` | `CanvasLayer` | Three-plan decision |
| `HeritageLabel` | `Label` | Displays the family heritage |

## Layout

| Zone | Content |
|---|---|
| West river | Eroded riverbank site |
| Central square | Decision point and market-flood site |
| North | Town hall and forecourt |
| East park | Fragilised forest site |
| Houses | Modern, terraced and Victorian houses from `exteriors_48x48` |

## Tasks

| ID | Success | Failure |
|---|---|---|
| `listen` | Talk to 3 different inhabitants | — |
| `assess` | Inspect the 3 fragile sites | — |
| `choose_plan` | Choose forest, tourism or family farms | — |
| `become_mayor` | Present the plan with enough support | The council rejects the plan |

`become_mayor` is resolved from the **support score**: 6 minus every failure event recorded
across the three generations. Four points are needed. A permanent failure produces the
secondary epilogue but does not block the ending.

## Plans and epilogue

| Plan ID | Label | Epilogue theme |
|---|---|---|
| `forest` | Protéger la forêt et la rivière | Water and forest restored |
| `tourism` | Développer un tourisme durable | Visitors with strict nature rules |
| `farms` | Soutenir les familles paysannes | Markets and family farms revived |

The choice is stored in `Campaign.choices["map3_plan"]` and saved. The ending also reports
the heritage amount and the total failure count.

## Heritage

`SceneRouter` sets `Campaign.heritage` when entering the map:

```text
heritage = floor(farm money × (1 − 0.1 × Map 2 failure events))
```

The heritage is displayed in the top-left label and in the epilogue.

## Controls

| Action | Keys | Effect |
|---|---|---|
| `move_*` | WASD / arrows | Move |
| `interact` | E | Talk, inspect, decide, present the plan |
| `toggle_tasks` | T / Select | Open the task list |
| `pause` | Esc / Start | Pause menu |

## Files

| Path | Purpose |
|---|---|
| `game/world/maps/Heir.tscn` | Minimal map scene |
| `game/heir/heir_map.gd` | Runtime layout and game loop |
| `game/heir/fragile_site.gd` / `.tscn` | Three inspectable sites |
| `game/heir/decision_point.gd` / `.tscn` | Opens the plan panel |
| `game/heir/town_hall.gd` / `.tscn` | Final council vote |
| `game/ui/dialogue/dialogue_box.tscn` / `.gd` | NPC and site dialogue |
| `game/ui/decision/decision_panel.tscn` / `.gd` | Three-plan modal |
| `game/ui/ending/ending_screen.tscn` / `.gd` | Choice-driven epilogue |

## Verification

```bash
GODOT_BIN=/Applications/Godot.app/Contents/MacOS/Godot
"$GODOT_BIN" --headless --audio-driver Dummy --quit-after 5 \
  --scene res://game/world/maps/Heir.tscn
GODOT_BIN="$GODOT_BIN" bash addons/gdUnit4/runtest.sh \
  --headless --audio-driver Dummy --ignoreHeadlessMode \
  --continue --add res://tests
```

Focused suites: `tests/unit/test_heir_map.gd` and `tests/unit/test_ending.gd`.
