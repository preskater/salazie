# Map 2 — Le cultivateur

Technical reference for the second map of Salazie. Narrative intent lives in
[LORE.md](../../LORE.md#map-2--le-cultivateur); this note records what is built and where.

- Scene: `game/world/maps/Farm.tscn`, root script `game/farm/farm_map.gd`
- Size: 96 × 68 tiles at 48 px → 4608 × 3264 px
- Player: `World/Player2`, spawned at `PlayerSpawn` `(2280, 3168)`, tile `(47.5, 66)`
- The game boots on `game/ui/menus/main_menu.tscn`; **Nouvelle partie** or **Continuer**
  loads `Farm.tscn`. Open the scene directly to test the map without the menu.

## Scene structure

| Node | Type | Role |
|---|---|---|
| `Farm` | `Node2D` + `farm_map.gd` | Map manager: interactions, objectives, wiring |
| `Ground` | `TileMapLayer` | Terrain, paths, tilled soil and water (`game/world/tilesets/terrains.tres`) |
| `World` | `Node2D`, y-sorted | Y-sorted props, plots, NPCs, animals, animated trees |
| `World/Fences` | `TileMapLayer` | Pens, pastures, field fences (`game/world/tilesets/fences.tres`) |
| `World/Player2` | `CharacterBody2D` | Farmer controller |
| `Bounds` | `StaticBody2D` | Map edges |
| `HUD` | `CanvasLayer` (layer 10) | `FarmHUD` overlays and prompts |

## Layout (tile coordinates, 48 px tiles)

| Zone | Area | Content |
|---|---|---|
| Farmstead | x 28–62, y 20–31 | Farmer house, barn, silo, well, doghouse, tractor, scarecrow |
| Kitchen garden | x 32–35, y 35–36 | 8 `CropPlot`s (4 start tilled); the objective target |
| Cow pasture | x 30–44, y 42–49 | Fenced pen; 3 cows |
| Hen pen | x 50–62, y 35–42 | Fenced pen, coop, henhouse, feeder; 3 hens, 1 rooster, 2 chicks |
| Market hamlet | x 38–56, y 56–64 | Market stand, crates, cottage, seller and villager |
| Lake | x 68–90, y 34–50 | Waterfall at x 78–80, island, peninsula, east outlet |
| River | y 4–26 | 3 tiles wide, centre winds between x 75 and x 80 |
| Forest | west x 2–29 y 6–64, north y 0–10, east x 83–94 y 18–33 | Oak, pine and birch trees; dense canopy in the thickets |

Landmarks in world pixels: `MarketStand` `(1992, 2976)`, `NPCSeller` `(1992, 2736)`,
`NPCVillager` `(2616, 3072)`, `Cottage` `(2640, 3024)`, waterfalls and water as above.

## Gameplay loop

Prepare a plot → plant the selected seed → wait for growth → harvest → sell at the market →
buy more seeds. Prices change when the day changes.

- Start: **30 G**, day 1, seeds `corn ×2, pumpkin ×1, tomato ×2, carrot ×1`
- Day length: **60 s**; prices reroll each day by about **±25 %** around the base price
- Selling pays the current daily price; buying a seed costs its `seed_price`

| Crop | Label | Seed | Base price | Growth |
|---|---|---|---|---|
| `corn` | Maïs | 4 G | 10 G | 18 s |
| `pumpkin` | Potiron | 6 G | 16 G | 24 s |
| `tomato` | Tomate | 4 G | 9 G | 16 s |
| `carrot` | Carotte | 3 G | 7 G | 12 s |

`CropPlot` states: `EMPTY → TILLED → GROWING → READY → TILLED` after harvest. Sprout and
mid-stage textures swap automatically while growing.

Objectives, in order: prepare a plot, plant a seed, harvest a crop, sell produce, reach 100 G.

### Controls

| Action | Keys | Effect |
|---|---|---|
| `move_*` | WASD / arrows | Move |
| `interact` | E | Prepare, plant, harvest, open market, talk |
| `select_seed_1..4` | 1–4 | Choose seed (also in the inventory popup) |
| `toggle_inventory` | I | Inventory popup (pause) |
| `toggle_prices` | P | Show/hide market prices |
| `pause` | Esc / Start | Open the pause menu |
| `ui_cancel` | Esc / B | Close the open overlay |

The HUD shows money and day (top-left), the current objective (top-centre), interaction
prompts and notifications. The market overlay pauses the game; the inventory and price
overlays never duplicate each other. The pause menu only opens when no HUD overlay owns the
pause, so `Esc` closes the market or inventory first.

See [docs/UI.md](../UI.md) for the title screen, options and save format.

## Living world

### Trees

446 trees are `AnimatedSprite2D` using the pack's 3-frame shake strips.

- 442 forest trees (154 colliding tree props, 118 `DenseTree_`, 170 `DenseCanopy_`)
- 4 fruit trees (apple, orange, peach, lemon)
- Dense-canopy trees have no collision; all other trees keep a per-tree
  `RectangleShape2D` sized from the original prop
- Shared `SpriteFrames` live in `game/world/animations/`; `game/world/tree_sway.gd`
  randomises start frame and speed per tree so the canopy is not synchronised

### Animals

| Nodes | Sheet | Frame cell | Speed |
|---|---|---|---|
| `CowWhite`, `CowBlack`, `CowCaramel` | `Cow_Big_White/Black`, `Cow_Caramel` | 144 × 144 | 15 px/s |
| `ChickenWhite`, `ChickenBrown`, `ChickenGolden` | `Chicken_*` | 48 × 48 | 30 px/s |
| `RoosterBrown` | `Rooster_Brown` | 48 × 96 | 27 px/s |
| `ChickA`, `ChickB` | `Chick` | 48 × 48 | 36 px/s |

`game/farm/animals/animal.gd` builds four walk and four graze animations from each sheet
(24 columns × 4 rows; row 1 = walk, row 3 = graze; direction groups of 6: right, up, left,
down). The AI alternates grazing and walking to a random point inside `roam_rect`:

- cows `Rect2(1440, 2040, 624, 288)` — cow pasture
- hens, rooster and chicks `Rect2(2448, 1728, 480, 264)` — hen pen

Animals are decorative: no collision, no production, no interaction. They are `Node2D`
children of `World`, so Y-sorting is handled by their feet.

### NPCs

`NPCSeller` (“Marchande”, blue tint) and `NPCVillager` (“Habitant”, warm tint) use the farmer
`sprite_frames`. They idle and walk in four directions, patrol within 18 px of their home
point, and turn to face the player when within 96 px. Talking (E) plays a random line from
their `lines` export. `FarmMap` assigns each NPC the player reference on ready.

### Crops and ambient details

- 30 decorative field crops (`Crop_*` sprites) sway from their base with
  `game/world/crop_sway.gd`
- `CropPlot` sprites swap growth textures; the gameplay plots do not sway
- 10 ambient leaf emitters (green, yellow, brown 24-frame loops) drift through the forest;
  scene `game/world/ambient_leaves.tscn`, frames `game/world/animations/Leaves_*.tres`

## Animation resource rules

- Tree shake sheets are horizontal strips of **3 frames**. The frame is
  `sheet_width / 3 × sheet_height`; static textures and shake frames normally share a size.
- **Fruit-tree exception:** Peach frames are `240 × 240` from a `720 × 240` sheet (static
  texture is 192 × 192) and Lemon frames are `192 × 240` from a `576 × 240` sheet. Both
  sprites use `offset = (0, -120)`. Do not derive fruit frame size from the static texture.
- Animal frames are sliced at runtime by `FarmAnimal`; there are no per-animal `.tres`
  files to maintain.
- When adding a tree type, add the static texture under `singles/Trees/`, the matching
  `animated/Trees_<name>_Shake_48x48.png`, a 3-frame `SpriteFrames` resource in
  `game/world/animations/`, and instance it with `tree_sway.gd`.

## Files

| Path | Purpose |
|---|---|
| `game/farm/game_state.gd` | Autoload: money, day, crops, seeds, produce, prices, signals |
| `game/farm/crop_plot.gd` / `.tscn` | Plot states, growth, harvest |
| `game/farm/market_stand.gd` / `.tscn` | Market interaction point |
| `game/farm/npc.gd` / `.tscn` | Dialogue, patrol and player-facing |
| `game/farm/farm_hud.gd` / `.tscn` | HUD, market, inventory, prices |
| `game/farm/farm_map.gd` | Manager and objective tracker |
| `game/farm/animals/animal.gd` / `.tscn` | Animal frames and roaming AI |
| `game/world/tree_sway.gd`, `crop_sway.gd`, `ambient_leaves.gd` / `.tscn` | World animation helpers |
| `game/world/animations/` | Shared tree and leaf `SpriteFrames` |
| `game/world/WorldObject.tscn` | Reusable prop: texture, bottom-centred collision |
| `game/ui/theme/salazie_theme.tres` | Shared UI-pack theme for menus and HUD |
| `game/ui/menus/` | Title screen, options, pause, controls, credits, confirmations |
| `game/ui/hud/hud.tscn` / `.gd` | Survival bars and UI-pack icons |
| `game/systems/save/`, `game/systems/settings/`, `game/systems/scene_router.gd` | Save, settings and scene lifecycle |

## Verification

```bash
GODOT_BIN=/Applications/Godot.app/Contents/MacOS/Godot   # macOS; `godot` on Linux/CI
"$GODOT_BIN" --headless --import
"$GODOT_BIN" --headless --audio-driver Dummy --quit-after 30 --scene res://game/world/maps/Farm.tscn
python3 .claude/skills/godot-nodes-scenes/scripts/check_godot_project.py . --json
```

Tests: `tests/unit/test_player.gd` and `tests/unit/test_farm_life.gd` (animal animations,
roam bounds, tree and leaf frames, fruit slice geometry, NPC facing), plus the menu,
settings, save and UI-asset suites in `tests/unit/`. Status at time of writing: 52/52
gdUnit4 tests pass.

## Known limits

- One autosave slot managed by `SaveGame`; state still resets if the save file is deleted.
- Animals are decorative; they do not produce eggs or milk and do not react to the player.
- Fruit trees and field crops are visual only; only the 8 `CropPlot`s are harvestable.
- No audio assets yet.
