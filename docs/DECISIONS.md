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
31. **Skills reuse the existing day:xp counters; no per-action XP plumbing (M4).** FarmingSim (and later foraging/mining/fishing/combat) already bumps `day:xp:<skill>` counters each day. The skills reducer farms those at day close: `day:summary.xpEarned` -> one enqueued `skills:grant-xp` per row, which the store already flushes after the outer dispatch. XP is a linear 100*(level+1) per level (100..1000), capped at level 10 with the overflow dropped. Level-ups emit `player:levelup`; the diff of `recipesUnlockedFor` at the new level vs the level before crossing emits `skills:recipes-unlocked` so content never resends already-known recipes. Professions are one-per-skill, level-gated by content, first pick wins and is immutable.
32. **Fishing claims rod tools from the shared tool-use bus; the whole loop is one saved session (T-0402).** Farming:sim resolves `tool:use-requested` for every non-rod tool and now short-circuits `kind === 'fishing'` (no energy, no `tool:failed`), while fishing:sim answers the same event for rods (id prefix `fishing-rod-` or tag `tool:rod`). The mini-loop is modelled as a single stateful `extensions.fishing.session` (`waiting` -> `hook`) with absolute-minute marks so it survives save/load exactly like walk timeouts and never crosses midnight. Cast time is species-time: `availableFish` gates season (calendar.seasonIndex) + weather + Stardew-scale time window, and the fish is drawn at cast from a rarity-weighted pool (`111 - difficulty`) but only revealed at `fishing:bite`. Reeling while waiting is a cancel (no cost), reeling on the hook is a catch; a reeling press when no session exists is a cast. Escape reasons are explicit (too-slow / inventory-full / day-end) and each is pinned by a sim test. XP rides the existing `day:xp:fishing` + `day:caught:<itemId>` counters (decision 31). The bobber is a bus-driven world visual with no state of its own.
33. **The "Minecraft-POV" request is a presentation layer over the unchanged 2D sim, not a voxel rework of the world (T-0406).** The grid, pathfinding, collisions, farmer sim and content stay 2D/unchanged (M3 contracts in force); a new pure module (voxel.ts) derives block columns from the existing tile grid + legend so a flat plain reads as a raised blocky island: houses extrude to 3-tile cubes, tree tiles stack trunk+crown cubes, water pools sit below the walkable surface with rim walls on the bordering flat tiles. The eye-level camera replaces the follow camera at the press of F (bus `view:camera-mode {mode}`), yaw/pitch come from player facing + mouse look, and head-bob tracks movement. Top-down is the default and untouched (all sim/walk/bot tests still pass unchanged); voxel math is unit-tested (tests/view/voxel.test.ts). The copyrighted *Minecraft*/*Stardew* names, art and soundtracks are never used — the aesthetic is original and the music is procedurally generated WebAudio (T-0460), matching the license stance in docs/ASSET_LICENSES.md.
34. **The soundtrack is an original generative system, not samples or licensed music (T-0460).** Every bar is synthesized at runtime from pure data: a per-season scale (spring Ionian, summer Lydian, fall Mixolydian, winter pentatonic-minor), a per-mood chord progression and tempo profile (dawn/day/dusk/night/late), biome overrides (home lullaby, cave/mining drone, low-health danger ostinato) and weather textures (rain/snow/wind mute percussion and air the lead up an octave; storm keeps drive with a sawtooth lead). Theme selection reads only the deterministic sim state (clock hour, season, weather, mapId, health fraction) so contexts never depend on wall-clock or RNG; bar notes are generated from `rng.fork('music')` and are unit-pinned as identical for equal seeds. Autoplay: the AudioContext is only created/resumed after the first `player:moved` (a user gesture); `music:set-enabled` / `music:set-volume` give the future settings screen control, and the engine is headless-safe (no timer/context off-DOM), keeping every sim/bot/CI run untouched by audio.
35. **Animals bond-gate production and roll the morning via nested dispatch (T-0403).** A mature animal only produces once `hearts >= 2` (~4 fully fed+petted mornings at +0.35/+0.2 per day), so a brand-new herd needs a few days of care before the first egg/milk — the friendship gate is the whole point of caring, not a dev convenience. The morning roll (`rollAnimalsDay`) is idempotent on `lastRolledDay` and feeds BOTH rollover paths without caring about feature-registration order: the forced pass-out `time:tick` runs after core's clock advance (it reads `world.dayCount` directly), while `player:sleep` dispatches a nested `animals:roll-day` that the Store flushes after every `player:sleep` reducer — so it reads the post-advance day whether animals:sim registered before or after shipping:sim (the naive `dayCount + 1` broke every harness where animals set up last). Quality is a pure roll from happy+bond: gold needs `happy >= 70` + `hearts >= 30%` + a 15% rng draw, silver `happy >= 45` + `hearts >= 2` + 40%; a full bag emits `inventory:full` and the animal STAYS ready. Feeding is atomic full-or-none on the bag (new `removeStackFromInventory` helper — it refuses the whole feed when any unit is missing, nothing is consumed). The initial herd is 5 species (chicken/duck/cow/goat/sheep) using one feed — hay, which general-store now stocks alongside the starter seeds.
36. **Machines are placed objects whose id doubles as their item id; every processor runs a data-driven countdown (T-0404).** A machine is a `machine:<machineId>` placed object on any free walkable tile, placed from a `machine`-category item of the SAME id that only the crafting menu can produce (recipes kind crafting gate them behind skill levels, so they enter the economy like SDV artisan goods rather than shop stock). Insert picks ONE input bundle from a bag slot (atomic full-or-none on the ingredient qty, refressing the same `removeStackFromInventory` helper as feeding), arms `remainingTicks = hours * 6` (1 in-game hour = six 10-minute `time:tick` steps — the sim's only time unit, so machines pause across sleep exactly like walk/fishing timeouts and never drift with wall-clock), and the final tick emits `machines:finished`. Collect is output-atomic: a bag that cannot take the full output refuses with `inventory:full` + `machines:denied` and the machine STAYS loaded, so overflow never eats a product. A machine cannot stack in the bag (canStack false). All state rides `MapState.placed[x,y].data`, so save/load and map migration (core's `migrateAllMaps` keeps placed objects in bounds) cover machines for free — no extension block needed.
37. **Recipes unlock by skill level and cooking is atomic; buffs are absolute-minute-expiring rows pruned on tick (T-0404).** A recipe is always-known unless it declares an `unlock {skill, level}`; `crafting:craft` checks the player's current levels (reusing skills' `skillLevelOf`/`recipesUnlockedFor` — no duplicated level table). The craft is a three-phase commit: the OUTPUT must fit the bag first (probe `addStackToInventory`), then ingredient bundles are removed full-or-none, then the output lands — a full bag or a missing stack leaves the bag byte-identical, which the tests pin. Cooking is `player:eat {slot}`: needs a slot whose item is the output of a `kind: cooking` recipe, adds `food.energy`/`food.health` capped at the player's maxima, and turns `food.buffs` into `{stat, amount, expiresAt}` rows in `extensions.crafting.buffs` (same absolute-minute clock as fishing, decision 32) that `time:tick` prunes once `expiresAt <= now` — the STAT is stored for the future balance layer (profession buffs land T-0405) while today the sim only proves arming and expiry. `food:eaten` reports the food's deltas so the HUD can toast "+40 energy" rather than the capped total.
38. **Tool interaction requests carry a map, because the sim has no ambient context (T-0502).** `ToolUseRequest.tile` is a `WorldPos`, not a bare `TilePos`, and the emitter stamps `player.position.mapId` onto it. The emitter and the consumer had drifted: farming and machines resolved the tile against a map they had to guess, and the guess was wrong, so *every real tool swing in the actual game* failed with `reason:"no-map"` while every unit test passed � the tests dispatched the payload directly and so never exercised the emitter. The lesson recorded here because it generalises: a payload assembled in one lane and consumed in another needs the ambient context both sides assume, and the only thing that catches the drift is driving the real input path, which is what `tests/sim/interact-path.test.ts` and the browser harness now do.

39. **The camera follows the sim `facing`; the sim never follows the camera (T-0504).** `facing` stays a 4-way value and `tileInFront(position, facing)` stays the single source of truth for *what a tool acts on* � that is a load-bearing contract for bots and tests. The view owns a `FirstPersonLook` that damps the camera yaw toward `yawOfFacing(facing)` every frame, and mouse-look feeds the resulting cardinal back as `player:face`. So keyboard turning rotates the camera, mouse-look moves the facing, and the two cannot disagree. Two bugs came out of building this: `lookPose.yaw` was previously written *only* on entering first person and under pointer lock, so without a pointer lock the camera was frozen and you could hoe a tile behind you; and `updatePlayer` filled `lerpFrom`/`lerpTo` and set `lerpT = 1` on the first frame, so the `if (lerpT < 1)` branch never ran and the player avatar sat at the world origin � the first-person eye was in the middle of the map. The reticle is projected onto the *target tile*, not painted at screen centre: with one-tile reach and a pleasant pitch, the screen centre lands ~1.5 tiles ahead and would have promised tile #2 while the tool hit tile #1.

40. **Diagonal movement steps each axis at full speed; it is not normalised by vector length (T-0506).** `player:walk` computes `xDelta = sign(dx) * speed * dt` and the same for y, with no `Math.hypot` division. Normalising forces the *total* displacement to equal `speed * dt` in every direction, which caps a diagonal at one axis of distance and leaves each axis with `1/sqrt(2)` of the speed � measured at 0.71x, and it is the single most common cause of "diagonal movement feels sluggish". The sub-tile collision sampler, `MAX_STEP`, wall sliding and the `facing` derivation are untouched, and the divide-by-zero on an all-zero input vector went away with the division. Invariant under test: for a fixed `dt`, each axis of a diagonal equals that axis's single-axis delta, across five `dt` values, all four diagonals, and shift speed.

41. **Audio claims are made against named cues, never against a note count (T-0505).** The acceptance harness originally counted `createOscillator` calls and reported `success-audio=YES (27 notes)`. That verdict was false confidence: the procedural soundtrack synthesises continuously, so a window containing no cue at all still contains music notes, and the same check passed for a *failed* action. The audio lane now records every `AudioEngine.play(cue, specs)` call to a dev-only ring buffer published as `__EH_SFX__`, keyed by a `SfxCue` union; music is logged separately at bar granularity and never shares a helper with the SFX path, so the log is sfx-only by construction. The harness asserts the cue *name* and includes the falsifying control: a 4s idle window must log 0 SFX cues while music bars keep scheduling. Adding a sound without naming it is now a type error rather than an unlabelled blip.

42. **In a GPU-less environment, speed is measured against commanded sim time, not the clock (harness).** Three plausible measurements were tried and all three were wrong: wall-clock tiles/sec (a 2s hold sampled 5883ms; identical code read 0.816 and 2.607 tiles/sec, and shift-vs-jog read 0.74 then 1.21), displacement per rendered frame (a hold that clips a wall averages nonsense � one diagonal test read 0.63 purely because its single-axis reference had 4 unobstructed frames), and summing the unit direction vector (1.0 by construction, so it would "confirm" a fix that never happened). What is used instead: wrap the store's `dispatch`, read the player position either side of each real `player:walk`, and divide the distance the sim actually moved by the time it was commanded to move, per axis. That is collision-independent and frame-rate independent, and it is what turned the diagonal verdict from 0.71 to 1.00. Measurements start from a tile with verified-open tiles ahead on both axes, and the harness prints INCONCLUSIVE rather than a number when the reference is obstructed. Frame rate in this environment is a property of the SwiftShader CPU rasteriser, not of the scene: 9060 triangles in 11 draw calls is trivial for real hardware and must not be read as a performance result.

43. **Reachability, not a green test suite, is what separates a game from a demo (T-0510/T-0511/T-0512).** The clearest symptom of this project so far was a suite at 440 passing tests over a game in which a player could not ship a crop, eat, tend a machine or sleep - so the game could not be played through one single day. The sim logic existed, was correct, and was unit-tested; it was simply unreachable from the keyboard, and a green suite said nothing about that. The rule recorded here: a milestone is not done because its logic is tested, but when a player can *do* the thing from normal play, and the proof has to travel the real input path, never a directly-dispatched action. That is the same lesson as decision 38 from the other end - the missing-`mapId` bug survived because the tests bypassed the emitter, and this class of bug survives because the tests bypass the keymap. `scripts/day-loop.ts` therefore drives till -> plant -> water -> four real nights -> harvest -> ship -> day close with `keyboard.press` only, and grows crops over real in-game days rather than fast-forwarding a stage.

44. **One contextual `use` key resolves every machine and animal; the player never memorises object types (T-0511).** `Q` dispatches a single `machines:interact {tile}` on the faced tile and the sim decides what "use" means there: an idle machine loads from the selected slot, a finished one is collected, a running one refuses with its own countdown, an animal is fed/pet/collected according to its state. The alternative - separate keys for load, collect, feed and pet - was rejected because it makes the player learn which object they are standing next to before they can act, which is exactly the knowledge a context action exists to remove. The cost is that the sim must answer for every object type; the payoff is that refusals can name the key that would have worked. `F` remains the shop: reintroducing it as a camera key was the one binding conflict that was tempting and wrong.

45. **A harness failure is not a game bug until the harness is proven right; three of four were the harness (T-0512).** The first day-loop run reported 3/8, and four of those failures looked like missing features. Three were the script: it tilled "any walkable tile" when a hoe only bites grass (`code === 'g'`); it computed the stance as `plot + dir` instead of `plot - dir` and so aimed two tiles away at nothing; and it searched `[id*=craft]` and the HUD's `textContent` for a panel that carries only classes (`.eh-crafting-dialog.is-open`, 119 recipe rows) and toasts mounted *outside* `#game-root` (`.eh-toast`). The fourth was the game being *right*: `parsnip` has `waterNeed: 1`, the script watered once and slept six nights, and the sim correctly killed the unattended field. "Fixing" that would have meant breaking correct behaviour. One check also produced a false PASS - the regex for "Q gives feedback" matched the static hint bar's "Space = use tool" - which is decision 41's error in a different costume, so contextual-use feedback is now read from `.eh-toast` only. The general rule: before reporting a missing feature, prove the observation method can see a feature that is known to exist.