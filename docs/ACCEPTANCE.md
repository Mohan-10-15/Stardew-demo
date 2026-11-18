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

- [x] New game starts from a menu, not straight into the world
- [x] Move with WASD, look with the mouse, jump
- [x] Interact with a prop; hold interactions progress visibly
- [x] Save, quit, reload: position, world state and inventory are intact
- [x] Save files are versioned, and an older version migrates forward

The generated title screen opens on a paused world with New Game and Continue;
Continue is disabled until a save exists. New Game deletes the old save and
reloads straight into play. The aggregate save (M16) carries the player's world
position as well as the bag, purse, stamina, world time and farm grid. Verified
by `tests/suites/test_title.gd`, `tests/suites/test_save.gd` and the
`tools/playtest_title.gd` / `tools/playtest_save.gd` real-window runs.

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

- [x] At least 12 NPCs exist, and each has every field §16 lists
- [x] NPC schedules change with the time of day, the weather and the season
- [x] NPCs move through the actual world by pathfinding
- [x] NPCs do not teleport between locations except at a scripted story event
- [x] Dialogue advances through a real conversation tree
- [x] An NPC says different things on different days
- [x] Dialogue opens from the same interact prompt that already carries gifting

All twelve villagers ship. Each has a home, wander radius, three disjoint gift
lists, a birthday, a CC0 body, a signature prop, an original anime face, an
authored day, a dialogue tree and a spouse day. Schedules are pinned by
`every_block_is_reachable_in_its_own_time`; conversations are scored over day,
weather, season and bond and remembered per save (TASK-008). Walking is real
pathfinding over the navigation grid, and the only teleport is the deliberate
day-rollover placement home. **`prompt.md` §16 is met. M5 is complete.**

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

- [x] Gifting an item the NPC likes raises the relationship
- [x] Gifting a disliked item lowers it
- [x] A relationship value exists, is readable in-game, and survives save and reload
- [x] Friendship gates something the player wants (dialogue, gifts, quests)
- [x] Romance and marriage work as a relationship path
- [x] A spouse appears in the world and follows a schedule

Verified in `tests/suites/test_friendship.gd` (27 cases), the strengthened
schedule and quest content checks, and `tools/playtest_friendship.gd` (real
window, real keys, six screenshots). The panel shows every tier and heart count;
a proposal moves the villager to the authored `farm_home` and switches them to
their `<id>_spouse` day, and both survive save → reload. **M6 is complete.**
M5 remains open on population: it wants twelve villagers, not six.

---

## M7 — Fishing, animals, machines, cooking

- [x] Fishing works: cast, wait for a bite, hook, land a fish
- [x] An animal works: buy, place, feed, and collect its product
- [x] A machine works: place, load input, wait, collect output
- [x] Cooking works: combine ingredients at a station, get a dish
- [x] Every one of the above has distinct success and failure feedback

Six season/weather/hour-gated fish are cast and landed at the pond. Two animals
live in the CC0 coop: the hen comes with the farm, the goat is bought from the
general store, both are fed and collected on a daily cycle. Three machines are
bought from the B-key build panel, placed on farm pads, loaded from the bag,
advanced by days and collected at the machine. Four dishes are cooked at the
farmhouse stove. Every outcome publishes its own EventBus event with its own
generated sound. `test_fishing.gd`, `test_animals.gd`, `test_machines.gd`,
`test_cooking.gd` and `test_crafting.gd` cover the loops; three real-window
playtests review them.

---

## M8 — Mines and combat

- [x] A mine can be entered and descended
- [x] Combat works: attack, damage, defeat an enemy
- [x] A boss can be fought and defeated
- [x] Combat success and failure sound and look distinct
- [x] The player can die and respawn without losing save integrity

`CombatService` opens the mine from a real E interaction, then descends through
three floors of data-authored enemies before the Warden appears. K or left-click
attacks; hits, misses, kills, the boss and the clear each publish their own
EventBus event and their own synthesised cue from the 52-sound library. Death
respawns at the farm with health restored and never writes a save —
`tests/suites/test_combat.gd` covers that, and `tools/playtest_combat.gd` clears
the mine in a real window.

---

## M9 — Weather and seasons

- [ ] Weather affects gameplay, not just visuals (rain waters crops, winter kills them)
- [ ] The season changes visuals, available crops and weather weights
- [ ] Weather and the forecast survive a day rollover
- [ ] A weather change is announced, not silent

---

## M10 — Cutscene / cinematic system

- [x] A cutscene plays in the 3D world
- [x] The player can skip it
- [x] Camera, input and player control all restore correctly afterwards
- [x] Skipping mid-cutscene does not leave the world in a broken state

Delivered as data-authored `.tres` cutscenes with a generated letterbox overlay;
`tests/suites/test_cutscene.gd` covers playback, restoration, skipping with flag
catch-up and uncancellable required beats. `tools/playtest_cutscene_audio.gd`
plays the intro in a real window and skips it with a real E key.

---

## M11 — Buildings and farm upgrades

- [ ] Buildings can be bought and placed
- [ ] A placed building is usable, not decorative
- [ ] Upgrades have a real effect

---

## M12 — Festivals

- [x] A festival happens in the physical 3D world, not a separate scene
- [x] Attending or skipping a festival has consequences
- [x] A schedule defers to a festival day instead of running normally

Four dated festivals are data. On the day, `FestivalService` lights lanterns in
the real square and switches all twelve villagers to generated `<id>_festival`
days; attendance inside the square pays gold, an item and friendship exactly
once, while never turning up publishes `festival_skipped`. `test_festival.gd`
covers content, deferral, attendance and skipping; `tools/playtest_festival.gd`
reviews Bloom Day in a real window.

---

## M13 — Story progression

- [x] Main progression reaches its ending
- [x] The ending completes, and free play continues afterwards

Six data-authored chapters open on real gameplay outcomes — the intro and
village cutscenes, the first harvest, two quest turn-ins, a friendship and a
marriage. `StoryService` advances one chapter per satisfied requirement set,
publishes `story_ending_reached` exactly once, and never pauses or locks the
game. `tests/suites/test_story.gd` covers the content, ordered progression, the
ending and save round-trip; `tools/playtest_story.gd` reviews all three states
in a real window.

---

## M14 — Audio

- [x] Every major action has audio: footsteps, tools, impacts, UI, ambience
- [x] Music and ambience change with time of day and weather
- [x] Volume settings work and persist
- [x] Audio is muted correctly on pause

52 original synthesised sounds under `resources/audio/sounds/`, including 12
loops. `AudioManager` maps distinct EventBus outcomes to distinct sounds,
crossfades music, switches ambience on weather and night, persists all five
volume settings plus mute, and silences the buses on pause. Tests cover the
registry, the signal map's distinctness, non-empty distinct PCM, settings
round-trip and a headless boot with no audio device.

---

## M15 — UI and accessibility

- [ ] Every screen is reachable and dismissible by keyboard alone
- [ ] No screen traps the player
- [ ] Rebinding input works end to end, with the HUD reflecting it
- [ ] Text scales without clipping
- [ ] Colour is never the only channel carrying information

---

## M16 — Save and load

- [x] Save/reload preserves the complete state: world, farm grid, inventory,
      time, relationships, quests, unlocks
- [x] Saves from a previous `SAVE_VERSION` migrate forward
- [x] A corrupt save fails loudly rather than silently discarding progress

`SaveService` owns one versioned JSON file (`SAVE_VERSION = 3`) and asks each
service for its own state. Writes are atomic; JSON-incompatible values are
normalised on the way out and id keys restored on the way in. `test_save.gd`
covers the section set, a full round-trip, version migration and corruption;
`tools/playtest_save.gd` writes with F5 and restores with F9 in a real window.

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
