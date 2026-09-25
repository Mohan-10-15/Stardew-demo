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

## M3 — People: PASS (commit cfe48de + M3 follow-ups)

| Step | Cov | Where |
|------|-----|-------|
| One NPC in different places at 09:00, 13:00, 19:00 | sim | npc-schedule test: position(map,x,y) from world.clock (tests/view/npcs.test.ts) |
| Dialogue changes with weather and friendship | sim | dialogue-selection test (heart tier + season/weather keys) |
| A gift changes hearts; loved vs hated reactions differ | sim | gift test (+0/+X/+2X/- off hearts, reply text varies) |
| A heart event plays | sim | heart-event test: trigger condition -> cutscene state machine -> hearts turn/flag |
| Accept, finish, turn in a quest; journal reflects it | sim | quest test (accept/objective/complete/turn-in -> journal entries + reward) |
| NPCs never stand on blocked tiles | sim | content validation: schedule rule + home anchor must be walkable per legend |
| Seasonal shop stock + Friday traveling merchant | sim | tests/sim/shop-seasonal.test.ts (open/closed days, seeded 4-item rotation, season gating) |

## M4 — Life skills (pending)

fish gated by season/time · animal buy/feed/product quality · machine processes ·
buff food changes stats · skill level unlocks recipe + profession at 5/10.

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