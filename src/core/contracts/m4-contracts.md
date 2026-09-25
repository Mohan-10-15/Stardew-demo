# M4 Contracts — life skills (fishing, animals, machines, cooking/buffs, skills panel)

Status: ORCHESTRATOR. Workers code against this document; raise disagreements in
their report (`DONE T-#### | files | verify | issues`). Fishing (section 1) is
RATIFIED (T-0402). Animals (section 2) is RATIFIED (T-0403). Machines
(section 3) and recipes/cooking buffs (section 4) are RATIFIED here (T-0404) —
code against them; the skills panel UI is still open (T-0405) and stays
briefed at the bottom of this document.

Read first: AGENTS.md, docs/ARCHITECTURE.md, src/core/contracts/m1-contracts.md,
src/core/contracts/m2-contracts.md, this doc. All M1/M2/M3 contracts stay in force.

## 0. New content kinds (core, in force — T-0400)

Orchestrator-added Zod-validated content kinds + loaders + cross-ref validation
in src/core (schemas.ts, content.ts). Workers READ these; nobody edits them.

- `content/skills.json` (keyed by skillId): `{ xpForLevel?: [10 ints], unlocks?,
  professions: [ {id, name, level, effect?} ] }` with `XP_TABLE = [100,200,...,1000]`
  default and `RECIPE_LEVEL = 5` default. Types: `SkillDef`, `ProfessionDef`.
- `content/fish.json` (keyed by fishId): `{ id, itemId, name, seasons?,
  weather?, time? {from,to}, difficulty (1..100, def 50), xp (def 5) }`.
  - `itemId` keys into items.json, category must be `fish`.
  - Omitted `seasons`/`weather`/`time` = always available. Game-minutes use the
    Stardew 600..2700 scale (6:00 = 600, 2:00 = 2600). Seasons are indices 0..3.
  - Type: `FishDef`.
- `content/animals.json` (keyed by species — RATIFIED in T-0403, section 2).
  `content/machines.json` / `content/recipes.json` ship with T-0404 (sections
  3 and 4); schemas exist in core/schemas.ts as `AnimalDef`, `MachineDef`,
  `RecipeDef`.

## 1. Fishing (RATIFIED — T-0402)

### 1.1 Where state lives

- `state.extensions.fishing`:
  ```
  { session: null | {
      mapId, x, y,                    // cast tile
      phase: 'waiting' | 'hook',
      castDay,                         // world day the cast happened
      castAt, biteAt, hookAt,          // absolute-minute marks (see 1.2)
      fishId } }
  ```
  The session rides save/load so a mid-catch line survives a reload. Purely
  data; the sim owns it, world only renders the bobber.

### 1.2 Time units

- `absoluteMinutes = dayCount*1440 + hour*60 + minute` — a monotonically
  increasing marker shared with player:sim's walk timeouts.
- `gameMinuteOf(clock) = hour*100 + minute` (600..2600) — the unit of
  fish.time windows.

### 1.3 The loop (sim-owned, rod claimed from the bus)

- The rod is an ordinary item: `fishing-rod-t0` (tags `["tool:rod","tier:0"]`),
  already stocked (general-store) and in the starter kit. Fishing:sim claims
  the shared `tool:use-requested` event for rod tools (id prefix `fishing-rod-`
  or tag `tool:rod`); farming:sim routes `toolKindOf()` = 'fishing' to a no-op
  (no energy, no tool:failed) — FishingSim owns rods.
- **Cast** (`fishing:cast {tile, toolId, fishId}`): target tile must be water
  (world map legend `.water`); else `tool:failed {reason:'not-water'}` and no
  session. If water, species are picked deterministically at cast time from the
  fish whose season/weather/time gates match the current moment (availableFish),
  weighted by rarity = `111 - difficulty` (rng fork `fishing:species`). No
  candidates -> `fishing:no-fish {reason:'no-fish-now'}` (no session, nothing
  paid). Otherwise open a `waiting` session with `biteAt = castAt + 10..89`
  (rng fork `fishing:bite`).
- **Wait**: on every `time:tick`, once `biteAt` passes, `fishing:bite {tile,
  fishId}` flips the session to `hook` and sets `hookAt = now`; the species is
  revealed. A session whose `castDay` is no longer the current day is cleared as
  `fishing:escaped {reason:'day-end'}` on the next tick AND on `player:sleep`.
- **Reel** (`fishing:reel`): while `waiting` -> `fishing:reel-cancel` (line
  pulled back, nothing caught). While `hook` -> catch: quality roll (rng fork
  `fishing:quality`, ~94% normal / ~5% silver / ~1% gold), the item
  `addStackToInventory(fish.itemId, qty 1, quality)`; a full inventory emits
  `inventory:full` + `fishing:escaped {reason:'inventory-full'}`. On a catch:
  `fishing:caught {tile, fishId, quality, xp}`, `day:xp:fishing += fish.xp`,
  `day:caught:<itemId> += 1`. Session cleared either way.
- **Escape**: if `hook` outlives `hookAt + 30` in-game minutes without a reel,
  `fishing:escaped {reason:'too-slow'}`.

### 1.4 Events (all bus)

| Event | Payload |
|---|---|
| `fishing:cast` | `{ tile, toolId, fishId }` |
| `fishing:bite` | `{ tile, fishId }` |
| `fishing:caught` | `{ tile, fishId, quality, xp }` |
| `fishing:reel-cancel` | `{ tile }` |
| `fishing:escaped` | `{ tile, fishId, reason: 'too-slow' \| 'inventory-full' \| 'day-end' \| 'no-fish' }` |
| `fishing:no-fish` | `{ tile, reason: 'no-fish-now' }` |
| `tool:failed` | `{ tile, toolId, reason: 'not-water' }` (also used by farming) |

### 1.5 World visual (WORKER-1, browser-only)

- On `fishing:cast` a bobbing float mesh appears at the cast tile; it hides on
  `fishing:caught` / `fishing:escaped` / `fishing:reel-cancel` /
  `fishing:no-fish`, on `player:warped`, and when the player leaves the
  bobber's map. Headless no-op — all logic above is sim-tested.

### 1.6 Content baseline (34 fish)

`content/fish.json` ships 34 species: spring 6, summer 6, fall 6, winter 5, and
11 multi-season/night/weather-special (all-gated `minnow`/`creek-chub`/
`river-perch`/`rock-bass`, rain-only `catfish`, spring-summer `dace`/
`brook-trout`, 2-season `flounder`/`mackerel`/`tuna`/`cod`). Every species keys
a `fish`-category item in items.json (36 items added in T-0402 total for fish).
Difficulty 10..75, XP 4..12 tied to rarity tier.

### 1.7 Test coverage

`tests/sim/fishing.test.ts`: gates (season/weather/time), water-only casts,
no-fish, weighted pick, bite -> catch (item + day stats), reel-cancel,
too-slow escape, inventory-full escape, day-end clear, save/load session
round-trip, and farming:sim no-op for rods. Uses the real village water
(bottom rows 28-31) by seeding `mapStateFromDef` for the village map.

## 2. Animals (RATIFIED — T-0403)

### 2.1 Where state lives

- `state.extensions.animals`:
  ```
  { animals: AnimalState[], lastRolledDay, seq }
  AnimalState = { id, species, bornDay, mature, happy, hearts, fedToday,
                  petToday, hungerStreak, productReady, nextProductAt }
  ```
  Purely data; the herd rides save/load. `id` = `<species>-<seq>` (monotonic
  per save), `happy` 0..100, `hearts` 0..heartsMax (float).

### 2.2 Content baseline (5 species)

`content/animals.json` ships chicken (400g), duck (900g), cow (1500g), goat
(1400g), sheep (1200g). Every species eats `hay` x1 daily (general-store stocks
12 hay at 15g each — T-0403 added the stock entry) and yields its own
`animal_product` item in items.json (T-0403 added `hay`, `egg`, `duck-egg`,
`milk`, `goat-milk`, `wool`). `maturityDays` is 0 for all; enforce later.

### 2.3 Buying (`animals:buy {species, qty}`)

- Caps the herd at `ANIMAL_CAP = 24`; rejects `full`. Requires gold
  `species.buy x qty`, else `no-gold`. Unknown species -> `unknown-species`.
  On success: money deducted, animals added `mature` (maturityDays 0..day),
  `nextProductAt = dayCount + maturityDays + produceEveryDays`, emits
  `animals:bought`. Every failure emits `animals:denied`.

### 2.4 Morning roll (`rollAnimalsDay`, gated on `lastRolledDay`)

Two rollover paths feed this; the guard makes the night roll exactly once:

- **Forced pass-out** (`time:tick`): core advances time first, so the reducer
  rolls `world.dayCount` directly.
- **Voluntary sleep** (`player:sleep`): shipping:sim advances the world inside
  the same action, so animals dispatches a nested `animals:roll-day` which the
  store runs after every `player:sleep` reducer — order-independent.

Per fed morning: `happy += 12`, `hearts += 0.35`, hunger streak resets. Per
unfed morning: `hungerStreak += 1`, `happy -= 16 + 5*streak`, `hearts -= 0.1`
(no bond from a starving animal). Petting (once/day, `animals:pet`) adds
`happy += 10`, `hearts += 0.2` on the spot. A mature animal whose
`nextProductAt <= day` AND `hearts >= 2` (MIN_HEARTS_TO_PRODUCE) flips
`productReady = true`.

### 2.5 Collecting (`animals:collect {animalId}`)

Rejects `no-animal` / `not-ready` / `unknown-species` (all `animals:denied`).
Quality roll (`animals:quality` rng fork): gold when `happy >= 70`,
`hearts/heartsMax >= 0.3`, `r >= 0.85`; silver when `happy >= 45`,
`hearts >= 2`, `r >= 0.6`; else normal. Product goes into the bag (capacity
limited — a full bag emits `inventory:full` and the animal STAYS ready), then
`productReady = false`, `nextProductAt = dayCount + produceEveryDays`, and
`animals:collected`.

### 2.6 Feeding (`animals:feed {animalId}`)

Consumes exactly `species.feed.qty` of `species.feed.itemId` (atomic: a bag
without the full count refuses `no-feed` and nothing is consumed). Already fed
this day -> `already-fed`. Emits `animals:fed`.

### 2.7 Events

| Event | Payload |
|---|---|
| `animals:bought` | `{ species, qty, uids, gold }` |
| `animals:day` | `{ day, count, produced }` |
| `animals:fed` | `{ animalId, species, itemId }` |
| `animals:petted` | `{ animalId, species }` |
| `animals:collected` | `{ animalId, species, itemId, qty, quality }` |
| `animals:denied` | `{ reason: 'full' \| 'no-gold' \| 'unknown-species' \| 'no-animal' \| 'already-fed' \| 'no-feed' \| 'already-petted' \| 'not-ready' }` |
| `inventory:full` | `{ animalId, itemId }` (shared inventory event) |

### 2.8 Test coverage

`tests/sim/animals.test.ts`: buying (gold, cap, unknown species, uid
uniqueness), the morning roll over BOTH paths (fed gain, hunger decay,
idempotence, forced pass-out), bond gating (`MIN_HEARTS_TO_PRODUCE`, ~4 fully
cared days to first product), feeding/petting denials, quality tiers, collect +
reschedule, inventory-full keeps the animal ready, per-species products, and
herd save/load round-trip.

## 3. Machines (RATIFIED — T-0404)

### 3.1 Content baseline

`content/machines.json` (keyed by machineId) ships four processors. The
machine's **id doubles as the item id** used to place it (`machine`-category
item, obtained by crafting — section 4):

| machine | input | output | hours |
|---|---|---|---|
| `mayonnaise-machine` | egg x1 | mayonnaise x1 | 3 |
| `cheese-press` | milk x1 | cheese x1 | 4 |
| `loom` | wool x1 | cloth x1 | 5 |
| `seed-maker` | parsnip x1 | parsnip-seed x1 | 1 |

T-0404 added the machine items `mayonnaise-machine` / `cheese-press` / `loom` /
`seed-maker` (category `machine`, uncraftable-until-bought via recipes) and the
products `mayonnaise` / `cheese` / `cloth` (category `animal_product`) plus the
cooked foods (section 4) to items.json.

### 3.2 Where state lives

A machine is a placed object `machine:<machineId>` in `MapState.placed[x,y]`
(any map), whose `data` is:

```
{ machineId, loaded: 0|1, remainingTicks }
```

`remainingTicks` counts down 1 per 10-minute `time:tick` (1 in-game hour = 6
ticks). Machines ride save/load and map migration like any placed object; no
extension block.

### 3.3 Actions and events

| Action | Payload | Result on success |
|---|---|---|
| `machines:place` | `{ tile, itemId }` | consumes the machine item, adds the placed object, `machines:placed` |
| `machines:insert` | `{ tile, slot }` | consumes one matching input bundle from the slot, arms `remainingTicks = hours*6`, `machines:loaded` |
| `machines:collect` | `{ tile }` | adds each output to the bag, resets `loaded`/`remainingTicks`, `machines:collected` |
| `time:tick` | — | decrements every loaded machine; last tick emits `machines:finished` |

Denials (all `machines:denied`): `unknown-machine`, `no-map`, `occupied`,
`blocked`, `no-item`, `no-slot`, `not-needed`, `busy`, `no-ingredient`,
`no-machine`, `not-loaded`, `not-ready`, `inventory-full`.

Rules fixed in T-0404:

- **Placement** requires a free walkable tile (`legend.walkable`, per the map's
  authored glyph). A bag without the full machine item refuses `no-item`.
- **Insert** needs a slot holding an item matching a `def.input` entry (qty
  checked atomically through the bag); a loaded machine is `busy` until its
  current bundle is collected.
- **Collect** is atomic on outputs: if the bag cannot take the full output, the
  machine STAYS loaded+ready and emits `inventory:full` + `machines:denied
  {reason:'inventory-full'}`.
- **Countdown** pauses during `player:sleep` (only `time:tick` advances it).

## 4. Recipes, cooking and food buffs (RATIFIED — T-0404)

### 4.1 Content baseline

`content/recipes.json` (keyed by recipeId) ships `kind: 'crafting'` recipes for
the four machines and `kind: 'cooking'` recipes for three foods:

| recipe | kind | ingredients | unlock | food |
|---|---|---|---|---|
| `mayonnaise-machine` | crafting | wood x20, fiber x5 | foraging 2 | — |
| `cheese-press` | crafting | wood x25, stone x10 | farming 3 | — |
| `loom` | crafting | wood x15, fiber x10 | foraging 4 | — |
| `seed-maker` | crafting | wood x20, stone x12, fiber x5 | farming 2 | — |
| `fried-egg` | cooking | egg x1 | none | energy 20, health 8 |
| `cheese-omelette` | cooking | egg, milk, cheese x1 each | farming 4 | energy 40, health 18, buff `farming +1` 2h |
| `ember-bloom-tea` | cooking | ember-bloom x1, fiber x3 | none | energy 15, health 6, buff `luck +1` 3h |

### 4.2 Crafting (`crafting:craft {recipeId}`)

- **Unlock**: `recipeUnlocked(state, recipeId)` = no `unlock`, or the named
  skill's level >= the required level. Locked -> `crafting:denied
  {reason:'locked'}`.
- **Atomic**: the output must fit the bag FIRST (else `inventory-full`, nothing
  consumed); only then are ingredient bundles removed full-or-none (else
  `missing-ingredients`, nothing consumed); the output is added last. Success
  emits `crafting:crafted {recipeId, itemId, qty}`.

### 4.3 Eating (player:eat {slot})

- `player:eat` requires a stack in the slot whose item is a cooked food
  (`not-food` / `no-slot` otherwise). Consumes one, adds `food.energy` /
  `food.health` capped at the player's maxima, and appends `food.buffs` as
  `ActiveBuff { stat, amount, expiresAt }` where
  `expiresAt = absoluteMinutes(now) + hours*60`. Emits `food:eaten {itemId,
  energy, health, buffs}` (the food's deltas).
- Buffs live in `extensions.crafting.buffs` and are **pruned on `time:tick`**
  against the advanced absolute minute; `activeBuffs(state)` reads those still
  in window. They ride save/load.

### 4.4 Events

| Event | Payload |
|---|---|
| `crafting:crafted` | `{ recipeId, itemId, qty }` |
| `crafting:denied` | `{ reason: 'unknown-recipe' \| 'locked' \| 'inventory-full' \| 'missing-ingredients' \| 'no-slot' \| 'not-food' }` |
| `food:eaten` | `{ itemId, energy, health, buffs }` |
| `machines:placed` / `machines:loaded` / `machines:finished` / `machines:collected` | { tile, ... } (section 3) |

### 4.5 Test coverage

`tests/sim/crafting.test.ts` + `tests/sim/machines.test.ts`: every action,
every `*:denied` branch, atomic consumption (full bag / missing ingredient
leaves the bag untouched), unlock gating across skill levels, countdown and
finished scheduling, collect denials, inventory-full keeps the machine ready,
and both persistence paths (placed machine in-flight + active buffs) survive
`flushPersist`.

## 5. T-0405 (skills panel and HUD) — briefed, not yet ratified

Still open (WORKER-3 / workers, browser-only rows): skills panel listing the
five skills with level/XP/professions and the currently known recipes;
animal/fishing/machine click affordances; a buff HUD line draining over time;
audio-settings UI. Covered by Playwright once a browser runs here; sim-level
logic behind them already lands with sections 3–4.