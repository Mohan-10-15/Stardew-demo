# Acceptance Tests

What each milestone must actually do before it counts as done. These are
playable behaviours, not unit tests — a milestone is complete when a player can
do the thing through normal play with no developer cheats.

Milestone names and numbering come from `prompt.md` §32 and match
`docs/ROADMAP.md` exactly. If a number here and a number there ever disagree
again, `prompt.md` wins and both get changed.

Unit and integration coverage lives in `tests/suites/`; run it with
`powershell -NoProfile -ExecutionPolicy Bypass -File tools/check.ps1`.

**Rule:** do not weaken an acceptance criterion to make a milestone pass. If a
criterion is wrong, change it here and say why in `docs/DECISIONS.md`.

---

## M0 — Stabilize existing project

- [x] Project imports with zero parse/compile errors
- [x] Game boots headlessly and reaches `PLAYING`
- [x] Player moves, jumps, and does not fall through the world
- [x] Camera switches between first and third person without teleporting the player
- [x] Crosshair interaction focuses a prop and performs it
- [x] Existing player/world/camera/interaction systems pass their tests

Verified: `check.ps1` — import OK, **126/126 tests**, boot OK. (99 at the time of
the M0 audit; the suite has grown with each milestone since.)

The Group 4B pond fix also landed here: the ground had no basin, so the player
walked on dry land over the water and the water was hidden under the grass.
Fixed and covered by `tests/suites/test_world_geometry.gd`.

---

## M1 — Core player, world, interaction

- [ ] New game starts from a menu, not straight into the world
- [ ] Move with WASD, look with the mouse, jump
- [ ] Interact with a prop; hold interactions progress visibly
- [ ] Save, quit, reload: position, world state and inventory are intact
- [ ] Save files are versioned, and an older version migrates forward

Blocked on M16 for the save system; the play-and-interact half can be signed off
independently.

---

## M2 — Time and calendar

- [x] The clock runs in real time and the valley's light tracks it
- [x] A full day of 10-minute ticks advances exactly one day
- [x] Advancing at 2:00 AM passes the player out and rolls the day
- [x] The season rolls after day 28; the year rolls after winter
- [x] The clock is monotonic within a day (no double-rollover)
- [x] The date and time are readable in-game, not only through a debugger

Verified: `tests/suites/test_time.gd` (27 cases) plus the corner HUD read through
the real `Panel/Column/TimeLabel` node by `tools/playtest_schedule.gd`.

The rollover and monotonicity criteria are the ones the retired Unity build
actually broke; they are enumerated in `docs/SALVAGED_DESIGN.md` section
"Edge cases the old tests pinned down". They are not optional.

Note that the day boundary is the 2:00 AM collapse and **not** midnight — see
`DECISIONS.md` D13. The salvaged design said both, which cannot both be true.
`SALVAGED_DESIGN.md` is annotated at the point of divergence rather than edited
to match the code, so the original reasoning is still readable.

---

## M3 — Farming

The loop runs through the clock, which is why these rows and M2's used to share
a section. They are separate milestones: M2 proves the clock, M3 proves
something that consumes it.

- [ ] Hoe a tile → it becomes tilled soil
- [ ] Plant a seed on tilled soil → a crop exists on that tile
- [ ] Water the crop → it is marked watered
- [ ] Sleep → the day advances, the crop grows, weather is re-rolled
- [ ] Harvest a mature crop → items enter the inventory
- [ ] Sell the harvest → currency increases

Delivered in groups 7–11 and reachable end to end from a new game through the
real `interact` key; the rows above are worded for a player, so they are signed
off by playing rather than by counting tests.

Per `AGENTS.md`, every one of these publishes a *clearly distinct* success event
and a *clearly distinct* failure event, and no two of them may look or sound the
same as each other either.

---

## M4 — Inventory, tools, economy

- [x] The farm is reachable, and so is the village shop
- [x] Buy seeds with currency; currency decreases by the right amount
- [x] An inventory stack splits across slots when it overflows
- [x] A full bag accepts nothing and loses nothing (all-or-nothing)
- [x] Removing an item takes the lowest quality first
- [x] Removing empties the slot rather than leaving a zero-count ghost
- [x] Selling updates currency and publishes `item_sold`

### Stamina

- [x] A tool swing costs the stamina on its `ItemDefinition`
- [x] A swing the player cannot afford changes no tile at all
- [x] A swing that changes nothing is refunded
- [x] Sleeping restores stamina to full
- [ ] A HUD bar draws the stamina pool (group 25)

### Currency

- [x] A new game starts with gold, and it survives save → reload
- [x] A wallet never goes negative
- [x] A refused trade moves neither gold nor items
- [x] A shop will not buy back its own stock (no free-money loop)
- [ ] A HUD shows the gold total (group 25)

---

## M5 — NPCs and dialogue

`prompt.md` §16 sets the floor at **at least 12 original NPCs**, each with name,
appearance, home, occupation, schedule, season schedule, weather schedule,
dialogue, gift tastes, friendship, birthday and story role.

- [ ] At least 12 NPCs exist, and each has every field §16 lists
- [ ] NPC schedules change with the time of day, the weather and the season
- [ ] NPCs move through the actual world by pathfinding
- [ ] NPCs do not teleport between locations except at a scripted story event
- [x] Dialogue advances through a real conversation tree
- [x] An NPC says different things on different days
- [x] Dialogue opens from the same interact prompt that already carries gifting

Schedules are **done** for the six villagers that ship (group 16), pinned by
`every_block_is_reachable_in_its_own_time`; the conversation is **done** as
well (TASK-008, 32 cases in `tests/suites/test_dialogue.gd`), so an NPC can be
spoken to, answers from a scored selection over day, weather, season and bond,
and remembers what it has already said. **Six more villagers are not** — the
twelve `prompt.md` §16 asks for is the open half of this milestone.

Relationship values, gift tastes actually being read, romance and marriage are
M6 — `prompt.md` §32 splits "relationships" out of this milestone on purpose.

---

## M6 — Quests and relationships

### Quests

- [x] A quest can be accepted
- [x] Objective progress updates as the player does the thing
- [x] A quest can be completed, and its reward is granted
- [x] Quest state persists across save and reload
- [x] No quest can be completed without doing its objectives

Verified in `tests/suites/test_quest.gd` (46 cases), `tests/suites/test_ui.gd`
(5 tracker cases) and `tools/playtest_quest.gd`. The persistence line means
`QuestService.to_dict()` / `from_dict()` round-trip, not the aggregate save file,
which is milestone M16 and does not exist yet.

### Relationships

- [ ] Gifting an item the NPC likes raises the relationship
- [ ] Gifting a disliked item lowers it
- [ ] A relationship value exists, is readable in-game, and survives save and reload
- [ ] Friendship gates something the player wants (dialogue, gifts, quests)
- [ ] Romance and marriage work as a relationship path
- [ ] A spouse appears in the world and follows a schedule

Gift tastes are already authored on `NpcData`; nothing reads them yet. This
milestone is **half** done and must not be reported as complete on the strength
of the quest list above.

---

## M7 — Fishing, animals, machines, cooking

- [ ] Fishing works: cast, wait for a bite, hook, land a fish
- [ ] An animal works: buy, place, feed, and collect its product
- [ ] A machine works: place, load input, wait, collect output
- [ ] Cooking works: combine ingredients at a station, get a dish
- [ ] Every one of the above has distinct success and failure feedback

---

## M8 — Mines and combat

- [ ] A mine can be entered and descended
- [ ] Combat works: attack, damage, defeat an enemy
- [ ] A boss can be fought and defeated
- [ ] Combat success and failure sound and look distinct
- [ ] The player can die and respawn without losing save integrity

---

## M9 — Weather and seasons

- [ ] Weather affects gameplay, not just visuals (rain waters crops, winter kills them)
- [ ] The season changes visuals, available crops and weather weights
- [ ] Weather and the forecast survive a day rollover
- [ ] A weather change is announced, not silent

---

## M10 — Cutscene / cinematic system

- [ ] A cutscene plays in the 3D world
- [ ] The player can skip it
- [ ] Camera, input and player control all restore correctly afterwards
- [ ] Skipping mid-cutscene does not leave the world in a broken state

---

## M11 — Buildings and farm upgrades

- [ ] Buildings can be bought and placed
- [ ] A placed building is usable, not decorative
- [ ] Upgrades have a real effect

---

## M12 — Festivals

- [ ] A festival happens in the physical 3D world, not a separate scene
- [ ] Attending or skipping a festival has consequences
- [ ] A schedule defers to a festival day instead of running normally

---

## M13 — Story progression

- [ ] Main progression reaches its ending
- [ ] The ending completes, and free play continues afterwards

---

## M14 — Audio

- [ ] Every major action has audio: footsteps, tools, impacts, UI, ambience
- [ ] Music and ambience change with time of day and weather
- [ ] Volume settings work and persist
- [ ] Audio is muted correctly on pause

---

## M15 — UI and accessibility

- [ ] Every screen is reachable and dismissible by keyboard alone
- [ ] No screen traps the player
- [ ] Rebinding input works end to end, with the HUD reflecting it
- [ ] Text scales without clipping
- [ ] Colour is never the only channel carrying information

---

## M16 — Save and load

- [ ] Save/reload preserves the complete state: world, farm grid, inventory,
      time, relationships, quests, unlocks
- [ ] Saves from a previous `SAVE_VERSION` migrate forward
- [ ] A corrupt save fails loudly rather than silently discarding progress

---

## M17 — Art and animation polish

- [ ] First-person tool animations exist for every tool
- [ ] Every interactable has a use animation and a reaction
- [ ] No placeholder geometry remains in normal play
- [ ] Missing or invalid assets cannot crash the game

---

## M18 — Performance

- [ ] 60 FPS at the target resolution on target hardware
- [ ] No frame spikes when moving through world boundaries
- [ ] Memory does not grow unbounded over a long session

---

## M19 — Testing and balance

- [ ] A 2-year bot simulation (112 days × 2) completes without crash or soft-lock
- [ ] The economy holds up: the player can afford to progress and cannot idle to infinite money
- [ ] No unbounded growth or decay in any resource

---

## M20 — Release integration

- [ ] A fresh clone builds and runs from the README instructions alone
- [ ] Windows export runs on a clean machine
- [ ] Web export loads and is playable
- [ ] No debug cheats are reachable in a release build
- [ ] Every shipped asset is traced in `docs/ASSET_LICENSES.md`
