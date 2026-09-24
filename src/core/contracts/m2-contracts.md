# M2 Contracts — village and economy

Status: ratified by ORCHESTRATOR. Workers code against this document; raise
disagreements in their report (DONE T-#### | files | verify | issues).

Read first: AGENTS.md, docs/ARCHITECTURE.md, src/core/contracts/m1-contracts.md,
this doc. All M1 contracts stay in force (placed-object vocab, collision rule,
energy, quality, save/persist, feature module layout, self-registration via
src/features/auto-import.ts).

## 1. New sim actions (M2)

| type | payload | reduces in | notes |
|------|---------|------------|-------|
| `shop:buy` | `{ shopId, itemId, qty }` | shop sim (WORKER-2) | validate money + daily stock + item price; deduct money; add stacks to inventory; decrement daily stock; emit `shop:bought` `{ shopId, itemId, qty, gold }` |
| `shop:sell` | `{ shopId, itemId, qty }` | shop sim | only when shop.buys; remove stacks from inventory; add money = item.price.base * qty (quality ignored for sell); emit `shop:sold` `{ shopId, itemId, qty, gold }` |
| `shop:restock` | `{}` | shop sim | consumed at each day rollover: restore per-shop daily stock counters (state.extensions.shop.stock) to content shop.stock[].qty (infinite items stay infinite) |
| `forage:roll` | `{}` | farm sim | at each day rollover: clear old forage placed objects from the farm map, then spawn a fresh batch (see §3). Emits nothing. |
| `player:move` | unchanged | engine:sim | now ALSO applies warp in the same reducer: when the player steps onto a tile listed in mapDef.warps, position becomes { to.map, to.x, to.y } and `player:warped` `{ from: mapId, to: mapId }` is emitted once. Normal walking, energy and collision rules apply up to the edge. |

Time/sleep/shipping actions are unchanged from M1.

## 2. Shop state (WORKER-2)

- Content: content/shops/<id>.json, Zod-validated (core). ShopDef = { id, name,
  buys, stock: [{ itemId, price?, qty? }] }. `qty` omitted = infinite; `price`
  overrides item buy price.
- Runtime stock lives in `state.extensions.shop`:
  `{ stock: Record<shopId, Record<itemId, number>> }`. Initialized lazily;
  counters = content qty (or absent for infinite). `shop:restock` resets them
  each morning.
- Purchased item goes into the player's inventory via the inventory sim
  (merge into existing stack if canStack and x<=stack.qty; else first empty
  slot). Inventory full or insufficient funds -> no-op + emit `shop:denied`
  `{ reason: 'funds' | 'space' | 'stock', shopId, itemId }`.
- Selling removes qty from inventory (all stacks of that id, then empty), pays
  player.price.base*qty.

## 3. Foraging (WORKER-2)

- Farm map gains one new placed-object kind each morning: `forage` (id
  `forage:<itemId>`). Candidates: every item.json entry whose category is
  `forage`. WORKER-2 may add a small set (daffodil, wild-horseradish,
  leek, ...) to content/items.json tagged `season:<currentSeason>` — but the
  sim must pick from items whose `tags` include `season:<seasonIndex of today>`
  (index as number string, e.g. `season:0`) OR the item has no season tag.
- Spawn: rng.fork('forage') -> count = floor(3 + rng.next()*5), positions =
  random walkable, non-tilled, non-crop, non-blocked tiles of the farm map that
  are legend-tillable grass 'g'. Do not overwrite existing placed objects or
  planting rows.
- Pickup: `player:interact` with the scythe (or bare hand) on a `forage:<id>`
  tile adds the item (qty 1) and removes the object (emit `item:picked`).
  WORKER-2 adds the `forage` case to the farming/tool interaction reducer.

## 4. Weather & seasons (WORKER-2)

- Roll + forecast already exist (seed-weather). Add EFFECTS at each day
  rollover (in the same `time:tick` pass, before crop growth):
  - rain/storm: every `tilled` and `crop:*` placed object on the farm gets
    `watered: true`.
  - storm: for each mature or any crop, rng.fork('storm').next() < 0.10 ->
    destroy that crop (remove placed object, emit `crop:lost` `{ x, y, cropId,
    cause: 'storm' }`).
  - winter (seasonIndex === 3): tilling a tile is rejected — the soil is
    frozen. Till reducer emits `farming:blocked` `{ reason: 'frozen',
    tile }` and returns state unchanged.
  - season mismatch: any crop whose crop.seasons doesn't include the CURRENT
    season is removed (withered) that rollover (emit `crop:withered` with
    cause 'season').
- Emit `weather:changed` `{ weather, forecast }` after applying (existing).

## 5. End-of-day summary (WORKER-3)

- On `player:sleep` (and on forced pass-out), after shipping payout, WORKER-2
  emits `day:summary`:
  `{ dayCount, date: { year, seasonIndex, dayOfMonth }, weather, forecast,
    goldEarned, itemsSold: { itemId, qty, gold }[],
    cropsHarvested: { cropId, qty }[], collectedForage: { itemId, qty }[],
    xpEarned: { skill, amount }[] }`.
- WORKER-2 must accumulate the per-day counters in `state.player.stats`
  (JSON-safe keys) reset at each day rollover: e.g. `day:sold:<itemId>`,
  `day:harvest:<cropId>`, `day:forage:<itemId>`, `day:xp:<skill>`.
- WORKER-3 renders it as a "Day complete" dialog (DONE button = close;
  autosave already happened on sleep).

## 6. Village map + warps (WORKER-1)

- New map content/maps/village.json (authored by WORKER-1): a dock village.
  At minimum: walkable paths, buildable plots (legend `b` walkable+tillable for
  future farm plots -> use existing 'g' or add), water pier corners (legend
  `w`), a few houses (legend `h`), trees (`t`), fence. Village must contain a
  warp tile back to the farm.
- rustleaf-farm.json gains ONE warp: at the east road edge (e.g. x=31) to
  village near its west road edge. Validate warp targets exist (core rule).
- engine:sim reduce `player:move` for warps per §1. The view renders the
  destination map (map segment swap) on `player:warped`.
- Season/weather visuals: a per-season palette (tint colors for grass/water)
  applied on season rollover, a cheap weather layer (rain particle field for
  rain/storm, darker snow tint for snow), and a day/night tint driven by
  world.clock. Keep everything procedural and cheap (no new assets needed).

## 7. Tests (workers run only their lane)

- WORKER-1: extend view tests with pure helpers (warp resolution is a pure fn
  on mapDef+position — cover it) + a walk test that steps onto a warp.
- WORKER-2: tests/sim/shop.test.ts (buy/sell/restock/deny), tests/sim/weather2
  extensions in weather.test.ts (rain waters, storm loss, winter frozen till,
  season wither), forage in farming tests.
- WORKER-3: ui-kit structure test extended for the summary dialog; format
  helpers pure-tested (gold formatting reused).
- Gate = full `npm run check` by ORCHESTRATOR.

## 8. Do NOT touch

src/core/*, docs/*, package.json, vite/eslint configs, tests from other lanes,
src/features of other lanes. WORKER-1 owns content/maps/*. WORKER-2 owns
content/items.json + content/crops.json + content/shops/*. WORKER-3 owns
content/npcs.json and all UI strings (i18n). If any worker needs a schema or
core change, report it (goes through the orchestrator).