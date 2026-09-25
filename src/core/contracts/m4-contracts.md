# M4 Contracts — life skills (fishing, animals, machines, cooking/buffs, skills panel)

Status: ORCHESTRATOR. Workers code against this document; raise disagreements in
their report (`DONE T-#### | files | verify | issues`). Fishing (section 1) is
RATIFIED (T-0402). Sections for animals, machines and recipes/buffs land with
T-0403 / T-0404 and are marked RATIFIED there — do not code them from here yet.

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
- (T-0403/T-0404 will add `content/animals.json`, `content/machines.json`,
  `content/recipes.json`; schemas already exist in core/schemas.ts as
  `AnimalDef`, `MachineDef`, `RecipeDef`.)

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