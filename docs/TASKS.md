# Tasks

The current work item, and the queue behind it.

One task in flight at a time. When it is done, it moves to `DEVELOPMENT_STATUS.md`
with what was implemented, what was tested, and every bug found along the way.

---

## In flight

**None.** Groups 12–13 are complete (M4 closed); the queue below is next up.

---

## Recently completed

### TASK-003 — Player state, stamina and economy (group 13) — COMPLETE

Lifted `Inventory`, `Hotbar` and the new `Stamina` and `Wallet` out of
`FarmService` into `PlayerStateService`, so farming and trading share one owner
instead of each having one. Added data-driven `ShopDefinition` content behind
`ShopRegistry`, `EconomyService` rules that refuse atomically with a
machine-readable reason, and a `Shop` counter placed by `WorldBuilder` that the
real interact key opens.

27 new cases in `tests/suites/test_economy.gd`; **229/229 green** with zero
script errors.

Six real defects found and fixed, all recorded in `DEVELOPMENT_STATUS.md`. The one
worth remembering: stamina was charged *after* the tool was applied, so a tired
player tilled for free — affordability is now a preflight.

### TASK-002 — Farming grid, crops and tools (groups 7–11) — COMPLETE

Till, plant, water, sleep, grow, harvest, with `FarmService` as the rules layer and
success/failure published as separate `EventBus` events.

### TASK-001 — Time and calendar service (M2) — COMPLETE

Delivered as `scripts/time/world_time.gd` (the calendar as a value),
`scripts/time/clock.gd` (pure arithmetic), `scripts/time/time_service.gd` (the
only thing that knows real seconds exist), `scripts/world/day_night_cycle.gd`
(sun and sky, driven from `EventBus` and holding no reference to the service),
and the corner clock readout. The originally-specified `clock_types.gd` was
split into two files instead, so the data type and the arithmetic on it can be
read separately.

27 test cases. `docs/DECISIONS.md` D13 records the three places the recovered
design in `SALVAGED_DESIGN.md` was deliberately diverged from — the day
boundary, the unit of `to_game_minutes`, and the scope of its monotonicity
requirement.

---

## Next

### TASK-002 — Farming grid and soil state (M3)

**Goal:** a tilled-soil grid the player can hoe, plant and water, with crop growth
resolved against the clock.

**Context:** M3 is the first system that consumes the clock rather than producing
it. The end-of-day moment is unambiguous: `TimeService` publishes `day_ended` and
`day_started` exactly once per day, and the day boundary is the 2:00 AM collapse
(D13), so growth is resolved in one place on `day_started` rather than being
pollled from every tile.

`WorldTime` already carries `weather` and `forecast`, so watering rules and
rain-based watering have somewhere to read from without changing the save format
again.

**Systems affected:** farming, interaction (hoe/seed/water actions), time
(`day_started` / `day_ended`).

**Acceptance criteria:** the M2+M3 rows in `docs/ACCEPTANCE.md` that describe
planting, watering and growth.

**Per `AGENTS.md`:** every farming action must publish a clearly distinct success
event *and* a clearly distinct failure event. Planting a seed and failing to
plant must not look or sound the same, and neither may look or sound like
harvesting.

**Verification:** `powershell -NoProfile -ExecutionPolicy Bypass -File
tools/check.ps1` exits 0, at least one test drives hoe → plant → water → sleep
through real input and asserts the resulting tile and crop state, and the whole
sequence survives save → reload.

---

## Queue

In rough dependency order. Each becomes its own TASK-nnn entry with a full
specification when it is picked up, not now.

| # | Milestone | Notes |
|---|---|---|
| TASK-003 | Farming grid and soil state | M3. Next up. Depends on TASK-001, now done |
| TASK-004 | Crop resources and growth | M3 |
| TASK-005 | New-game menu and title screen | M1. Straightforward; needed before save/load is reachable |
| TASK-006 | Save system, versioned | M1/M16. `SAVE_VERSION` from the start |
| TASK-006 | Inventory with quality tiers | M4. Slot splitting, lowest-quality-first removal |
| TASK-007 | Tools and stamina | M4 |
| TASK-008 | Economy, shop, currency | M4 |
| TASK-009 | NPC entities and schedules | M5 |
| TASK-010 | Dialogue system | M5 |
| TASK-011 | Relationships and gifting | M5 |
| TASK-012 | Quests | M6 |
| TASK-013 | Fishing | M7 |
| TASK-014 | Animals | M7 |
| TASK-015 | Crafting and cooking | M7 |
| TASK-016 | Mines | M8 |
| TASK-017 | Combat and boss | M8 |
| TASK-018 | Weather | M9 |
| TASK-019 | Seasons and visuals | M9 |
| TASK-020 | Cutscene system | M10. Spec in `docs/CUTSCENE_GUIDE.md` |
| TASK-021 | Buildings and upgrades | M11 |
| TASK-022 | Festivals | M12 |
| TASK-023 | Story progression | M13 |
| TASK-024 | Audio manager and music | M14 |
| TASK-025 | UI and accessibility | M15 |
| TASK-026 | Art and animation polish | M17 |
| TASK-027 | Performance | M18 |
| TASK-028 | Bot simulation and balance | M19 |
| TASK-029 | Release integration | M20 |

The ordering is a dependency order, not a difficulty order. Fishing is harder
than the menus, and it is later only because a fish needs a time of day and
weather to bite.

---

## Housekeeping

**When a task is done:** run `check.ps1` (green, with a real pass count), update
`DEVELOPMENT_STATUS.md`, update `docs/DECISIONS.md` if a decision was made, and
commit. Only the orchestrator commits.

**When something does not work:** record the exact error, file, line, root cause,
and why the test suite did not catch it. A bug found this way is worth more than
one that was never found.

**When a task is blocked:** say so explicitly and say what it is blocked on. Do
not mark a partial result complete.