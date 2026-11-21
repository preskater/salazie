# Map 1 — Le marron

Technical reference for the first generation of Salazie. Narrative intent lives in
[LORE.md](../../LORE.md#map-1--le-marron); this note records what is built and where.

- Scene: `scenes/maps/maroon.tscn`, root script `scripts/maroon/maroon_map.gd`
- Size: 72 × 112 tiles at 48 px → 3456 × 5376 px
- Player spawn: tile `(14, 101)` on the southern beach
- New game starts here; the chapter fade leads to `farm.tscn` once the refuge is reached.

## Journey

The player escapes from the sea and follows the river upstream to the mountain pass.
The river is the spine of the map: it widens into a lagoon at the mouth, narrows
between two bridges, drops through a broad waterfall in the gorge and ends at the
mountain source above the refuge.

| Tiles y | Zone | Content |
|---|---|---|
| 106–112 | Sea | animated water shader, tide foam, buoys, wreck rocks |
| 92–108 | Beach and mouth | spawn, palms, shells, driftwood, seagulls, ruined dock, wrecked boat |
| 78–94 | Estuary | wooden bridge, fishing boat, fish, ducks, first patrol |
| 62–80 | Wide river | second bridge, forest camp, river pool |
| 46–70 | Tropical forest | tents, campfire, forage, two hide spots, two patrols |
| 36–48 | Gorge and waterfall | animated cascade, pool, rocks, cave tunnel, waterfall alcove, third bridge |
| 20–40 | Mountain forest | pines, birches, boulders, goats, pass, cliff-ridge trail, two hide spots |
| 8–22 | Col and refuge | cabin, well, campfire, lanterns, fence, `MapExit` |
| 0–8 | Rocky crest | large boulders and pines, collision band |

The trail is painted from the beach to the cabin. It crosses the river on three
bridges at rows 84, 52 and 26; everywhere else the water blocks movement.

## Routes and stealth

Two optional routes parallel the main trail through the gorge.

| Route | Entry / exit | Mechanics |
|---|---|---|
| Cave tunnel | Trail at `(21, 50)` → `(20, 36)`, west of the trail | dark floor shade, rock walls, lanterns, food at `(18, 42)`, hide spot at `(18, 44)`; the cave zone conceals the player and mutes running noise |
| Cliff ridge | Climb `(39, 51)` → `(42, 48)`, then climb `(42, 30)` → `(44, 28)` | sealed lane of rock walls, lanterns, hide spot at `(42, 40)`; both climbs are interactive and fade the screen |

- The waterfall spray is a third stealth zone (`(28, 41)`, 9 × 4 tiles): it only
  mutes noise, it does not conceal the player. The alcove at `(26, 42)` nests
  inside it and both conceals and mutes.
- `climb_point.gd` joins the `interactable` group; `E` starts a 0.22 s fade,
  teleports the player to the destination and fades back in, then emits
  `climb_finished`.
- `stealth_zone.gd` joins the `stealth_zones` group. On exit it only clears
  concealment or noise muting when no other overlapping zone still provides it,
  so nested zones behave.
- The player has `noise_muted`; while set, `emit_noise()` skips the guard
  broadcast. Guards keep their normal vision, chase and catch logic.

## Scene structure

`maroon.tscn` stays minimal: the root builds `Terrain` (four `TileMapLayer`s, a
bridge-deck layer and the collision body) and a y-sorted `World` (props, player,
guards, pickups and animals).

| Node | Type | Role |
|---|---|---|
| `Maroon` | `Node2D` + `maroon_map.gd` | Gameplay, tasks, UI, respawns |
| `Terrain` | `Node2D` | Ground, water, bridges, cliff accents, collisions |
| `Terrain/Water` | `TileMapLayer` | River and sea; `water_flow.gdshader` |
| `World` | `Node2D`, y-sorted | Static props, player, guards, pickups, animals |
| `World/Player` | `CharacterBody2D` | Player with active `SurvivalComponent` |
| `World/RiverMouthCheckpoint` | `Area2D` | Completes `follow_river` |
| `World/ForestCheckpoint` | `Area2D` | Mid-map respawn point |
| `World/UpperCheckpoint` | `Area2D` | Completes `cross_patrol` after the gorge |
| `World/Climb_*` | `Area2D` | Ridge climb points (`climb_point.tscn`) |
| `World/Stealth_*` | `Area2D` | Cave, cascade spray and alcove zones (`stealth_zone.tscn`) |
| `Overlay` | `CanvasLayer` | Controls hint, notifications, interaction prompt, objective tracker |
| `SurvivalHUD` | `CanvasLayer` | Food and water bars |
| `TaskList` | `CanvasLayer` | Generation task list |
| `GenerationResult` | `CanvasLayer` | Result shown before leaving |
| `RefugeExit` | `MapExit` | Final task and transition to Map 2 |

## Tasks

| ID | Success | Failure | Retry |
|---|---|---|---|
| `follow_river` | Reach the estuary checkpoint | — | — |
| `find_water` | Drink at the waterfall basin (`E` near the pool) | — | — |
| `find_food` | Collect 3 wild foods | — | — |
| `hide_from_patrol` | Stay hidden for 1.5 s | Spotted while trying to hide | Yes |
| `cross_patrol` | Reach the upper checkpoint | Caught by a guard | Yes |
| `reach_refuge` | Enter the cabin | — | — |

Being caught records a failure for `cross_patrol` and, if not already hidden, for
`hide_from_patrol`. The player respawns at the last checkpoint, the failed tasks return to
`PENDING`, and the failure history stays in the generation result.

## Objective indicator

The HUD shows exactly one objective tracker at a time (gold arrow, task label and
distance in metres). It follows the first unresolved task in `Campaign.TASKS[1]`
order and never marks the other pending tasks.

| Task | Indicator points at |
|---|---|
| `follow_river` | River-mouth checkpoint |
| `find_water` | Waterfall basin |
| `find_food` | Nearest unused food spot |
| `hide_from_patrol` | Nearest hide spot |
| `cross_patrol` | Upper checkpoint |
| `reach_refuge` | Refuge exit |

The tracker updates as soon as a task is resolved; `find_food` also shows the
current `(n/3)` progress. It lives under `Overlay/ObjectiveBar` in
`maroon_map.gd`; no world nodes are created.

Saves written before `follow_river` existed are migrated: when the saved game is already
past Map 1, the river task is marked done.

## Survival and stealth

- `SurvivalComponent`: food drains at 0.35/s, water at 0.55/s.
- Forage restores 28 food.
- Drinking is an `E` interaction at any freshwater bank (river, estuary, pool).
  Each drink restores 10 water. The sea is salt water and cannot be drunk.
- Drinking has a 10 s cooldown. Salazie's rivers carry fine volcanic silt: the
  gourd must stand for about ten seconds so the silt settles before the next
  sip. The prompt shows the remaining settling time.
- The first drink within 12 tiles of `WATER_SPOT_TILE` (the waterfall basin)
  completes `find_water`. There are no water forage pickups any more.
- A concealed player is ignored by guards beyond 32 px.
- Running emits noise unless the player is inside the cave or the waterfall
  spray, where the ambient noise masks the steps.
- Guards use the existing vision cone, chase and catch logic with `pause_on_catch = false`
  so the map can respawn the player.

## Static world builders

| File | Role |
|---|---|
| `scripts/maroon/maroon_layout.gd` | River curve, ground/water painting, bridges, waterfall, cliffs, props, zones |
| `scripts/maroon/maroon_decor.gd` | Asset catalogue and node factory (props, trees, sheet animations, animals) |
| `scripts/world/animated_sheet.gd` | Slices a sheet row into a one-animation `SpriteFrames` |
| `scenes/world/animated_sheet.tscn` | Reusable animated sheet node |
| `scenes/world/tree_shake.tscn` | Reusable tree sway node |
| `game_resources/tilesets/maroon_ground.tres` | Ground, sand, dirt, water and cliff accents |
| `shaders/world/water_flow.gdshader` | Moving highlights on the water layer |
| `shaders/world/waterfall_flow.gdshader` | Scrolling water on the custom cascade |

The TileSet is generated by `tools/build_maroon_tilesets.gd` (Godot's TileSet editor is
click-only, so the generator stays in the repository):

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
  --script res://tools/build_maroon_tilesets.gd
```

`tools/preview_maroon.gd` renders zone screenshots, `tools/preview_maroon_anim.gd`
captures the animated inhabitants, `tools/make_fish_sheets.gd` regenerates the
transparent fish copies, `tools/check_maroon_paths.gd` proves every bridge is
crossable and that open water blocks movement, and
`tools/check_maroon_anchors.gd` verifies that no task anchor sits inside a
static collision.

## Tile transitions

The ground layer does not paint flat tiles at terrain changes. It builds a type
map first (`water`, `sand`, `dirt`, `grass`) and then picks a 3×3 pack variant
from the matching block.

| Transition | Pack block | Center tile |
|---|---|---|
| Grass ↔ dirt (trail, clearings) | `farm_48x48/tilesets/1_Terrains_48x48.png`, cols 0–2, rows 0–2 + corridor tiles `(15,9)` / `(17,9)` | `(1,1)` |
| Grass ↔ water (river, gorge) | `exteriors_48x48/tilesets/1_Terrains_and_Fences_48x48.png`, cols 8–10, rows 6–8 | `(9,7)` |
| Sand ↔ water (beach, estuary) | `Sea_Water_Tileset_48x48.png`, rim overlays `(1,0)` / `(5,0)` rotated on water cells | pure sand |
| Sand ↔ grass (beach top, river rim) | `farm_48x48/tilesets/1_Terrains_48x48.png`, cols 0–2, rows 4–6 | `(1,5)` |

Rules:

- Water cells always use the clean `(27,5)` water tile. Grass and dirt own
  their land-side edge art; sand stays pure and the water side carries the
  foam/sand contour.
- Grass checks water first, then stays a pure centre tile. Sand checks grass
  and dirt first. Dirt checks grass.
- Trails are one tile wide. Straight vertical runs use the farm dirt corridor
  `(15,9)`, horizontal runs use `(17,9)`, and bends use the 3x3 dirt patch edges.
- Sand/water coast: one `Sprite2D` overlay per water cell side reads the sea
  water N/S rim tiles, rotated for east/west. `shaders/world/water_edge.gdshader`
  keeps only the sand and foam pixels, so corner overlays stack without hiding
  each other or the animated water body.
- Diagonal-only neighbours keep the centre tile: the packs do not ship a true
  inner-corner variant, and borrowing an outer corner would flood the cell with
  water or dirt.
- The random shade pass was removed so centre and edge tiles always share the
  same grass colour.

## Assets used

Ground and water come from the vendored LimeZu packs:

- `sprites/exteriors_48x48/tilesets/1_Terrains_and_Fences_48x48.png` — grass, dirt, deep water
- `sprites/farm_48x48/tilesets/1_Terrains_48x48.png` — dirt path variants
- `sprites/exteriors_48x48/tilesets/21_Beach_48x48.png` — sand variants
- `sprites/farm_48x48/singles` — trees, rocks, cabin, canopies, crates, signs, well
- `sprites/exteriors_48x48/singles/21_Beach` — palms, sea rocks, shells, starfish
- `sprites/exteriors_48x48/singles/11_Camping` — tents, campfires, logs, lanterns,
  sleeping bags, backpacks, benches, fishing crates, pier and dock pieces
- `sprites/exteriors_48x48/singles/17_Garden` — flowers
- `sprites/exteriors_48x48/singles/1_Terrains_and_Fences` — grass tufts, mound accents
- `sprites/custom/waterfall_gorge_288x432.png` — wide gorge cascade
- `sprites/custom/waterfall_144x432.png` — mountain source cascade
- `sprites/custom/fishes_1/2/3.png` — fish sheets with the water background keyed out

World props are bottom-anchored for y-sorting; fish and mist are centred in
their cell.

## Animations

| Effect | Source | Slice / rules |
|---|---|---|
| Water highlights | `water_flow.gdshader` on `Terrain/Water` | Static pure water tile; moving crests |
| Cascade | `waterfall_flow.gdshader` + `sprites/custom/waterfall_gorge_288x432.png` | Integer scale 1.0, scrolling shader; mountain source uses `waterfall_144x432.png` |
| Seagulls | `Beach_Seagull_Idle_{Down,Left,Right}_48x48.png` | Down: 6 frames, cell 48×48; left/right: 6 frames, cell **96×48**, row 0 |
| Boats and buoys | `Fishing_Boat_right_48x48.png`, `Beach_Water_Buoy_1/2_48x48.png` | Boat cell **240×96**, 8 frames; buoys cell **96×96**, 8 frames; bottom anchored |
| Fish | `sprites/custom/fishes_1/2/3.png` | Copies of `Fishes_*` with the flat water colour keyed out; 48×48, 12 / 14 / 14 frames, centered in water |
| Campfire | `Campfire_48x48.png` | **Row 1** (logs + flames), 6 frames |
| Lanterns | `ME_Singles_Camping_48x48_Lantern_1.png` | Static prop, no frame cycling |
| Mist | `...Fog_Only_Loop_48x48.png` | **Row 1**, 6 frames of **288×48** |
| Smoke | `Stone_Oven_Smoke_Effect_48x48.png` | 8 frames of **144×192**, bottom anchored above the fire |
| Trees | `game_resources/animations/Tree_*_Shake.tres` | Existing 3-frame `shake` animations |
| Falling leaves | `Leaves_Green/Brown/Yellow.tres` | Existing `fall` animations |
| Goats | `Goats_48x48/Goat_*.png` | **Cell 96×144**, walk row **2**, graze row **3**, 6 frames per direction |
| Rabbits and ducks | `Rabbits/Ducks_48x48/*.png` | **Cell 96×96**, walk row **2**, graze row **3**, 6 frames per direction |
| Crows | `Crow_Flap_Right_48x48.png` | **6 frames** of **96×96**, row 0, horizontal tween |
| Grass sway | `crop_sway.gd` | Small tufts only |

Animal direction groups in the LimeZu sheets are ordered **left, up, right,
down**, not right/up/left/down. The fish background is the pack's flat water
colour, so `tools/make_fish_sheets.gd` copies the three sheets to
`sprites/custom/` with that colour made transparent.

The animated water sheets in the pack are **shoreline autotile** sheets; they do
not contain a clean pure-water body. The water body therefore animates through
the crest shader, while the land/water edge uses the static pack variants.

## Prop conventions

- **Integer scales only.** Small/medium/big sizes come from the asset variants,
  never from random `scale` values. This keeps pixel art crisp and hitboxes
  predictable.
- **Fences** are the `Rod_Rope_Horizontal_*` line, terminated by a wooden post.
  The isolated `Wooden_Fence_Type_1_Brown` pieces are no longer scattered.
- **Campfires**: both camps use the complete log fire (`Campfire_48x48` row 1).
  The separate hanging pot and cooking-tripod duplicate were removed.
- **Dock**: one small south-facing pier at the beach (`Pier_Bridge_1`) with
  barrels, fish crates and a boat; no diagonal pile of `Pier_3/4`.
- **Vegetation**: natural `Garden/Bush_*` for scatter and hide spots; big
  flowers are placed manually near the tents and cabin, not randomly.
- **Water and sand props** are reserved around task anchors so a rock or barrel
  cannot cover the player or a checkpoint.

## Result and carry-over

- Map result: done / failed / failure events / rank.
- Each Map 1 failure event removes 5 G from the farmer's starting money, down to 15 G.
- The generation result is shown before the chapter fade to `farm.tscn`.

## Controls

| Action | Keys | Effect |
|---|---|---|
| `move_*` | WASD / arrows | Move |
| `run` | Shift | Run, emits noise |
| `interact` | E | Climb between the river trail and the cliff ridge; drink at a freshwater bank |
| `toggle_tasks` | T / Select | Open the task list |
| `pause` | Esc / Start | Pause menu |

## Files

| Path | Purpose |
|---|---|
| `scenes/maps/maroon.tscn` | Minimal map scene |
| `scripts/maroon/maroon_map.gd` | Gameplay, UI, tasks and respawns |
| `scripts/maroon/maroon_layout.gd` | Static world generation |
| `scripts/maroon/maroon_decor.gd` | Props and animation factory |
| `scripts/maroon/forage_spot.gd` / `scenes/maroon/forage_spot.tscn` | Wild food pickups |
| `scripts/maroon/hide_spot.gd` / `scenes/maroon/hide_spot.tscn` | Concealment and hide task |
| `scripts/maroon/climb_point.gd` / `scenes/maroon/climb_point.tscn` | Ridge climb interaction |
| `scripts/maroon/stealth_zone.gd` / `scenes/maroon/stealth_zone.tscn` | Concealment and noise-masking areas |
| `scripts/maroon/checkpoint.gd` / `scenes/maroon/checkpoint.tscn` | Respawn point and route tasks |
| `scripts/systems/campaign/campaign_state.gd` | Task states, failures and generation result |
| `scenes/ui/tasks/task_list.tscn` / `scripts/ui/tasks/task_list.gd` | Task list UI |
| `scenes/ui/tasks/generation_result.tscn` / `scripts/ui/tasks/generation_result.gd` | Generation result overlay |
| `tools/build_maroon_tilesets.gd` | TileSet generator |
| `tools/make_fish_sheets.gd` | Fish-sheet transparency generator |
| `tools/preview_maroon.gd` | Zone screenshot helper |
| `tools/preview_maroon_anim.gd` | Animation close-up screenshot helper |
| `tools/check_maroon_paths.gd` | Bridge and water collision helper |
| `tools/check_maroon_anchors.gd` | Task-anchor collision helper |

## Verification

```bash
GODOT_BIN=/Applications/Godot.app/Contents/MacOS/Godot
"$GODOT_BIN" --headless --import
"$GODOT_BIN" --headless --audio-driver Dummy --quit-after 5 \
  --scene res://scenes/maps/maroon.tscn
GODOT_BIN="$GODOT_BIN" bash addons/gdUnit4/runtest.sh \
  --headless --audio-driver Dummy --ignoreHeadlessMode \
  --continue --add res://tests
```

Focused suite: `tests/unit/test_maroon_map.gd`.
