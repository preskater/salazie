# Economy

Technical reference for currencies, market offers and asset ownership. Narrative intent lives
in [LORE.md](../LORE.md); this note records what is built and where.

- Autoload: `game/systems/economy/economy.gd` (`Economy`)
- Shipped config: `game/systems/economy/config/economy.tres`
- Data resources: `game/systems/economy/economy_config.gd`,
  `economy_generation.gd`, `economy_currency.gd`, `economy_offer.gd`
- Farm integration: `game/farm/game_state.gd`, `game/farm/farm_hud.gd`
- Save integration: `game/systems/save/save_game.gd` (save version 2)

`Economy` is the single wallet store. `GameState.money` is a facade over the active
generation's primary currency, so existing farm code keeps using `money`, `add_money()` and
`spend_money()` without a second ledger.

## Configuration model

```text
EconomyConfig
├── default_generation: StringName
└── generations: Array[EconomyGeneration]
    ├── id, label, enabled
    ├── allow_buy, allow_sell, allow_trade
    ├── currencies: Array[EconomyCurrency]
    │   ├── id, label, symbol, icon
    │   ├── starting_balance
    │   └── enabled
    └── offers: Array[EconomyOffer]
        ├── id, label, description
        ├── kind: ITEM | BUILDING | SLOT
        ├── currency_id, price
        ├── sell_price (-1 = not sellable)
        ├── stock (-1 = unlimited)
        └── grant_id (ownership key, defaults to the offer id)
```

All values are `@export` fields, so the `.tres` file is editable in the inspector. The
primary currency is the first enabled currency of the generation.

### Shipped generations

| Generation | `enabled` | Currencies | Market |
|---|---|---|---|
| `marron` | `false` | — | Economy disabled; survival map |
| `cultivateur` | `true` | `gourde` (G), start 30 | Barn, field slot, hoe |
| `heritier` | `true` | `euro` (€), start 120; `credit_vert` (CV), start 5 | Wetland, refuge slot, seedling kit |

`default_generation` is `cultivateur`, matching the first playable map.

### Disabling the economy

A generation with `enabled = false` keeps its data but refuses every transaction:
`buy()`, `sell()`, `trade()`, `add_currency()`, `spend_currency()` and `set_balance()` all
return `false`/`0`, and their signals are not emitted except `transaction_failed`. Market
buttons are greyed out and `GameState.sell()` keeps the produce in the basket.

`Economy.set_enabled(false)` disables the active generation at runtime; `set_enabled(true)`
only works when the generation allows it. A disabled generation can never be re-enabled at
runtime.

## API

### Selection and state

| Method | Effect |
|---|---|
| `apply_config(config, generation_id)` | Use a config built in code; selects a generation |
| `reload_config(path)` | Load a `.tres` and select its `default_generation` |
| `select_generation(id, reset_state)` | Activate a generation; resets wallets, stock and ownership |
| `reset()` | Reset the active generation to its configured starting state |
| `set_enabled(value)` | Runtime toggle, bounded by `generation.enabled` |
| `is_enabled()` | `true` only when the generation and runtime toggle allow transactions |
| `generation()`, `current_generation_id()` | Active generation data and id |
| `to_dict()`, `from_dict(data)`, `can_restore(data)` | Save payloads, plain data only |

### Wallets

| Method | Effect |
|---|---|
| `balance(currency_id)` | Current amount, `0` for unknown currencies |
| `can_afford(currency_id, amount)` | Enabled generation and enough funds |
| `add_currency(currency_id, amount)` | Credit a known, enabled currency |
| `spend_currency(currency_id, amount)` | Debit only when the balance covers it |
| `set_balance(currency_id, amount)` | Absolute value, clamped to `>= 0` |
| `format_amount(currency_id, amount)` | `"12 G"` / `"80 €"` display text |
| `currency_symbol(id)`, `currency_label(id)` | Display helpers |

### Offers and ownership

| Method | Effect |
|---|---|
| `offers(kind)` | Offers, optionally filtered by `ITEM`, `BUILDING` or `SLOT` |
| `offer(id)`, `offer_stock(id)` | Offer data and remaining stock (`-1` unlimited) |
| `can_buy(id, quantity)`, `buy(id, quantity)` | Check then purchase; stock and funds are rechecked |
| `can_sell(id, quantity)`, `sell(id, quantity)` | Sell owned units; returns the amount earned |
| `owned_count(asset_id)` | Units owned under an offer's `grant_id` |

Buying debits the offer currency, decrements limited stock, grants `quantity` ownership
units and emits `offer_purchased`. Selling does the reverse and restocks limited offers.

Ownership is generic: a building and a slot are both an `asset_id` with a count. Gameplay
systems subscribe to `offer_purchased`, `offer_sold` and `ownership_changed` to apply their
own effects; the economy never instantiates scenes.

### Trading

`trade(give, receive)` is an atomic barter between two bundles:

```gdscript
Economy.trade(
    {"currency": &"gourde", "amount": 20},
    {"asset": &"plot", "amount": 2})
```

Each side is `{"currency": id, "amount": n}` or `{"asset": id, "amount": n}`. Both sides are
validated before anything changes, so a failed trade leaves wallets, ownership and stock
untouched. `generation.allow_trade` gates the operation.

### Signals

| Signal | Payload |
|---|---|
| `generation_changed` | `generation_id` |
| `economy_enabled_changed` | `enabled` |
| `balance_changed` | `currency_id`, `amount` |
| `ownership_changed` | `asset_id`, `amount` |
| `stock_changed` | `offer_id`, `remaining` |
| `offer_purchased` | `offer`, `quantity` |
| `offer_sold` | `offer`, `quantity`, `total` |
| `trade_completed` | `give`, `receive` |
| `transaction_failed` | `reason` |

Failure reasons: `economy_disabled`, `buy_disabled`, `sell_disabled`, `trade_disabled`,
`unknown_offer`, `unknown_currency`, `invalid_quantity`, `insufficient_funds`,
`out_of_stock`, `not_owned`, `not_sellable`, `invalid_trade_entry`, `empty_trade`.

## Farm integration

- `GameState.money` reads and writes `Economy.balance(currency_id())`.
- `currency_id()` is the active generation's primary currency; `format_money()` and
  `currency_label()` use the same definition. `format_wallets()` lists every enabled wallet
  (`"120 € · 5 CV"`), and the HUD money label uses it.
- `GameState.reset()` selects `GameState.FARM_GENERATION` (`cultivateur`) before resetting
  the farm wallet, so a new game never inherits a later generation's currency.
- `GameState.add_money()` and `spend_money()` delegate to `add_currency()` and
  `spend_currency()`. `GameState.sell()` refuses to move produce when the economy is off.
- `Economy.balance_changed` is forwarded as `GameState.money_changed`, so the HUD updates
  after a generic building/slot purchase.
- `FarmHUD` shows every `ITEM`, `BUILDING` and `SLOT` offer under **OBJETS & PROPRIÉTÉS**
  in the market sell and buy columns. Crop seeds and produce keep their dynamic market in
  the same overlay.

To use another generation on a map without `GameState`:

```gdscript
Economy.select_generation(&"heritier")
```

`FarmMap.economy_generation` selects its generation in `_enter_tree()`, before the HUD
builds its offer rows. `GameState.reset()` deliberately returns to
`GameState.FARM_GENERATION` because it restarts the farm map.

## Save format

`GameState.to_dict()` embeds `Economy.to_dict()`; save version 2 stores:

```json
"economy": {
  "generation": "cultivateur",
  "enabled": true,
  "wallets": {"gourde": 40},
  "owned": {"barn": 1},
  "stock": {"building_barn": 0, "slot_field": 2, "item_hoe": 1}
}
```

- Version 1 payloads without `economy` still load; the legacy `money` field is applied to
  the active generation's primary currency.
- `Economy.can_restore()` rejects a payload whose generation is missing from the config, or
  whose `wallets`, `owned` or `stock` entries are not dictionaries.
- JSON object keys become `String`; `from_dict()` converts them back to `StringName`.
- Unknown currencies are ignored and amounts are clamped to `>= 0`. Unknown offers are not
  restored in `stock`.

## Adding content

1. Add an `EconomyCurrency` and/or `EconomyOffer` to the generation in
   `game/systems/economy/config/economy.tres`.
2. Give buildings and slots a stable `grant_id`; this is the key used by future gameplay
   systems and by the save file.
3. Keep `sell_price` at `-1` for non-sellable offers.
4. Set `stock = -1` for unlimited items and a positive count for unique buildings.
5. Add a generation entry when a map introduces a new currency; set `enabled = false` for a
   generation without trade.

## Verification

```bash
GODOT_BIN=/Applications/Godot.app/Contents/MacOS/Godot   # macOS; `godot` on Linux/CI
"$GODOT_BIN" --headless --import
"$GODOT_BIN" --headless --path . \
  --script .github/skills/godot-gdscript/assets/check_scripts_compile.gd
GODOT_BIN="$GODOT_BIN" bash addons/gdUnit4/runtest.sh \
  --headless --audio-driver Dummy --ignoreHeadlessMode \
  --continue --add res://tests
```

Focused suites: `tests/unit/test_economy.gd` and `tests/unit/test_save_game.gd`.

## Known limits

- Building and slot ownership is recorded but has no gameplay effect yet; no scene is
  instantiated by the economy.
- The market UI lists only the current generation; changing generation while a HUD is alive
  requires reloading the map.
- Item ownership is a plain count; no inventory slot is reserved for generic `ITEM`
  offers yet. Crop seeds and produce keep the existing dynamic pricing in `GameState`.
