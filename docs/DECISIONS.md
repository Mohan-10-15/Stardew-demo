# Ember Hollow — Decisions Log

Each non-obvious choice gets an entry. Newest last.

1. **Working title: Ember Hollow.** Substitutes the intended "original name/art/
   music" requirement. Logged M0.
2. **oc-grid adaptation (M0).** This machine has no `~/.local/state/oc-grid`,
   no `oc-send`/`oc-todo-clear`, no worker panes. The 4-agent team is emulated:
   briefs written to docs/tasks/T-####.md, "workers" run as opencode subagents,
   roles WORKER-1 (world/engine), WORKER-2 (sim), WORKER-3 (people/UI). Reports
   follow `DONE T-#### | files | verify | issues`. Recorded in AGENTS.md.
3. **Sim tick = 10 in-game minutes, deterministic.** `advanceClock` is pure;
   RNG seeded from state.rngSeed; view only reads sim state. Headless bot and
   tests replay exactly.
4. **Content is single-file-per-kind JSON.** items.json/crops.json/npcs.json +
   maps/<id>.json, Zod-validated. Map layers allow newlines (whitespace
   stripped) so maps stay authorable by hand.
5. **Features self-register via import.meta.glob.** Nobody edits a shared
   registry; src/features/index.ts pulls all index.ts side-effects. Works under
   Vite and Vitest via the same transform.
6. **SaveStore is an interface.** Memory (tests), IndexedDB (browser), fs
   (node bot). Chosen so the sim stays headless and corruption-safe tests run
   without a browser.
7. **Base time reducer is core-owned in M0.** `time:tick` reduces via
   advanceClock. WORKER-2 replaces it with the full time/energy module in M1;
   the contract (pure, deterministic, JSON-safe) stays.
8. **secondsPerTick defaults to 7** (about 16 min real per in-game day) —
   genre-aligned; tunable; sim step content is independent of real time.
9. **Pass-out hour = 2:00 AM (PASS_OUT_HOUR=26).** Clock logic stays pure;
   pass-out clamping happens in advanceClock.
10. **Content in M0 is intentionally tiny seed data.** Full quotas arrive in
    the owning lanes' milestones (M1-M6). Not a scope cut — tracked in
    ROADMAP quotas.
11. **Feature glob moved to src/features/auto-import.ts (M1).** The eager
    `import.meta.glob` originally lived inside core/registry.ts; Vite inlines
    feature imports into registry's module scope, creating an ESM cycle
    (registry still evaluating → feature index calls registerFeature → TDZ
    ReferenceError under Vite/vitest). Now game.ts imports registry BEFORE
    auto-import, so the registry finishes evaluating first and feature index.ts
    self-registration is safe. Feature indexes restored to side-effect
    registration after the fix.
12. **Store queues nested dispatches instead of throwing (M1).** engine:sim's
    `player:interact` reducer emits `tool:use-requested`, which farming:sim
    handles by dispatching `farming:tool-use` — reentrant. Core Store now defers
    nested dispatches and flushes them synchronously after the in-flight action
    commits, preserving determinism (no microtasks, still replayable). A
    `state:changed` is emitted per completed action.
13. **Maps are seeded from content, not a placeholder (M1).** createGameRuntime
    builds initial MapState from map defs (mapStateFromDef / buildInitialMaps,
    core/state.ts); player spawn comes from the farm def's `spawn`. Saves
    migrate grid layouts on load when map `version` is bumped (migrateAllMaps):
    grid rebuilt from content, placed objects kept while in bounds.
14. **Regrow semantics (M1).** Harvest of a regrow crop resets `stage` to
    `days.length - regrow` (e.g. blueberry days.len 13 regrow 4 → stage 9), so
    the next harvest comes `regrow` watered days later. m1-contracts.md was
    aligned to this (it originally said `days.length - 1`, which ignored the
    regrow interval). Matches genre convention.
15. **Keyboard input is single-owner (M1).** WORKER-3's input:ui attaches key
    listeners and sets `globalThis.__EH_INPUT_OWNED__`; main.ts's built-in
    stopgap handler (WASD/Space) goes idle once the flag is set, so move/hold
    repeats dispatch exactly once per 120ms interval with no double moves.
16. **Shops are a content kind (M2).** content/shops/<id>.json,
    Zod-validated ShopDef { id, name, buys, stock: [{ itemId, price?, qty? }] };
    qty omitted = infinite daily stock; price overrides item.price.buy. Runtime
    counters live in state.extensions.shop and restock each morning. Buy/sell
    are pure sim reducers (shop:buy / shop:sell / shop:restock) so money and
    stock stay deterministic and replayable.
17. **Warp stepping lives in engine:sim player:move (M2).** A validated move
    onto a mapDef.warps tile rewrites player.position to the destination map +
    offset and emits `player:warped` once. The view swaps the rendered map
    segment on the position change. Pure `resolveWarp(mapDef, x, y)` is
    unit-tested against farm+village.
18. **Night rollover is idempotent across both called paths (M2).** The same
    farm rollover (weather roll → its effects → crop growth → forage refresh)
    is invoked from the `time:tick` reducer AND the `player:sleep` reducer just
    in case sleep's own pass wins the race; both applyFarmRollover and
    applyWeatherRoll are gated on ext day-counters (farming.lastRolloverDay /
    weather.lastRolledDay) so they fire exactly once per world day regardless
    of which reducer runs first. Events (weather:changed, crop:lost,
    crop:withered) are emitted only by the pass that actually rolls.
19. **Forage spawns as placed objects (M2).** Each morning the farm map gets a
    batch of `forage:<itemId>` placed objects (count floor(3 + rng*5), picked
    from items with category 'forage' whose optional `season:<idx>` tag matches
    today). Any map's old forage is cleared first. Scythe/bare-hand interact
    picks one up. Keeps decay/save/serialization free — forage re-rolls at each
    day rollover instead of persisting long-lived state.
20. **day:summary is emitted once per sleep (M2).** WORKER-2 accumulates per-day
    counts in state.player.stats (day:sold:<itemId> etc.), resets them at each
    day rollover, and emits `day:summary` exactly once after shipping payout on
    sleep/pass-out. WORKER-3's summary:ui dialog consumes it.
21. **Shop UI and shop sim are separate feature dirs (M2).** Sim owns
    src/features/shop/ (id shop:sim); UI owns src/features/shop-ui/ (id
    shop:ui) to avoid cross-worker write conflicts on a shared index.ts. UI
    opens on 'F' (data-driven 'shop' keymap action → `ui:open-shop` bus event);
    walking-into-a-shop proximity triggers properly land in M3 with NPCs.
22. **NPC schedules are a content kind with override slots (M3).** Schedules live
    in content/schedules.json as { home, default, overrides } with rules keyed
    by Stardew-style game-minutes (600 = 6 AM, 2600 = 2 AM). The first override
    whose { season, weather, day, dayOfWeek } all match wins; no rule covers
    the clock -> NPC waits at home/spawn. Same-map windows move tile-by-tile
    via deterministic A* (N,S,W,E tie-break, max 3 tiles per 10-min tick);
    cross-map windows apply as an instant "through the door" cut, so authors
    place map changes at night. Positions live in mapState.npcs; intents in
    state.extensions.people.targets.
23. **Gift/heart math (M3).** Taste deltas: loved +1, like +0.5, neutral 0,
    dislike -0.5, hate -1, clamped 0..10, only the first gift of a day counts;
    talking once a day gives +0.25. Heart events are data (dialogue.json
    heartEvents + eventLine) with a code trigger; each id plays once ever and
    reward hearts are capped at 10. Dialogue pools pick by byHeart > weather >
    season > time-of-day > default, seeded per npc+day for repeatable lines
    ("say another" cycles the seeded order).
24. **Quests are collect/deliver/talk only for M3 (M5/M6 add reach/mine).**
    Quest rewards mutate money/inventory/relationships directly in the people
    sim reducers, reusing addStackToInventory from inventory:sim (ShippingSim
    and ShopSim are the precedent). Progress for collect-type is re-derived
    from inventory at turn-in instead of being ticked.
25. **Acceptance playtests are a milestone gate (ADDENDUM A).** docs/ACCEPTANCE.md
    carries the per-milestone script; steps are marked sim (headless bot/tests,
    the gate here) vs browser (deferred to Playwright). Browser-only steps may
    not be the sole coverage of any feature's logic.
26. **Quest interaction routing (M3).** A player:interact on an NPC resolves in
    priority order: pending deliver (held item is the quest item) → pending talk
    → pending turn-in (giver + objective satisfied) → giver accepts a new quest
    → gift. A held tool (item category 'tool') never counts as a gift and falls
    back to talking, so the starter hoe can't be gifted accidentally. Weekly
    quests re-open 7 days after their doneDay.
27. **Heart-tier dialogue key is "2", not "0" (M3).** The first M3 dialogue content
    used byHeart tier "0", which always matched at hearts>=0 and starved the
    weather/season/time pools — visibly freezing dialogue variety. All six NPCs
    now key their heart pool at tiers 2/5/8 so greenhorn players see season and
    weather lines change as intended.
28. **Schedule targets are content-validated to be walkable (M3).** assertScheduleRule
    and homeAnchor require the legend glyph at every scheduled tile to be walkable;
    the rule caught the worker's juniper clinic anchor inside a building 'h' tile
    and it was moved to the porch floor (8,20). NPCs can never be authored to stand
    in water, trees, or walls.

29. **Interactions emit two feedback buses, not one (ADDENDUM B).** tool:used now fires ONLY on an outcome with a concrete effect (tilled/planted/watered/chopped/harvested/...) and carries the exact effect; every miss fires tool:failed with a reason (frozen/exhausted/occupied/nothing/not-tilled/...). The view maps success -> arm-swing + colored particle burst, failure -> red flash on the highlight tile only, and the audio lane maps success -> ascending blip, failure -> low buzz. farming:blocked stays for weather-gated logic (winter). The sim split is the contract; no failure ever rides the success bus and tests pin both sides.
30. **Continuous walk is a new reducer, not a rework of player:move (ADDENDUM B).** player:walk takes dx/dy/dt/speed, advances a fractional position, samples the destination tile per axis in sub-tile steps (max 0.25u) so a big dt cannot tunnel a one-tile wall, drains energy proportional to distance moved, and warps the instant a crossed tile is a warp. player:move remains the tile-stepping contract for bots/tests/WORKER-2 and is left untouched. Facing precedence is diagonal-up first for 8-way play, and the view snaps (no lerp) whenever the position is fractional.