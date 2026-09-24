# M1 Contracts — playable season core loop

Status: ratified by ORCHESTRATOR. All three workers code against this document.
Anything they need changed here must be raised as an issue in their report.

## 1. Feature module layout (all lanes)

Each feature lives in src/features/<name>/ with an index.ts that imports and
registers its submodules:

```ts
// src/features/engine/index.ts  (example shape, WORKER-1)
import { registerFeature } from '../../core/registry';
import { defineFeature } from '../../core/feature';
import { engineView } from './view/EngineView';
import { engineSim } from './sim/EngineSim'; // WORKER-1 may own a small sim reducer for position/collision

registerFeature(defineFeature(engineView));
registerFeature(defineFeature(engineSim));
```

- `defineFeature({ id: '<name>:view', lane: 'world', view() { ... } })`
- `defineFeature({ id: '<name>:sim', lane: 'sim', setup(ctx) { ctx.store.registerReducer(...) }, onTick(ctx) {} })`
- `defineFeature({ id: '<name>:ui', lane: 'ui', ui() { return { mount(root) {}, dispose() {} } } })`

ids must match /^[a-z0-9][a-z0-9-]*:[a-z0-9-]+$/. No shared registry edits.

## 2. Shared sim data (in GameState, src/core/types.ts)

- `state.world`: calendar {year, seasonIndex, dayOfMonth}, clock {hour, minute},
  weather, forecast[3] (index 0 = tomorrow), dayCount, passedOut.
- `state.player`: name, farmName, position {mapId, x, y}, facing
  ('up'|'down'|'left'|'right'), energy/energyMax, health/healthMax, money,
  skills, inventory {slots: (ItemStack|null)[], capacity, selected}, stats.
- `state.maps[mapId]`: grid {tiles: string[] (row-major), width, height},
  placed: Record<"x,y", PlacedObject>, npcs, version.
- `state.progression.flags`, `state.quests`, `state.relationships`.

PlacedObject shape: `{ id, x, y, data?: Record<string, unknown> }`.

### Placed-object id vocabulary (M1)
- `tilled` — tilled soil. data: `{ watered: boolean }`
- `crop:<cropId>` — planted crop. data: `{ stage: number, watered: boolean,
  grownDays: number, fertilized?: boolean }`
- `shipping-bin` — one per farm. data: `{}` (items are stored in
  state.extensions.farming.shippingBox: ItemStack[]).
- `weed`, `branch`, `rock`, `stump` — farm debris; `rock`/`stump` block,
  `weed`/`branch` block too until cleared.

### Collision rule (single source of truth in sim; view copies for rendering)
A tile is walkable for the player iff:
  legend[code].walkable === true
  AND no placed object blocks. Blocking = id is NOT 'tilled' and does NOT start
  with 'crop:'. ('shipping-bin' and debris block.)

## 3. Sim actions (dispatch from Input/UI; reduce in sim modules)

| type | payload | notes |
|------|---------|-------|
| `player:move` | `{ dx: -1\|0\|1, dy: -1\|0\|1 }` | one tile step; validates collision; sets facing; drains energy over time; emits `player:moved` |
| `player:interact` | `{}` | uses the currently selected item on the tile in front (facing). Emits `tool:used`, `crop:planted`, `crop:harvested`, `item:picked`, `shipping:x` etc. |
| `player:select-slot` | `{ slot: number }` | hotbar selection |
| `inventory:move` | `{ from: number, to: number }` | drag/drop swap or merge |
| `player:sleep` | `{}` | only near home bed at night OR forced at 2am; advances to next day 06:00, runs day rollover (growth, shipping payout, weather), then `persist()` |
| `shipping:insert` | `{ slot: number }` | move stack from inventory into shipping box (extensions.farming.shippingBox) |

Time advancement stays core-owned (`time:tick`, 10 in-game minutes). Sim modules
listen to `day:rollover` (emitted when dayCount changes) and optionally register
their own reducers for `time:tick` that run AFTER core's.

## 4. Crop lifecycle (WORKER-2 owns; view reads)

- Growth stages: crop.days array (content/crops.json). stage advances one step
  per day rollover **only if watered that day**. Fully grown = stage >= sum of
  all but... definition: stage index into days[]; plant at stage 0; each watered
  day rollover advances stage by 1; harvest allowed when stage >= days.length.
  Wait/regrow: for regrow crops, after harvest reset stage to days.length-1.
- Unwatered for 2 consecutive days → withered (remove placed object, emit
  `crop:withered`).
- Watering: tile must be watered daily; watering comes from what the player
  equipped (watering can refills at water tiles: legend.water).
- Quality on harvest: seeded rng (ctx.rng) → 0 normal / 1 silver / 2 gold.
  Starter: quality ~5%/1% → balance in M8.

## 5. Energy

- Walking: drain 0.02 energy per tile (floored at 0).
- Tool use: hoe 6, watering-can 4, axe 8, pickaxe 8, scythe 2 (per use).
- energy<=0 → cannot use tools (emit `player:exhausted`), move still allowed
  but slow. Sleep restores to energyMax. Passing out at 2:00 AM handled by
  core clock.

## 6. Shipping + money

- Money is `state.player.money`. Shipping box in
  `state.extensions.farming.shippingBox` (ItemStack[]).
- On sleep: sell every stack at item price.base, add `quality` multiplier
  (silver x1.25, gold x1.5), clear box, emit `shipping:report`
  `{ sold: {itemId, qty, gold}[], total }`.

## 7. Weather (WORKER-2)

- At each day rollover, roll weather via `rng.fork('weather')` using
  seasonWeatherWeights (src/core/time.ts). forecast = [newWeather, old0, old1].
- Emit `weather:changed`.

## 8. Save/persist

- `ctx.persist()` writes current state to the active slot. Called by sim on
  sleep; UI may also call it. Autosave on sleep is a soft requirement of M1.
- `runtime.saveSlot` tells the active slot name.

## 9. View/conduit contract (WORKER-1)

- viewSim reads `store.state` each frame; subscribes to `state:changed` and
  `player:moved` to animate interpolation between tiles.
- Interaction preview: reads `state.player.position` + `facing`, highlights the
  tile ahead.
- Map rendering: `state.maps[mapId]` tiles (legend codes → procedural low-poly
  meshes via asset-ID layer), placed objects rendered by their id.
- Camera: angled top-down follow with smooth lerp + zoom + 90 deg snap
  (M1: follow + fixed angle acceptable, snap rotation in M7).
- Player render: simple low-poly humanoid; swap later behind asset layer.
- All Three.js only in view/ modules. Never import three in sim/.

## 10. UI contract (WORKER-3)

- HUD reads store on `state:changed`: date/season, clock, weather, money,
  energy+health bars, hotbar (selected slot ring), tooltip for hovered item.
- Actions dispatched via store.dispatch using the action table in section 3.
- UI kit: DOM/CSS overlay in src/features/ui-kit/ with reusable primitives:
  panel, button, slider, tooltip, dialog. Full i18n-ready string tables
  (src/features/ui-kit/i18n/en.ts) — all M1 strings live there.
- Input mapping module (src/features/input/): keyboard + mouse → dispatch.
  Keys are data (a mapping table) so remapping lands in M7 without refactor.

## 11. Content

- WORKER-2 may extend content/items.json + content/crops.json (their lane).
- WORKER-1 owns content/maps/* (they may add placed objects per map JSON).
- WORKER-3 owns content/npcs.json and all i18n/UI strings.
- No worker edits src/core, docs, config. Request changes via issues.

## 12. Tests (must pass; run only your lane's tests)

- WORKER-2: tests/sim/farming.test.ts, tests/sim/inventory.test.ts,
  tests/sim/shipping.test.ts, tests/sim/weather.test.ts (node, pure).
- WORKER-1: tests/view/view.test.ts — pure logic helpers only (no browser).
- WORKER-3: tests/ui-upgrade later in M7; for M1 validate via typecheck + a
  headless structural test (mount() against a JSDOM-free stub guarded by
  headless flag) — keep UI modules DOM-free at import time.
- Full suite runs via `npm run check` by ORCHESTRATOR only.