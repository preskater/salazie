# Map 2 — Le cultivateur

Technical reference for the second map of Salazie. Narrative intent lives in
[LORE.md](../../LORE.md#map-2--le-cultivateur); this note records what is built and where.

- Scene: `scenes/maps/farm.tscn`, root script `scripts/farm/farm_map.gd`
- Size: 96 × 68 tiles at 48 px → 4608 × 3264 px
- Player: `World/Player2`, spawned at `PlayerSpawn` `(2280, 3168)`, tile `(47.5, 66)`
- The game boots on `scenes/ui/menus/main_menu.tscn`; **Nouvelle partie** now loads
  `maroon.tscn`. **Continuer** loads the saved generation. Map 2 is entered from the
  refuge of [Map 1](MAP1.md), or opened directly for testing.

## Scene structure

| Node | Type | Role |
|---|---|---|
| `Farm` | `Node2D` + `farm_map.gd` | Map manager: interactions, objectives, wiring |
| `Ground` | `TileMapLayer` | Terrain, paths, tilled soil and water (`game_resources/tilesets/terrains.tres`) |
| `World` | `Node2D`, y-sorted | Y-sorted props, plots, NPCs, animals, animated trees |
| `World/Fences` | `TileMapLayer` | Pens, pastures, field fences (`game_resources/tilesets/fences.tres`) |
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

- Start: money carried from Map 1 (**30 G** minus 5 G per failure event, minimum 15 G),
  day 1, seeds `corn ×2, pumpkin ×1, tomato ×2, carrot ×1`
- Day length: **60 s**; prices reroll each day by about **±25 %** around the base price
- Selling pays the current daily price; buying a seed costs its `seed_price`
- The `gourde` wallet, its starting balance and the `OBJETS & PROPRIÉTÉS` offers come from
  `game_resources/economy/economy.tres`; see [ECONOMY.md](../ECONOMY.md)
- `FarmMap.economy_generation` selects the generation before the HUD builds its rows; it is
  `cultivateur` on this map

| Crop | Label | Seed | Base price | Growth |
|---|---|---|---|---|
| `corn` | Maïs | 4 G | 10 G | 18 s |
| `pumpkin` | Potiron | 6 G | 16 G | 24 s |
| `tomato` | Tomate | 4 G | 9 G | 16 s |
| `carrot` | Carotte | 3 G | 7 G | 12 s |

`CropPlot` states: `EMPTY → TILLED → GROWING → READY → TILLED` after harvest. Sprout and
mid-stage textures swap automatically while growing.

### Generation tasks

| ID | Success | Failure |
|---|---|---|
| `prepare_plot` | Prepare a plot | — |
| `plant_seed` | Plant a seed | — |
| `harvest_crop` | Harvest a crop | — |
| `sell_produce` | Sell produce | — |
| `earn_100` | Reach 100 G before day 6 | Day 6 starts first |

A farmer with no seed, no produce, nothing in the ground and not enough money for the
cheapest seed is *destitute* (`FarmMap.is_destitute()`): the objective points at the
Marchande, who advances one carrot seed (`RELIEF_CROP`) when talked to. Without it the
remaining tasks could never be resolved and the road exit would stay closed.

The five tasks replace the old local objective booleans and are stored in `Campaign`.
`earn_100` is permanent once the day-6 deadline passes: the farm can still be left, but the
generation result is partial and the heir receives a smaller heritage.

The road exit is east of the market hamlet, at `(4360, 3168)`. It is gated on all five
tasks being resolved and shows the generation result before the chapter fade to
[Map 3](MAP3.md).

### Controls

| Action | Keys | Effect |
|---|---|---|
| `move_*` | WASD / arrows | Move |
| `interact` | E | Prepare, plant, harvest, open market, talk |
| `select_seed_1..4` | 1–4 | Choose seed (also in the inventory popup) |
| `toggle_inventory` | I | Inventory popup (pause) |
| `toggle_prices` | P | Show/hide market prices |
| `toggle_tasks` | T / Select | Open the generation task list |
| `pause` | Esc / Start | Open the pause menu |
| `ui_cancel` | Esc / B | Close the open overlay |

The HUD shows money and day (top-left), the task list and current objective (top-centre),
interaction prompts and notifications. The market overlay pauses the game and lists crop
sales, seeds and the generation's **OBJETS & PROPRIÉTÉS** offers (a barn, an extra field slot
and a hoe by default). The inventory and price overlays never duplicate each other. The pause
menu only opens when no HUD overlay owns the pause, so `Esc` closes the market or inventory
first.

See [docs/UI.md](../UI.md) for the title screen, options and save format.

## Living world

### Trees

446 trees are `AnimatedSprite2D` using the pack's 3-frame shake strips.

- 442 forest trees (154 colliding tree props, 118 `DenseTree_`, 170 `DenseCanopy_`)
- 4 fruit trees (apple, orange, peach, lemon)
- Dense-canopy trees have no collision; all other trees keep a per-tree
  `RectangleShape2D` sized from the original prop
- Shared `SpriteFrames` live in `game_resources/animations/`; `scripts/world/tree_sway.gd`
  randomises start frame and speed per tree so the canopy is not synchronised

### Animals

| Nodes | Sheet | Frame cell | Speed |
|---|---|---|---|
| `CowWhite`, `CowBlack`, `CowCaramel` | `Cow_Big_White/Black`, `Cow_Caramel` | 144 × 144 | 15 px/s |
| `ChickenWhite`, `ChickenBrown`, `ChickenGolden` | `Chicken_*` | 48 × 48 | 30 px/s |
| `RoosterBrown` | `Rooster_Brown` | 48 × 96 | 27 px/s |
| `ChickA`, `ChickB` | `Chick` | 48 × 48 | 36 px/s |

`scripts/farm/animals/animal.gd` builds four walk and four graze animations from each sheet
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
  `scripts/world/crop_sway.gd`
- `CropPlot` sprites swap growth textures; the gameplay plots do not sway
- 10 ambient leaf emitters (green, yellow, brown 24-frame loops) drift through the forest;
  scene `scenes/world/ambient_leaves.tscn`, frames `game_resources/animations/Leaves_*.tres`

### Cyclone

`World/Cyclone` is the shared storm effect (`scenes/world/fx/cyclone.tscn`). On the farm it
moves on a schedule:

- every third farm day (60 s per day, so every **3 minutes**) it crosses the farm along a
  **6-leg path** for **30 s** (`cyclone_legs = 6`, `cyclone_leg_time = 5`), at **200 px/s**
  (`cyclone_speed`);
- at every leg the heading turns by up to **60°** (`cyclone_turn_deg`), so the storm visibly
  changes direction; when a leg would leave the playable area it bounces off the 300 px
  margin;
- the day before, `GameState.announce` warns the player to harvest ripe crops;
- after each leg, every `READY` crop within 220 px of that **segment** is destroyed: the
  plot returns to `TILLED`, the harvest is lost, and the HUD reports the total count once
  the crossing ends. Growing crops are left alone.

`CropPlot.destroy_crop()` refuses anything that is not `READY`. Tests live in
`tests/unit/test_farm_cyclone.gd`.

> **À vérifier en jeu** — les valeurs actuelles sont un point de départ, pas un
> équilibrage validé : 30 s de traversée (`cyclone_legs = 6` × `cyclone_leg_time = 5`)
> et 200 px/s (`cyclone_speed`). Il faut les tester manette en main : trop lent, le
> joueur a tout le temps de récolter et la menace disparaît ; trop rapide, le cyclone
> devient illisible. Les trois réglages à ajuster sont `cyclone_legs`,
> `cyclone_leg_time` et `cyclone_speed`, plus `cyclone_turn_deg` pour l'ampleur des
> virages.

### Zone de voyage

Aujourd'hui le cyclone rebondit sur une marge de 300 px autour de **toute** la map
(`FARM_SIZE`), donc il peut traverser la maison, le spawn ou le marché, où il n'a
aucun intérêt de gameplay. Il faudrait sans doute lui donner une **zone de voyage
dédiée** :

- un `Rect2` exporté (`cyclone_zone`) centré sur les champs et le verger ;
- tirage du point de départ et des caps à l'intérieur de ce rectangle, pas de
  `FARM_SIZE` ;
- rebond sur les bords de la zone au lieu des bords de la map.

Les 8 parcelles sont groupées entre x = 1560–1704 et y = 1728–1776 ; une zone du type
`Rect2(1150, 1300, 1350, 900)` laisserait le cyclone balayer le potager et ses abords
sans entrer dans la cour. Coordonnées à confirmer visuellement.

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
  `game_resources/animations/`, and instance it with `tree_sway.gd`.

## Files

| Path | Purpose |
|---|---|
| `scripts/systems/game_state.gd` | Autoload: money, day, crops, seeds, produce, prices, signals |
| `scripts/systems/economy/economy.gd` | Autoload: per-generation wallets, offers and ownership |
| `game_resources/economy/economy.tres` | Currency, generation and property offer data |
| `scripts/farm/crop_plot.gd` / `scenes/farm/crop_plot.tscn` | Plot states, growth, harvest |
| `scripts/farm/market_stand.gd` / `scenes/farm/market_stand.tscn` | Market interaction point |
| `scripts/farm/npc.gd` / `scenes/farm/npc.tscn` | Dialogue, patrol and player-facing |
| `scripts/farm/farm_hud.gd` / `scenes/farm/farm_hud.tscn` | HUD, market, inventory, prices |
| `scripts/farm/farm_map.gd` | Manager, campaign task wiring and road exit |
| `scripts/farm/animals/animal.gd` / `scenes/farm/animals/animal.tscn` | Animal frames and roaming AI |
| `scripts/systems/campaign/campaign_state.gd` | Generation tasks, failures, results and carry-over |
| `scenes/ui/tasks/task_list.tscn` / `scripts/ui/tasks/task_list.gd` | Task list UI |
| `scenes/ui/tasks/generation_result.tscn` / `scripts/ui/tasks/generation_result.gd` | Generation result overlay |
| `scripts/world/tree_sway.gd`, `scripts/world/crop_sway.gd`, `scripts/world/ambient_leaves.gd` / `scenes/world/ambient_leaves.tscn` | World animation helpers |
| `game_resources/animations/` | Shared tree and leaf `SpriteFrames` |
| `scenes/world/world_object.tscn` | Reusable prop: texture, bottom-centred collision |
| `themes/salazie/salazie_theme.tres` | Shared UI-pack theme for menus and HUD |
| `scenes/ui/menus/` | Title screen, options, pause, controls, credits, confirmations |
| `scenes/ui/hud/hud.tscn` / `scripts/ui/hud/hud.gd` | Survival bars and UI-pack icons |
| `scripts/systems/save/`, `scripts/systems/settings/`, `scripts/systems/scene_router.gd` | Save, settings and scene lifecycle |

## Verification

```bash
GODOT_BIN=/Applications/Godot.app/Contents/MacOS/Godot   # macOS; `godot` on Linux/CI
"$GODOT_BIN" --headless --import
"$GODOT_BIN" --headless --audio-driver Dummy --quit-after 30 --scene res://scenes/maps/farm.tscn
python3 .claude/skills/godot-nodes-scenes/scripts/check_godot_project.py . --json
```

Tests: `tests/unit/test_player.gd` and `tests/unit/test_farm_life.gd` (animal animations,
roam bounds, tree and leaf frames, fruit slice geometry, NPC facing), plus the campaign,
map, menu, settings, save and UI-asset suites in `tests/unit/`.

## Known limits

- One autosave slot managed by `SaveGame`; state still resets if the save file is deleted.
- Buildings and slots bought at the market are recorded as owned assets only; they do not
  appear in the world or unlock new plots yet.
- Animals are decorative; they do not produce eggs or milk and do not react to the player.
- Fruit trees and field crops are visual only; only the 8 `CropPlot`s are harvestable.
- The day-6 prosperity deadline is the only failure source on this map.
- The cyclone only destroys ripe crops; it never fails a task and the destroyed harvest is
  not counted in the generation result.
- Cyclone duration (30 s), speed (200 px/s) and turning are unverified tuning values, and
  the storm still roams the whole farm instead of a dedicated travel zone.
- No audio assets yet.
