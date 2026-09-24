# Ember Hollow — Architecture

## 1. Simulation is deterministic

- The sim is tile-based and runs headless in Node (vitest). Rendering is 3D and
  reads sim state only.
- Fixed timestep: one sim tick = 10 in-game minutes (TICK_MINUTES). `advanceClock`
  in src/core/time.ts is a pure function.
- All randomness flows through `Rng` (src/core/rng.ts), seeded from
  `state.rngSeed`. Replays and the headless bot are reproducible.
- The view never mutates sim state. The store dispatches JSON-safe actions to
  reducers registered by features (`Store.registerReducer`).

## 2. Module layout

- Features live under src/features/<name>/ with sim/ (WORKER-2), view/ (WORKER-1)
  and ui/ (WORKER-3) subfolders.
- Every feature folder has an index.ts that self-registers its `FeatureModule`s by
  importing them; src/features/index.ts imports all entries via
  import.meta.glob so no shared registry is edited by hand.
- src/core is owned by the orchestrator: types, Rng, EventBus, Store, save/load,
  content schemas + validator, feature contract, game bootstrap.

## 3. Content is data

- content/**/*.json, validated by Zod schemas in src/core/schemas.ts.
  - content/items.json => ItemDef map
  - content/crops.json => CropDef map (seedId must exist in items)
  - content/npcs.json => NpcDef map
  - content/maps/<id>.json => MapDef (multi-line layers are whitespace-normalized)
- Map validator: dimension match, legend glyph coverage, spawn bounds, warp
  target existence. Cross refs: crop.seedId -> items.

## 4. Save/load

- SaveFile = { format:'ember-hollow', version, savedAt, state }.
- migrations: Record<version, (raw) => raw+1>; migrateSave walks to latest.
- sanitizeState backfills missing fields from defaults.
- SaveStore interface: MemorySaveStore (tests), IdbSaveStore (browser),
  FsSaveStore (node bot). 3 slots named slot1..slot3.

## 5. Feature module contract

See src/core/feature.ts:
- lanes: world | sim | people | ui | core (see AGENTS.md ownership).
- setup(ctx) registers reducers; onTick(ctx, step) per sim step;
  view()/ui() provide Three.js view / DOM UI handles.

## 6. Engine notes (WORKER-1)

- Camera: angled top-down, smooth follow, zoom, 90-degree snap rotation.
- Interactions target the tile in front; player moves freely with collision.
- Rendering reads sim state; maps are serialized grids, model instantiation
  happens through an asset-ID layer so assets can be swapped.
- Performance budget: 60 FPS @1080p on integrated GPUs; Low/Medium/High presets;
  F3 debug overlay. See docs/ASSET_LICENSES.md for asset sources.

## 7. Dev tooling

- `npm run check`: typecheck + lint + unit/sim tests + content validation.
- tests/sim: headless sim tests (node). tests/content: content validation.
- Dev console (skip day, set money, teleport) is gated and stripped from release.
- Headless bot plays 2 in-game years (M8).