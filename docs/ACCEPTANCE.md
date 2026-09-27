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

## ADDENDUM B — Core-loop feel: PASS, VERIFIED IN A REAL BROWSER

A browser is now available (Playwright + Chromium), so the `browser`-marked steps
below were run against the real game instead of being deferred. The harness is
`npx vite-node scripts/observe.ts`; the transcript of the run that produced the
numbers below is `artifacts/observe-transcript.txt`. Three consecutive runs gave
identical verdicts.

| Step | Cov | Where |
|------|-----|-------|
| Successful hoe/axe/water/pick swings land a quick visual + a distinct success cue | sim+browser | browser: `tool:used` emitted, `swinging=true`, 12 particles during the swing, tilled tile created. Cue recorder logged `tool:success` (494Hz→587 square + 587Hz→784 square). Unit: tests/sim/tool-feedback.test.ts, tests/ui-kit/sfx-cues.test.ts |
| Failed interactions clearly fail: red hit-flash on the tile only + distinct failure cue, never confused with a success | sim+browser | browser: `tool:failed` reason `not-tillable`, `failFlash=true`, `swinging=false`, 0 particles, world unchanged. Cue recorder logged `tool:failure` (233Hz→175 sawtooth) — a *different* cue from success, not the same sound twice |
| Movement is continuous with diagonals at full per-axis speed | sim+browser | browser: per-axis rate vs a single-axis reference = **A 1.00, B 1.00**. Unit: tests/view/diagonal-speed.test.ts, tests/view/walk-continuous.test.ts |
| Shift walks slower than jogging | sim+browser | browser: per-frame step 0.4 (jog) vs 0.21 (shift) — measured per frame, not per second |
| Walls stop movement exactly at the tile edge and are slid along | sim+browser | browser: 8% of moving frames ended on a partial `MAX_STEP` sub-step, i.e. the sampler engaging, not a stutter. Unit: diagonal-speed.test.ts (3 wall-slide cases) |
| Walking gives feedback and still warps through map edges | sim+browser | `player:footstep` cue on movement; energy 270 → 269.90 over one walk. Unit: walk-continuous.test.ts |
| Selling into the shipping bin rings in a coin register | sim | `shipping:report` → `sale:coin`. Unit: tests/sim/audio.test.ts |
| Minecraft-like voxel presentation, first person by default | browser | 424 meshes, **424/424 `BoxGeometry`**, 526/527 materials `flatShading:true`, every texture 16×16 with `NearestFilter`, 11 draw calls, 9060 triangles, 0 console errors. Palette measured from a compositor screenshot: 8 dominant colours, all greens `rgb(44,68,26)`…`rgb(93,102,48)` plus sky/water `rgb(142,166,170)`. Unit: tests/view/voxel.test.ts, tests/view/blocks.test.ts |
| The camera and the thing you act on can never disagree | browser | camera direction vs the world direction `facing` implies, all four directions: `w` dot 0.991, `d` 0.999, `s` 0.999, `a` 1.000. Works with no pointer lock at all. Unit: tests/view/look.test.ts, tests/view/face-action.test.ts |
| The reticle is on the tile the tool will hit | browser | reticle is projected onto the target every frame and hidden when the target leaves frame, because with one-tile reach the screen centre is ~1.5 tiles ahead and would promise the wrong tile |
| `V` toggles first-person / top-down; the reticle hides in top-down | browser | `firstPerson` true→false→true, reticle hidden in top-down, world still renders in both |
| Pixel UI: hard-edged panels, procedural 16×16 item icons, one font | browser | Silkscreen loaded, 24 `eh-` classes present, no HUD/panel overlap, 1 journal tab, no leaked dialogs |
| One AudioContext, created on a real gesture | browser | 1 context, state `running`, `sfx` bus |

### How the audio verdicts were made honest

The first version of this script counted every oscillator the game created and
reported `success-audio=YES (27 notes)` / `fail-audio=YES (32 notes)`. **Those
verdicts were worthless and have been replaced.** The procedural soundtrack
synthesises continuously, so a window in which the game played no cue at all
still contains music notes — the count was measuring the soundtrack, and it
would have passed even with the failure sound deleted.

The audio lane now records each SFX at the one point all of them pass through
(`AudioEngine.play(cue, specs)`, which the music path never touches), keyed by
cue name. The script asserts the cue *name*, and includes the falsifying
control: a 4s idle window logs **0 SFX cues while 12 music bars / 96 notes /
10–19 oscillators are still scheduled**. That is the evidence that a cue count
means something.

### Measurement rules this environment forces

There is no GPU here: the renderer reports `ANGLE (Google, Vulkan 1.3.0
(SwiftShader Device (Subzero)), SwiftShader driver)` and runs at 2–11fps, and
the frame delta is clamped. Three plausible-looking speed measurements were
wrong before the right one was found, and the reasons are recorded so the next
person does not repeat them:

- **wall-clock tiles/sec is noise.** A 2s hold sampled 5883ms; identical code
  measured 0.816 and 2.607 tiles/sec, and shift-vs-jog read 0.74 then 1.21.
- **displacement per rendered frame is noise.** A hold that clips a wall reports
  a nonsense average — one diagonal test read 0.63 purely because the
  single-axis reference had only 4 unobstructed frames.
- **summing the unit direction vector is worse than useless.** It is 1.0 by
  construction and would "confirm" a fix that never happened.

What the script uses instead: tap the store's `dispatch`, read the player
position either side of each real `player:walk`, and divide the distance the sim
**actually** moved by the time it was **commanded** to move, per axis. That is
collision-independent and frame-rate independent, and it is what turned the
diagonal verdict from 0.71 to 1.00. Measurement starts from a tile with five
verified-open tiles ahead on both axes, and the verdict reports INCONCLUSIVE
rather than a number when the reference is obstructed.

**Frame rate here says nothing about real performance.** 9060 triangles in 11
draw calls is trivial for any GPU; the 2–11fps is the CPU rasteriser, not the
scene.


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
| First-person voxel presentation: `V` camera toggle + block world over the same sim map, camera locked to the interaction target | sim+browser | browser: 424/424 BoxGeometry, flat-shaded, 16×16 nearest textures; camera dot vs facing 0.991–1.000 on all four directions with no pointer lock; reticle projected onto the real target. Unit: tests/view/voxel.test.ts, tests/view/look.test.ts, tests/view/face-action.test.ts, tests/view/blocks.test.ts |
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
