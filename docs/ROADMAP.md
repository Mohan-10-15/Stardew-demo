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
| M1 | Core player, world, interaction | **COMPLETE** |
| M2 | Time and calendar | **COMPLETE** |
| M3 | Farming | **COMPLETE** |
| M4 | Inventory, tools, economy | **COMPLETE** |
| M5 | NPCs, dialogue | dialogue **COMPLETE**; six villagers open |
| M6 | Quests, relationships | quests **COMPLETE**; relationships open |
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

Milestone names and numbering come from `prompt.md` §32 and are authoritative;
`docs/ACCEPTANCE.md` is keyed to the same scheme. Where a name here and a name
there once disagreed, `prompt.md` won and both were changed.

They are not the same axis and the mapping is not 1:1. Where a group covers
several milestones, the milestone list is the one that decides when a feature is
*done*; the group list decides how the work was *batched*. Groups 0–4 map to
M0 and part of M1; group 5 (time and ambience) is M2.

---

## The milestones

### M0 — Stabilize existing project
**Status: COMPLETE.** Import clean, 99/99 tests at the time, boot reaches
`PLAYING`, and the pond basin defect found during the audit is fixed with
regression coverage. The suite is now 476 cases, having grown with each
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

### M3 — Farming — COMPLETE
Tilled soil, planting, watering, growth over days, harvesting.

Per `AGENTS.md`, every interact-style action publishes a *clearly distinct*
success event and a *clearly distinct* failure event. Farming is on that list.
Planting a seed and failing to plant must not look or sound the same.

Delivered in groups 7–11. Playable end to end from a new game through the real
`interact` key: hoe, seed packet, watering can, sleep, harvest.

One ordering rule this milestone taught, worth carrying to every later action that
mutates world state and then hands something to a container: **settle storage
before you commit the change.** Harvesting first and re-planting on failure
published a success event for a harvest that never happened, and silently reset a
regrowing crop's clock. Check what can be accepted first; do not rely on undo.

### M4 — Inventory, tools, economy — COMPLETE
Stacking with quality tiers, slot splitting, tools with stamina costs, shops,
buying and selling, currency.

All three parts are done (groups 10–11 and 13):

- **Inventory and tools** (groups 10–11): quality-aware merging, overflow
  splitting, all-or-nothing adds, lowest-quality-first removal, refuse-to-shrink,
  and per-stack tool durability.
- **Stamina** (group 13): `Stamina` as a plain resource, costs on
  `ItemDefinition.stamina_cost`, affordability checked *before* a swing touches the
  soil, a no-op swing refunded, and a full restore on sleep.
- **Economy** (group 13): `Wallet`, `ShopDefinition` content resources behind a
  registry, `EconomyService` rules with a machine-readable refusal reason on every
  rejection, and a walk-up counter in the world that the real interact key opens.

Deliberately still out: the shop UI, a shipping bin, and daily price variation.

`docs/SALVAGED_DESIGN.md` records the inventory edge cases the old build pinned
down — merging never across quality, overflow splitting rather than failing,
removal taking lowest-quality-first, all-or-nothing on a full bag. Each was a
real bug once.

### M5 — NPCs, dialogue
Twelve original NPCs, schedules that respond to time, weather, season, festival
and quest state, and branching dialogue.

`prompt.md` §16 sets the floor at **at least 12**; six ship today
(`bram`, `fen`, `halda`, `mira`, `odette`, `sable`), so this milestone is not
approached yet on population alone.

Schedule determinism matters more than it sounds: an NPC that is in two places
at once, or nowhere, reads as broken instantly. The schedule half is **done**
(group 16): six authored days, resolved from clock, season and weather, walked
rather than teleported, and pinned by
`every_block_is_reachable_in_its_own_time`. Friendship and romance are
deliberately *not* in this milestone — `prompt.md` §32 puts them in M6, so the
two halves of a villager are split across the boundary on purpose.

**Status: open.** Schedules and the conversation are done (group 16 and
TASK-008 respectively — the panel, the service, six trees and 32 cases in
`tests/suites/test_dialogue.gd`); the missing six villagers are not. Population
is the whole of what is left.

### M6 — Quests, relationships — quests COMPLETE, relationships open
Acceptance, tracked objectives, completion, rewards, persistence — and the
relationship layer: gifts that like and dislike differently, friendship that
rises and falls, romance and marriage.

No quest may be completable without doing its objectives.

What exists: `collect`, `deliver` and `talk` objectives as data; five quests; a
`QuestService` with no quest id in it; a corner tracker showing up to four active jobs
with live `current/required` and a `ready` mark; quest work in the existing villager
interaction chain; gold, item and friendship rewards; distinct success and failure
events for both accepting and handing in; and per-service save/restore.

What does not yet exist, and is deliberately not stubbed: a quest journal page with
turned-in history, `!` / `?` markers over villagers with work, the aggregate
save file that would carry quest state between sessions (M16), and the whole
relationships half — gift tastes are authored on `NpcData` but nothing reads
them, friendship has no value, and romance has no path.

Because the milestone covers both halves, **M6 is not complete when the quest
list above is** — it is complete when the M6 rows in `docs/ACCEPTANCE.md` are
all ticked.

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