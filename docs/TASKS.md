# Tasks

The current work item, and the queue behind it.

One task in flight at a time. When it is done, it moves to `DEVELOPMENT_STATUS.md`
with what was implemented, what was tested, and every bug found along the way.

---

## In flight

**None.** M0 is complete; the queue below is next up.

---

## Next

### TASK-001 — Time and calendar service (M2)

**Goal:** a deterministic clock and calendar, with the day/night cycle driven
from it.

**Context:** M2 is the spine of the game. Energy, NPC schedules, shop hours, crop
growth and lighting all hang off the clock, and M3 cannot start until it works.
The model is recovered in `docs/SALVAGED_DESIGN.md` section "Calendar and clock";
read it before writing anything. `EventBus` already declares `time_minute_changed`,
`time_hour_changed`, `day_started`, `day_ended`, `season_changed` and
`year_changed` for this purpose.

**Exact files:**
- `scripts/time/time_service.gd` (new — pure logic, no scene dependency)
- `scripts/time/clock_types.gd` (new — `WorldTime`/`Clock` value types)
- `scripts/world/world_root.gd` (own — instantiate and drive the service)
- `tests/suites/test_time.gd` (new)
- `scenes/ui/hud_time.tscn` + generator (new — clock readout, if M2 scope
  includes UI; otherwise defer to M15 and keep this task logic-only)

**Systems affected:** time, calendar, lighting (M2 day/night), and every
downstream system that will later subscribe to the time signals.

**Acceptance criteria:** the M2 block in `docs/ACCEPTANCE.md`.

**Tests required:** every case in the "Edge cases the old tests pinned down"
list in `docs/SALVAGED_DESIGN.md`. Those are not optional — each one is a bug
that shipped once. In particular:
- 6:00 AM is absolute minute zero
- advancing at midnight rolls the day; advancing just before it does not
- at 2:00 AM the player collapses *and* the day rolls
- advancing past 2:00 AM clamps at the collapse point
- `passed_out`, once set, stays set
- the season rolls on day 29, the year after winter
- `NextDayMorning` works from a late-night clock and does not mutate its input
- a full day of 10-minute ticks advances exactly one day
- `ToGameMinutes` is monotonic across midnight

**Files not to modify:** `scripts/core/event_bus.gd` (signals already exist — if
one is genuinely missing, add it and record the decision), `scripts/world/world_builder.gd`
(its geometry is unrelated to time), and any `tests/suites/` file other than the
new one.

**Verification:** `pwsh -File tools/check.ps1` exits 0 with zero `SCRIPT ERROR`
lines, boot still reaches `PLAYING`, and the new suite passes.

---

## Queue

In rough dependency order. Each becomes its own TASK-nnn entry with a full
specification when it is picked up, not now.

| # | Milestone | Notes |
|---|---|---|
| TASK-002 | New-game menu and title screen | M1. Straightforward; needed before save/load is reachable |
| TASK-003 | Save system, versioned | M1/M16. `SAVE_VERSION` from the start |
| TASK-004 | Farming grid and soil state | M3. Depends on TASK-001 |
| TASK-005 | Crop resources and growth | M3 |
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