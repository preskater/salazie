# Menus, settings and save

Technical reference for the title screen, options, pause overlay and the single-slot save.
Narrative text lives in [LORE.md](../LORE.md); this note records what is built and where.

- Boot scene: `game/ui/menus/main_menu.tscn`
- Game scene opened by **Nouvelle partie**: `game/world/maps/Maroon.tscn`
- **Continuer** opens the generation stored in `Campaign.current_map`
- Pause overlay: autoload `game/ui/menus/pause_menu.tscn`
- Save file: `user://savegame.json` (plus `savegame.json.bak`)
- Settings file: `user://settings.cfg`
- UI art: **only** `assets/ui_48x48` (LimeZu Modern UI, Style 1) for menus and HUD

## Screen flow

```text
main_menu.tscn
  Home ── Nouvelle partie ──> Maroon.tscn (Map 1)
    │    └─ (existing save) ─> Confirm ─> Maroon.tscn
    ├── Continuer ───────────> saved generation
    ├── Options ─────────────> Settings
    ├── Crédits ─────────────> Credits
    └── Quitter ─────────────> Confirm ─> quit

Maroon.tscn
  Refuge exit ──────────────> Farm.tscn (Map 2)

Farm.tscn
  Road exit ────────────────> Heir.tscn (Map 3)

Heir.tscn
  Town hall ────────────────> EndingScreen

Pause (Échap / Start)
  ├── Reprendre
  ├── Options ─────────────> Settings
  ├── Commandes ───────────> Controls
  ├── Sauvegarder
  ├── Menu principal ──────> Confirm ─> main_menu.tscn
  └── Quitter ─────────────> Confirm ─> quit
```

Each menu uses `game/ui/menus/menu_stack.gd`: one screen is visible at a time, the
first focusable control receives focus, and returning restores the focus of the previous
screen. Hidden screens cannot receive focus or mouse input.

## UI direction

All menu and HUD textures come from `assets/ui_48x48`. The shared theme is
`game/ui/theme/salazie_theme.tres` and is also the project-wide `gui/theme/custom`.

| Element | Source |
|---|---|
| Panel frame | `Modern_UI_Style_1.png`, `(24, 24, 96, 93)`, 30 px nine-patch margins |
| Compact HUD panel | Button frame `(36, 753, 72, 75)`, `HudPanel` type variation |
| Button normal / hover / focus | `(36, 753, 72, 75)` and `(180, 753, 72, 75)` |
| Slider track / fill | `(30, 432, 84, 48)` and `(1008, 447, 51, 24)` |
| Progress bar track / fill | `(1008, 399, 48, 24)` and `(1008, 1023, 51, 24)` |
| Settings icons | `game/ui/theme/icons/*.tres` (`AtlasTexture`) |
| Controls illustration | `Modern_UI_Gamepad.png`, `(444, 39, 648, 435)` at 1/3 scale |

Text is dark brown on beige panels; titles and labels over the dark background use
cream/gold overrides. Buttons carry 48×48 grid-tile icons scaled to 24 px by the theme.

The title screen uses three `family_portrait.tscn` instances, each stacking four 96×96
portrait-generator frames cropped to `(16, 12, 56, 56)` and displayed at 3×:

| Generation | Skin | Eyes | Hair | Accessory |
|---|---|---|---|---|
| Le marron | `PG_Skin_48x48_1` | `PG_Eyes_48x48_01` | `PG_Hairstyle_05_48x48_4` | — |
| Le cultivateur | `PG_Skin_48x48_7` | `PG_Eyes_48x48_02` | `PG_Hairstyle_03_48x48_2` | `PG_Accessory_13_Beard_48x48_1` |
| L’héritier | `PG_Skin_48x48_2` | `PG_Eyes_48x48_06` | `PG_Hairstyle_02_48x48_1` | `PG_Accessory_15_Glasses_48x48_1` |

No farm texture is referenced by a menu or HUD scene; `tests/unit/test_ui_assets.gd`
enforces this. The engine default font is kept because the UI pack does not ship a font.

## Task list and generation result

`game/ui/tasks/task_list.tscn` is instanced by every map. It reads `Campaign` and never
polls:

- compact row: `Tâches — X faites · Y échouées · Z en cours`;
- expanded rows: `✓` done, `✗` failed with the last reason and `[Réessayer]` when the task
  can be retried, `○` pending with `(progress/target)` for multi-step tasks;
- result footer once the map is resolved: rank and next-generation label;
- `T` or gamepad Select toggles the panel.

`game/ui/tasks/generation_result.tscn` is the modal shown by a `MapExit` or the town hall.
It pauses the tree, lists every task and its failure count, and resumes when **Continuer**
is pressed.

## Autoloads

| Autoload | Script | Responsibility |
|---|---|---|
| `Settings` | `game/systems/settings/settings.gd` | Load/apply/save audio, window and VSync settings |
| `DayNightCycle` | `game/world/DayNightCycle.tscn` | Day/night phases and tint |
| `SceneTransition` | `game/ui/SceneTransition.tscn` | Chapter fade used by map exits |
| `Economy` | `game/systems/economy/economy.gd` | Per-generation wallets, offers, trading, ownership |
| `GameState` | `game/farm/game_state.gd` | Farm economy, day timer, `playing`/`farm_active`, serialisation |
| `Campaign` | `game/systems/campaign/campaign_state.gd` | Generation tasks, failures, results, choices and carry-over |
| `SaveGame` | `game/systems/save/save_game.gd` | Single-slot JSON save, autosave, `.bak` fallback |
| `SceneRouter` | `game/systems/scene_router.gd` | New game, continue, generation transitions, menu/quit, fade |
| `PauseMenu` | `game/ui/menus/pause_menu.tscn` | Global pause overlay, process mode `ALWAYS` |

Autoload order matters: `Settings`, `DayNightCycle`, `SceneTransition`, `Economy`,
`GameState`, `Campaign`, `SaveGame`, `SceneRouter`, `PauseMenu`.

`SceneRouter` stops and hides the day/night tint on the title screen, resets the cycle when a
game starts or continues, and re-enables it in gameplay. Map exits keep using
`SceneTransition` for their chapter fade; the pause menu is blocked while a chapter fade is
running. Day/night remains decorative: the next generation is unlocked by the task list.

## Settings

`Settings` stores:

| Section | Key | Type | Default |
|---|---|---|---|
| `audio` | `master` | float 0..1 | 0.8 |
| `audio` | `music` | float 0..1 | 0.7 |
| `audio` | `sfx` | float 0..1 | 0.8 |
| `display` | `window_mode` | int (`0` windowed, `1` fullscreen) | `0` |
| `display` | `resolution` | `[width, height]` | `[1280, 720]` |
| `display` | `vsync` | bool | `true` |

Audio is applied to the `Master`, `Music` and `SFX` buses in `default_bus_layout.tres`.
There are no audio assets yet, so the sliders are wired for future music and sound effects.
Display changes are skipped when `DisplayServer.get_name() == "headless"`, which keeps
CI and the gdUnit4 runner safe.

The options screen applies changes immediately and saves after a short debounce, on
**Retour**, and when leaving the screen with `ui_cancel`. `Réinitialiser` restores the
defaults above.

## Save format

Only plain data is stored. The farm scene rebuilds itself from `GameState` and the campaign
rebuilds task states from `Campaign`; no nodes, resources or node paths are serialised.
Save version 2 adds the per-generation economy payload documented in [ECONOMY.md](ECONOMY.md)
and the campaign payload.

```json
{
  "version": 2,
  "saved_at": "2026-11-21T10:30:00",
  "money": 84,
  "day": 3,
  "day_time": 12.5,
  "selected_seed": "corn",
  "seeds": {"corn": 2, "pumpkin": 1, "tomato": 2, "carrot": 1},
  "produce": {"corn": 1, "pumpkin": 0, "tomato": 3, "carrot": 0},
  "prices": {"corn": 10, "pumpkin": 16, "tomato": 9, "carrot": 7},
  "previous_prices": {"corn": 10, "pumpkin": 16, "tomato": 9, "carrot": 7},
  "economy": {
    "generation": "cultivateur",
    "enabled": true,
    "wallets": {"gourde": 84},
    "owned": {"barn": 1},
    "stock": {"building_barn": 0, "slot_field": 2, "item_hoe": 1}
  },
  "campaign": {
    "current_map": 2,
    "tasks": {
      "1": {
        "find_food": {"status": 1, "progress": 3, "attempts": 1, "failures": []},
        "cross_patrol": {
          "status": 1,
          "progress": 1,
          "attempts": 2,
          "failures": [{"reason": "Repéré par une patrouille", "at": "2026-11-21T10:12:00"}]
        }
      }
    },
    "results": {},
    "choices": {"map3_plan": "forest"},
    "heritage": 0,
    "finished": false
  }
}
```

Task statuses are `0` pending, `1` done and `2` failed. A retry returns the status to `0`
but keeps the failure list.

- Writes are atomic: `savegame.json.tmp` → `savegame.json`, with the previous file rotated
  to `savegame.json.bak`.
- Loading tries the primary file, then the backup. Invalid JSON, missing fields, or a newer
  `version` are refused without mutating the current state.
- Version 1 payloads without the `economy` block still load; `money` is applied to the
  active generation's primary currency.
- JSON numbers load as floats; `GameState.to_dict()` / `from_dict()` and
  `Campaign.to_dict()` / `from_dict()` convert them back to integers.
- Autosave triggers: day change (`GameState.day_advanced`), task status change, map
  resolution, opening the pause menu, pressing **Sauvegarder**, returning to the main menu,
  and closing the window while playing.
- **Nouvelle partie** resets both the farm and the campaign, then saves immediately. An
  existing save is replaced only after the confirmation panel.
- Version 1 saves migrate to version 2: the farm is kept, `current_map` becomes 2, Map 1 is
  treated as completed, and `earn_100` is marked done when the old purse had 100 G.
- The **Continuer** line shows the generation, its title, the day and the purse.

## Pause and HUD interaction

`PauseMenu` opens only when `SceneRouter.is_gameplay` is true and the tree is not already
paused. `Échap` / Start is the `pause` action in `project.godot`.

The market and inventory overlays already pause the tree through `FarmHUD`. To keep the two
systems apart:

- `PauseMenu` does not open while `get_tree().paused` is true (market/inventory open).
- `FarmHUD._unhandled_input()` ignores `I` and `P` when the tree is paused by another system.
- `Échap` closes the market/inventory first; once nothing else owns the pause, it opens the
  pause menu.

### HUD styling

- `FarmHUD` small panels (money, objective, prompt, dialogue, prices) use the `HudPanel`
  type variation; the market and inventory use the large panel frame.
- Money text uses `GameState.format_wallets()` so every enabled wallet follows the active
  generation's currencies. The market adds an **OBJETS & PROPRIÉTÉS** section for `ITEM`,
  `BUILDING` and `SLOT` offers; see [ECONOMY.md](ECONOMY.md).
- `farm_hud.gd` keeps the market/inventory text colours in a small palette
  (`TEXT_DARK`, `TEXT_MUTED`, `TEXT_ACCENT`, `POSITIVE`, `NEGATIVE`) instead of the old
  cream-on-dark values.
- Labels displayed directly over the world (notification, controls hint) keep a light
  colour with an outline.
- The survival HUD uses the meat and blue-potion icons plus the pack progress-bar track;
  `hud.gd` tints the beige fill orange for food, blue for water and red below 25%.

## Controls

| Action | Keys |
|---|---|
| Move | WASD / arrow keys |
| Interact | `E` |
| Select seed | `1`–`4` |
| Inventory | `I` |
| Market prices | `P` |
| Task list | `T` / gamepad Select |
| Pause | `Échap` / gamepad Start |
| Menu navigation | arrows / D-pad + Enter / A |
| Back / close | `Échap` / B |

Rebinding is not implemented; `Commandes` is a read-only screen.

## Files

| Path | Purpose |
|---|---|
| `game/ui/menus/main_menu.tscn` / `.gd` | Title screen and game entry |
| `game/ui/menus/pause_menu.tscn` / `.gd` | Global pause overlay |
| `game/ui/menus/menu_stack.gd` | Screen stack, focus, back navigation |
| `game/ui/menus/screens/settings_screen.tscn` / `.gd` | Audio and display options |
| `game/ui/menus/screens/controls_screen.tscn` / `.gd` | Read-only controls reference |
| `game/ui/menus/screens/credits_screen.tscn` / `.gd` | Credits |
| `game/ui/menus/screens/confirm_screen.tscn` / `.gd` | Confirmation panel |
| `game/ui/menus/family_portrait.tscn` / `.gd` | Four-layer portrait from the portrait generator |
| `game/ui/theme/salazie_theme.tres` | Shared UI-pack theme (menus + HUD, project default) |
| `game/ui/theme/icons/*.tres` | `AtlasTexture` icons cropped from the UI pack |
| `game/ui/hud/hud.tscn` / `.gd` | Survival bars and pack icons |
| `game/farm/farm_hud.tscn` / `.gd` | Farm HUD, market and inventory |
| `game/systems/campaign/campaign_state.gd` | Generation tasks, failures, results and choices |
| `game/ui/tasks/task_list.tscn` / `.gd` | Per-generation task list |
| `game/ui/tasks/generation_result.tscn` / `.gd` | Generation result overlay |
| `game/world/maps/Maroon.tscn` + `game/maroon/` | Map 1 |
| `game/world/maps/Heir.tscn` + `game/heir/` | Map 3 |
| `game/ui/dialogue/dialogue_box.tscn` / `.gd` | Map 3 NPC/site dialogue |
| `game/ui/decision/decision_panel.tscn` / `.gd` | Map 3 plan decision |
| `game/ui/ending/ending_screen.tscn` / `.gd` | Choice-driven epilogue |
| `game/systems/settings/settings.gd` | Persistent settings |
| `game/systems/economy/economy.gd` | Per-generation wallets, offers and ownership |
| `game/systems/economy/config/economy.tres` | Shipped currency, generation and offer data |
| `game/systems/save/save_game.gd` | Save/load and autosave |
| `game/systems/scene_router.gd` | Scene transitions and game lifecycle |
| `default_bus_layout.tres` | Master / Music / SFX buses |
| `game/farm/game_state.gd` | `reset()`, `to_dict()`, `from_dict()`, `playing` |
| `game/farm/farm_hud.gd` | Input guard while another system owns the pause |

## Tests

```bash
GODOT_BIN=/Applications/Godot.app/Contents/MacOS/Godot   # macOS; `godot` on Linux/CI
"$GODOT_BIN" --headless --import
GODOT_BIN="$GODOT_BIN" bash addons/gdUnit4/runtest.sh \
  --headless --audio-driver Dummy --ignoreHeadlessMode \
  --continue --add res://tests
"$GODOT_BIN" --headless --quit-after 5 --audio-driver Dummy
"$GODOT_BIN" --headless --audio-driver Dummy --quit-after 30 \
  --scene res://game/world/maps/Farm.tscn
```

Focused suites:

- `tests/unit/test_menus.gd` — main menu, continue state, settings navigation, pause, HUD guard.
- `tests/unit/test_menu_layout.gd` — off-screen controls and initial focus at 1280×720,
  1536×648, 1152×864 and 2560×1080.
- `tests/unit/test_settings.gd` — defaults, round-trip, clamping, slider wiring, buses.
- `tests/unit/test_save_game.gd` — round-trip, `.bak` fallback, newer version refusal,
  economy round-trip and version 1 migration.
- `tests/unit/test_economy.gd` — generation currencies, disabled generations, buy/sell,
  trading, ownership and state round-trip.
- `tests/unit/test_game_state_reset.gd` — reset, signals, day timer, JSON floats.
- `tests/unit/test_campaign_state.gd` — task statuses, failures, retries, results, carry-over.
- `tests/unit/test_task_list.gd` — pending/done/failed rows and result text.
- `tests/unit/test_generation_result.gd` — result overlay and pause handling.
- `tests/unit/test_maroon_map.gd` — survival, forage, hiding, checkpoints and refuge gate.
- `tests/unit/test_heir_map.gd` — NPCs, fragile sites, decision and plans.
- `tests/unit/test_ending.gd` — choice-driven epilogue.
- `tests/unit/test_ui_assets.gd` — UI-pack-only texture references, portrait layers, trio
  wiring, survival HUD icons and bars.

Current status: **155/155 gdUnit4 tests pass**.

## Known limits

- One save slot; no slot picker or cloud save.
- Building and slot ownership is recorded by the economy but does not build anything in the
  world yet.
- No audio assets yet; music/SFX volumes are ready but silent.
- No key rebinding and no language selector.
- Display options are ignored in headless mode and may behave differently in a browser.
- The title screen uses the engine default font because the UI pack has no font asset; there
  is no dedicated logo.
- Menu/HUD art is limited to `assets/ui_48x48`; the game world keeps the farm packs.
- Map 1 and Map 3 build their props at runtime from the existing packs, so their `.tscn`
  files are thin and most layout changes live in `maroon_map.gd` / `heir_map.gd`.
