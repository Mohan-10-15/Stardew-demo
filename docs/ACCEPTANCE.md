# Ember Hollow — Acceptance Playtests (ADDENDUM A)

Each milestone is NOT done until its script steps pass. Since no browser runs in
this environment, every step is driven by the headless sim/bot and/or unit tests;
`browser`-marked steps are deferred to Playwright once a browser is available and
must never be the only coverage for a feature's logic.

Coverage marks: `sim` = covered by headless tests now · `browser` = deferred to
Playwright · `sim+browser` = sim covered now, browser check pending.

## M0 — Foundations: PASS (commit e1c4545)

| Step | Cov | Where |
|------|-----|-------|
| `npm run check` is green | sim | `npm run check` (typecheck + lint + 130 tests + content validation) |
| `npm run dev` opens a lit 3D map | sim+browser | tests/sim/engine-boot.test.ts boots view+sim headless; dev server HTTP 200 verified at integration points |
| WASD walks with collision | sim | tests/sim/walk.test.ts (engine:sim player:move + collision) |
| camera snap-rotates | sim+browser | engine:view snap rotation under 90-degree increments (view unit checks); visual check deferred |
| F3 shows FPS and tile coordinates | browser | debug overlay markup; headless visual check deferred |
| Save, refresh, position restored | sim | tests/sim/save-roundtrip + persist.spec (position + farmState + time restored through load) |
| AGENTS.md and docs/ exist, git has clean milestone commits | sim | repo state |

## M1 — Core loop: PASS (commit 709f567)

| Step | Cov | Where |
|------|-----|-------|
| New game -> hoe a tile | sim | tests/sim/farming.test.ts (tillTiles via farming:sim) |
| plant -> water | sim | farming.test.ts (plant/water, soil state) |
| sleep; crop advances a growth stage each night | sim | day-loop + farming.test.ts (stage += per rollover) |
| harvest it, ship it, money arrives next morning | sim | shipping.test.ts (ship -> day:rollover payout -> money) |
| Energy drains and refills | sim | time/energy tests (moves/spendEnergy, refill on sleep) |
| Save/reload keeps crops, money, time exactly | sim | persist roundtrip: farmState (crops), wallet, clock |

## M2 — Village and economy: PASS (commit 89816e1)

| Step | Cov | Where |
|------|-----|-------|
| Walk farm -> village through a map transition | sim | warp test (resolveWarp + player:warped between rustleaf-farm and village) |
| Buy seeds and a tool upgrade, sell forage | sim | tests/sim/shop.test.ts (buy/sell money flow; tool upgrade hook) |
| Rain auto-waters crops and is visible | sim+browser | weather.test.ts (rain waters planted tiles); rain particles in engine:view (visual deferred) |
| Season change alters visuals and crops available | sim+browser | growth.ts seasonal gating + view palette/swap; visual deferred |
| A chopped tree regrows | sim | forage/stump regrow test (seed-based respawn) |

## M3 — People: PASS (commit 1c32b36)

| Step | Cov | Where |
|------|-----|-------|
| One NPC in different places at 09:00, 13:00, 19:00 | sim | npc-schedule test: position(map,x,y) from world.clock (tests/view/npcs.test.ts) |
| Dialogue changes with weather and friendship | sim | dialogue-selection test (heart tier + season/weather keys) |
| A gift changes hearts; loved vs hated reactions differ | sim | gift test (+0/+X/+2X/- off hearts, reply text varies) |
| A heart event plays | sim | heart-event test: trigger condition -> cutscene state machine -> hearts turn/flag |
| Accept, finish, turn in a quest; journal reflects it | sim | quest test (accept/objective/complete/turn-in -> journal entries + reward) |
| NPCs never stand on blocked tiles | sim | content validation: schedule rule + home anchor must be walkable per legend |
| Seasonal shop stock + Friday traveling merchant | sim | tests/sim/shop-seasonal.test.ts (open/closed days, seeded 4-item rotation, season gating) |

## ADDENDUM B — Core-loop feel: PASS

| Step | Cov | Where |
|------|-----|-------|
| Successful hoe/axe/water/pick swings land a quick visual + a distinct success blip | sim+browser | engine:view swing anim + particle burst (browser pending); audio `tool:used` success cue (tests/sim/audio.test.ts); success/failure bus split (tests/sim/tool-feedback.test.ts) |
| Failed interactions clearly fail: red hit-flash on the tile only + distinct failure blip, never confused with a success | sim+browser | engine:view failFlash (browser pending); audio `tool:failed` cue (audio.test.ts); failure reasons incl. frozen/exhausted/occupied/nothing (tool-feedback.test.ts) |
| Movement is continuous (hold a key to jog; Shift walks ~60% slower) with 8-way diagonals at the same speed | sim | engine:sim `player:walk` + input layer; tests: tests/view/walk-continuous.test.ts |
| Walls stop movement exactly at the tile edge and are slid along, never walked into or teleported through | sim | walk reducer sub-tile collision sampling; tests: walk-continuous.test.ts (wall block + slide) |
| Walking gives feedback (footstep audio cadence; energy still drains) and still warps through map edges | sim+browser | audio `player:moved` cue; warp on walk; tests: walk-continuous.test.ts (warp + moved events, energy drain) |
| Selling into the shipping bin rings in a coin register | sim+browser | audio `shipping:report` coin cue when sold.length > 0; tests: tests/sim/audio.test.ts |
| Wood-and-parchment UI panels with a pixel font and corner accents | browser | ui-kit revamp (wood bevel + parchment + corner nails, Silkscreen font); visual deferred, CSS only |

## M4 — Life skills (pending)

fish gated by season/time · animal buy/feed/product quality · machine processes ·
buff food changes stats · skill level unlocks recipe + profession at 5/10.

| Step | Cov | Where |
|------|-----|-------|
| XP earned by farming/foraging/mining/fishing/combat actions banks and levels skills 1-10 on a fixed curve | sim (PASS) | tests/sim/skills.test.ts (`skills:grant-xp`: threshold, multi-level chain, level-10 cap + overflow drop) |
| Daily XP counters roll into skills at day close with level-up feedback | sim (PASS) | skills.test.ts (day:summary -> `player:levelup` harvesting the `day:xp:*` counters) |
| Reaching a level unlocks its authored recipes | sim (PASS) | skills.test.ts (`skills:recipes-unlocked` diff at the milestone level; `recipesUnlockedFor` is level/data-driven) |
| Choosing a profession at level 5/10 is one-time and level-gated | sim (PASS) | skills.test.ts (`skills:choose-profession`: below-level reject, valid pick emits `player:profession`, second pick locked) |
| Fishing: 34 content fish gated by season/weather/time, cast/wait/hook | sim (PASS) | tests/sim/fishing.test.ts (water-only cast, no-fish, availableFish gates, bite->catch -> item + `day:xp:fishing`/`day:caught:<itemId>`, reeling waits: reel-cancel, too-slow, inventory-full + day-end escapes, save/load session; farming no-op for rods) |
| Buy an animal, feed it daily, hunger + heart growth, product quality from friendship | sim (PASS) | tests/sim/animals.test.ts (gold/cap/uid buying; fed morning goal + hunger/streak decay and the bond gate; product ready only once hearts >= 2 for a cared herd; quality tiers from happy+bond; feed/pet/deny; collect + reschedule; inventory-full keeps the animal ready; per-species products; sleep AND forced pass-out rollover, idempotent; save/load herd) |
| Machine processes convert inputs over time (keg/preserves/etc.) | sim (PASS) | tests/sim/machines.test.ts (crafted machine placed on free walkable tile; insert one input bundle; 10-min countdown with `machines:finished`; collect output; every `machines:denied` branch incl. occupied/blocked/busy/not-ready; inventory-full keeps the machine loaded+ready; in-flight work survives save) |
| Cooked food applies a timed stat buff when eaten | sim (PASS) | tests/sim/crafting.test.ts (always-known + unlock-gated recipes; atomic craft full-bag/missing-ingredients leaves the bag untouched; eat applies energy/health deltas capped at maxima; buff arming at expiresAt = now + hours and pruning on `time:tick`; non-food/empty-slot denials; active buffs survive save) |
| Crafting menu lists known/locked recipes and crafts from the bag (browser panel: C key, sections, Craft buttons) | browser (deferred — logic PASS) | tests/ui-kit/crafting-ui.test.ts (row split by kind over real content; unlock gating flips with level-up; canCraft flips on short ingredients; have-counts drain after a craft; lock/ingredient/food/buff labels) |
| First-person voxel presentation: F-switch camera + block world over the same sim map (browser polish: placed-object blending, pointer-lock look) | browser (deferred — sim math PASS) | tests/view/voxel.test.ts (voxelColumns: house/tree/water/rim rules on real maps; pose: facing yaw, look vector, pitch clamp, head-bob) |
| Original procedural soundtrack: day/night/season/weather/biome + low-health themes change with context (browser listen — sim logic PASS) | sim (PASS) | tests/sim/music.test.ts (mood/time/weather/season resolution, home/cave/danger overrides, deterministic bars, audible notes in-scale, headless engine) |

## M5 — Mines & combat (pending)

same seed -> same floor · 3 monster types behave differently · death penalty +
respawn · checkpoint every 5 floors · ore feeds tool upgrades · boss beatable.

## M6 — Story & content (pending)

collection unlock · marriage + spouse routine · festival attend · ending reached
(dev-console skip ok) · free play continues.

## M7 — Polish (pending)

30 min continuous play, zero console errors, 60 FPS Medium · full gamepad loop ·
remap a key · colorblind mode · tutorial days 1-3 · music changes by
place/season/time.

## M8 — Balance, QA, release (pending)

2-year bot run no crashes/soft-locks · economy report, no dominant strategy ·
fresh clone builds from README · web zip from static server · desktop launches.

---

## How a result is recorded

At every milestone integration: the orchestrator re-runs the marked sim steps
(the `Where` column entries), records PASS/FAIL on the row, and pastes the row
summary into the milestone status report. `browser` rows get a trailing "(browser
pending)" and do not block the milestone while no browser is available, provided
the equivalent sim coverage exists.
