# Map 3 — L'héritier

Technical reference for the final generation of Salazie. Narrative intent lives in
[LORE.md](../../LORE.md#map-3--lhéritier); this note records what is built and where.

- Scene: `scenes/maps/heir.tscn`, root script `scripts/heir/heir_map.gd`
- Size: 72 × 52 tiles at 48 px → 3456 × 2496 px
- Player spawn: `(1752, 2376)`, tile `(36, 49)`
- Entered from `farm.tscn` after the farm generation is resolved

## Scene structure

| Node | Type | Role |
|---|---|---|
| `Heir` | `Node2D` + `heir_map.gd` | Campaign flow, interactions, final vote |
| `Ground` | `TileMapLayer` | Modern ground, river, roads, plaza, paths |
| `World` | `Node2D`, y-sorted | Player, buildings, props, NPCs, sites, landmarks, trees |
| `Bounds` | `StaticBody2D` | Map edges |
| `PlayerSpawn` | `Marker2D` | South entrance marker |
| `TaskList`, `GenerationResult`, `DialogueBox`, `DecisionPanel` | `CanvasLayer` | Created by the controller |
| `Overlay` | `CanvasLayer` (layer 5) | Heritage, hint, prompt and notification labels |

The world layout is authored in the scene. The controller only spawns the player, builds
the UI, connects the groups and runs the campaign logic.

## Layout

| Zone | Area | Content |
|---|---|---|
| South entrance | x 32–40, y 39–51 | Spawn, bus shelter, street and sidewalks |
| Central square | x 26–44, y 28–38 | Fountain, market stalls, decision point, candy cart, benches |
| Town hall | x 28–44, y 20–27 | Mairie, forecourt, solar panels, EV charger, mailboxes |
| West river | x 10–16, y 4–51 | Waterfall, winding river, bridge on the west road, eroded bank |
| West houses | x 19–29, y 9–29 | Two creole houses, riverbank trail, fisherman |
| East park | x 48–71, y 4–28 | Forest, trail, fragile forest, ranger, belvédère |
| School | x 56–66, y 20–27 | Court, clock tower, flag, basketball hoops |
| East houses | x 44–71, y 29–50 | Modern one-storey house, villa, Mme Payet |
| Shared garden | x 21–25, y 42–46 | Soil, vegetables, flower beds, landmark |

The main street runs south–north to the square; the west road crosses the river at
y 34–41 and meets the square. The park trail starts at the square's east side and forks
towards the school, the fragile forest and the belvédère.

World landmarks: `Mairie` `(1752, 1008)`, fountain `(1464, 1680)`, decision point
`(1560, 1800)`, town-hall interaction `(1752, 1128)`, market site `(1944, 1560)`,
eroded bank `(840, 1176)`, fragile forest `(2616, 696)`, belvédère `(3336, 648)`,
shared garden `(1128, 2136)`, south bus stop `(1992, 2184)`, north bus stop `(1992, 1224)`.

## Tasks

| ID | Success | Failure |
|---|---|---|
| `listen` | Talk to 3 different inhabitants | — |
| `assess` | Inspect the 3 fragile sites | — |
| `choose_plan` | Choose forest, tourism or family farms | — |
| `become_mayor` | Present the plan with enough support | The council rejects the plan |

## Council vote

`become_mayor` is resolved from the **support score**, shown at all times in the top-left
corner and in the town-hall prompt. `Campaign.SUPPORT_NEEDED` (6) voices are required.

| Line | Voices | How |
|---|---|---|
| Inherited | 5 − failure events of the three generations (min 0) | What the family did before |
| Sites | +1 per fragile site funded (max 3) | Inspect a site, then interact again to pay for its protection |
| Residents | +1 | Listen to all five residents (the `listen` task only needs three) |
| Landmarks | +1 | Visit the belvédère and the shared garden |
| Coherence | +1 | The plan matches what was done: `forest` with the forest or the bank funded, `tourism` with both landmarks visited, `farms` with the market funded |

A flawless family arrives with 5 and still has to act once; a family with three failures
arrives with 2 and needs four of the six voices available. The vote is final: a rejection
gives the secondary epilogue and does not block the ending.

## Budget

`HeirMap._enter_tree()` selects the `heritier` economy and converts the heritage once:
the euro wallet starts at the heritage, green credits at 0. A save made in the village
already holds the heir's wallets and is left alone.

| Site | Offer (`economy.tres`) | Price |
|---|---|---|
| Eroded bank | `building_wetland` | 80 € |
| Fragile forest | `item_seedling_kit` | 15 € |
| Flood-prone market | `slot_refuge` | 12 CV |

Green credits are the residents' trust: +4 CV for each resident heard for the first time,
+3 CV for each landmark. The market is therefore secured by listening, not by money, and a
small heritage can still afford the forest.

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
heritage = floor(farm net worth × (1 − 0.1 × Map 2 failure events))
```

The heritage is displayed in the top-left label and in the epilogue, above the remaining
budget (`BudgetLabel`) and the support score (`SupportLabel`).

## Living world

- **Trees:** 46 colliding animated trees and 28 non-colliding canopy trees use the shared
  3-frame shake resources in `game_resources/animations/` and `scripts/world/tree_sway.gd`.
  Dense canopy trees are in the park; the village trees keep a base collision.
- **Leaves:** 8 ambient leaf emitters (`scenes/world/ambient_leaves.tscn`) drift through the
  park and the riverbank.
- **NPCs:** 5 villagers use the 16 × 16 Amelia, Bob and Adam sheets via the optional
  `sprite_frames` and `sprite_scale` exports of `FarmNPC`. They idle, walk, patrol their
  home area and turn to face the player. Each has a custom `talk_prompt`.
- **Street life:** parked car, mailboxes, solar panels, EV charger, street lamps, benches,
  bins, hydrant, pigeons and a candy cart.
- **Optional interactions:** the belvédère and the shared garden show a flavour line and
  record a `Campaign` choice (`visited_belvedere`, `visited_jardin`) without touching the
  tasks or the support score.
- **Shuttle:** the two stops (south entrance and mairie forecourt) animate a full ride:
  the yellow bus arrives from the south edge, stops beside the shelter, the player walks
  to the door and boards, the camera follows the bus along the main street and through
  the square to the other stop, the player steps out to the stop, and the bus drives away
  south. `HeirMap.ride_finished` is emitted at the end for tests. The square props
  (fountain, benches, cart, pigeons) were shifted west so the bus lane stays clear.

## Controls

| Action | Keys | Effect |
|---|---|---|
| `move_*` | WASD position / arrows, left stick / D-pad | Move |
| `interact` | E, gamepad A | Talk, inspect, fund a site, decide, board the shuttle, present the plan |
| `toggle_tasks` | T / Select | Open the task list |
| `pause` | Esc / Start | Pause menu |

## Assets and resources

| Path | Purpose |
|---|---|
| `game_resources/tilesets/heir_terrains.tres` | Farm grass/water/path/soil + city asphalt/sidewalk atlas |
| `game_resources/animations/*_frames.tres` | Adam, Amelia and Bob idle/walk frames (16 × 32) |
| `sprites/exteriors_48x48/` | Asphalt and sidewalk terrain cells, buildings, props, vehicles |
| `sprites/farm_48x48/` | Creole houses, market stands, crops, trees, water and fences |
| `sprites/custom/waterfall_144x432.png` | Waterfall at the river source |

The mairie reuses the post-office facade, with a `Mairie` label at the entrance. The
school is represented by the clock tower, court and sports furniture rather than the
24 × 23-tile school illustration.

## Files

| Path | Purpose |
|---|---|
| `scenes/maps/heir.tscn` | Map layout and placed content |
| `scripts/heir/heir_map.gd` | Controller: campaign, tasks, prompts, ending |
| `scripts/heir/fragile_site.gd` / `scenes/heir/fragile_site.tscn` | Three inspectable sites |
| `scripts/heir/decision_point.gd` / `scenes/heir/decision_point.tscn` | Opens the plan panel |
| `scripts/heir/town_hall.gd` / `scenes/heir/town_hall.tscn` | Final council vote |
| `scripts/heir/landmark_point.gd` / `scenes/heir/landmark_point.tscn` | Belvédère and shared garden |
| `scripts/heir/bus_stop.gd` / `scenes/heir/bus_stop.tscn` | Shuttle stops |
| `scripts/heir/shuttle.gd` / `scenes/heir/shuttle.tscn` | Animated shuttle ride |
| `game_resources/animations/shuttle_frames.tres` | Bus frames per direction |
| `scenes/ui/dialogue/dialogue_box.tscn` / `scripts/ui/dialogue/dialogue_box.gd` | NPC and site dialogue |
| `scenes/ui/decision/decision_panel.tscn` / `scripts/ui/decision/decision_panel.gd` | Three-plan modal |
| `scenes/ui/ending/ending_screen.tscn` / `scripts/ui/ending/ending_screen.gd` | Choice-driven epilogue |
| `scenes/ui/tasks/task_list.tscn`, `generation_result.tscn` | Task list and result overlay |
| `scenes/world/world_object.tscn` / `scripts/world/world_object.gd` | Reusable colliding prop |
| `scenes/world/ambient_leaves.tscn` / `scripts/world/ambient_leaves.gd` | Leaf emitters |

## Verification

```bash
GODOT_BIN=/Applications/Godot.app/Contents/MacOS/Godot
"$GODOT_BIN" --headless --audio-driver Dummy --quit-after 30 \
  --scene res://scenes/maps/heir.tscn
GODOT_BIN="$GODOT_BIN" bash addons/gdUnit4/runtest.sh \
  --headless --audio-driver Dummy --ignoreHeadlessMode \
  --continue --add res://tests
```

Focused suites: `tests/unit/test_heir_map.gd` (map content, tasks, landmarks, shuttle
arrival/boarding/ride/exit) and `tests/unit/test_ending.gd`. Status at time of writing:
158/158 gdUnit4 tests pass.

## Known limits

- The school is a courtyard and clock tower, not a full interior; buildings are facades.
- Vehicles are static; traffic is limited to the parked car and the shuttle interaction.
- Audio is synthesised placeholder material; see [AUDIO.md](../AUDIO.md).
