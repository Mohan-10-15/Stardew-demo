# Roadmap

Milestones, in order. Each one ships playable and tested before the next starts.

`docs/TASKS.md` holds the current work item. `docs/ACCEPTANCE.md` holds what each
milestone must do before it counts as done. This file is the sequence and the
reasoning.

---

## Status

| Milestone | Name | Status |
|---|---|---|
| M0 | Stabilize existing project | **COMPLETE** |
| M1 | Core player, world, interaction | NEXT |
| M2 | Time and calendar | |
| M3 | Farming | |
| M4 | Inventory, tools, economy | |
| M5 | NPCs, dialogue, relationships | |
| M6 | Quests | |
| M7 | Fishing, animals, crafting, cooking | |
| M8 | Mines and combat | |
| M9 | Weather and seasons | |
| M10 | Cutscene system | |
| M11 | Buildings and farm upgrades | |
| M12 | Festivals | |
| M13 | Story progression | |
| M14 | Audio | |
| M15 | UI and accessibility | |
| M16 | Save and load | |
| M17 | Art and animation polish | |
| M18 | Performance | |
| M19 | Testing, bot simulation, balance | |
| M20 | Release integration | |

### Two numbering schemes, one sequence

`DEVELOPMENT_STATUS.md` tracks **groups** (0–32), which predate this roadmap and
go two or three milestones at a time — a group is a batch of related work.
This file tracks **milestones**, which are the acceptance-test units.

They are not the same axis and the mapping is not 1:1. Where a group covers
several milestones, the milestone list is the one that decides when a feature is
*done*; the group list decides how the work was *batched*. Groups 0–4 map to
M0 and part of M1; group 5 (time and ambience) is M2.

---

## The milestones

### M0 — Stabilize existing project
**Status: COMPLETE.** Import clean, 99/99 tests at the time, boot reaches
`PLAYING`, and the pond basin defect found during the audit is fixed with
regression coverage. The suite is now 126 cases, having grown with each
milestone.

The point of M0 is that everything after it assumes a working baseline. Three
groups of green tests had hidden a pond the player could walk over without anyone
noticing; a milestone that cannot be trusted to be green is not a foundation.

### M1 — Core player, world, interaction
Finish the loop that already half-exists: a real new-game menu, enter the world,
move, look, jump, interact, save, reload with state intact.

The interaction system and both cameras are done. What is missing is the frame
around them — a title screen, a save system, and world content worth walking in.

### M2 — Time and calendar
A deterministic clock, the day/night cycle, and the calendar.

This is the spine of the whole game: energy, schedules, shop hours, crop growth
and lighting all hang off it. `docs/SALVAGED_DESIGN.md` holds the recovered
model, including a rollover bug that shipped in the Unity build and a monotonicity
requirement that exists specifically to stop it recurring.

Everything in M3 depends on this. Farming without a clock is a demo.

**Status: complete.** Delivered as `WorldTime` + `Clock` (pure arithmetic),
`TimeService` (the only thing that knows real seconds exist), `DayNightCycle`
(sun and sky driven from `EventBus`, holding no reference to the service), and
the corner clock readout. 27 test cases cover the recovered edge cases plus the
ones found while building it. Three rules in `SALVAGED_DESIGN.md` were
deliberately diverged from; the reasoning is in `DECISIONS.md` D13 and the
salvaged doc is annotated where it was superseded.

The day rolls at the 2:00 AM collapse rather than at midnight, so M3's sleep and
crop-growth code has one unambiguous end-of-day moment to hook into.

### M3 — Farming
Tilled soil, planting, watering, growth over days, harvesting.

Per `AGENTS.md`, every interact-style action publishes a *clearly distinct*
success event and a *clearly distinct* failure event. Farming is on that list.
Planting a seed and failing to plant must not look or sound the same.

### M4 — Inventory, tools, economy
Stacking with quality tiers, slot splitting, tools with stamina costs, shops,
buying and selling, currency.

`docs/SALVAGED_DESIGN.md` records the inventory edge cases the old build pinned
down — merging never across quality, overflow splitting rather than failing,
removal taking lowest-quality-first, all-or-nothing on a full bag. Each was a
real bug once.

### M5 — NPCs, dialogue, relationships
Twelve people, schedules that respond to time and weather, branching dialogue,
gifts, friendship and romance.

Schedule determinism matters more than it sounds: an NPC that is in two places
at once, or nowhere, reads as broken instantly.

### M6 — Quests
Acceptance, tracked objectives, completion, rewards, and persistence.

No quest may be completable without doing its objectives.

### M7 — Fishing, animals, crafting, cooking
Four interlocking systems: the timed minigame, husbandry with feed cycles, timed
machines, and recipes that combine ingredients.

### M8 — Mines and combat
Descent, procedural floors, enemies with distinct AI, a boss, and death and
respawn that does not corrupt the save.

### M9 — Weather and seasons
Weather that *affects gameplay* (rain waters crops, winter kills them), seasonal
visuals, seasonal crops, seasonal fish, weather-weighted days.

### M10 — Cutscene system
The `CutsceneDirector`, the data-driven event vocabulary, and state restoration.
See `docs/CUTSCENE_GUIDE.md` for the full specification.

### M11 — Buildings and farm upgrades
Buyable, placeable, usable buildings, and upgrades with real effects.

### M12 — Festivals
Seasonal events in the physical 3D world, with consequences for attending or
skipping.

### M13 — Story progression
The Heartstone spine through to its ending, then free play continuing after the
credits.

### M14 — Audio
`AudioManager`, music per region and time of day, ambience, SFX for every action,
volume settings.

### M15 — UI and accessibility
Every screen keyboard-reachable and dismissible, input rebinding, text scaling,
and no information carried by colour alone.

### M16 — Save and load
Versioned saves with a migration path, covering the complete state. The version
constant is `SAVE_VERSION`.

### M17 — Art and animation polish
First-person tool animations, interactable reactions, no placeholder geometry in
normal play.

### M18 — Performance
60 FPS on target hardware, no frame spikes, no unbounded memory growth.

### M19 — Testing, bot simulation, balance
A 2-year (112-day × 2) headless simulation that completes without crash or
soft-lock, plus economy tuning so progression is neither trivial nor grindy.

### M20 — Release integration
A fresh clone builds from the README alone, Windows and web exports run, no debug
cheats reachable, all assets traced.

---

## Constraints that apply to every milestone

- **Preserve what works.** Do not rewrite a working system to make a task easier.
  Do not delete a test because it fails.
- **Do not weaken assertions to make a suite pass.** Establish whether the code or
  the test is wrong, and record which.
- **No fake implementations.** No placeholder buttons, no "coming soon", no empty
  methods, no UI that only looks functional, no developer cheats required for
  normal progression.
- **A milestone is complete when it is playable and tested**, not when its scripts
  exist.
- **Every meaningful milestone runs `check.ps1`, updates the docs and the status
  file, and commits.**