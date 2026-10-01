# Acceptance Tests

What each milestone must actually do before it counts as done. These are
playable behaviours, not unit tests — a milestone is complete when a player can
do the thing through normal play with no developer cheats.

Unit and integration coverage lives in `tests/suites/`; run it with
`pwsh -File tools/check.ps1`.

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

Verified: `check.ps1` — import OK, **99/99 tests**, boot OK.

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

Blocked on M2 for the save system; the play-and-interact half can be signed off
independently.

---

## M2 — Time, calendar, and the farming loop

- [ ] Hoe a tile → it becomes tilled soil
- [ ] Plant a seed on tilled soil → a crop exists on that tile
- [ ] Water the crop → it is marked watered
- [ ] Sleep → the day advances, the crop grows, weather is re-rolled
- [ ] Harvest a mature crop → items enter the inventory
- [ ] Sell the harvest → currency increases
- [ ] A full day of 10-minute ticks advances exactly one day
- [ ] Advancing at 2:00 AM passes the player out and rolls the day
- [ ] The season rolls after day 28; the year rolls after winter
- [ ] The clock is monotonic across midnight (no double-rollover)

The rollover and monotonicity criteria are the ones the retired Unity build
actually broke; they are enumerated in `docs/SALVAGED_DESIGN.md` section
"Edge cases the old tests pinned down". They are not optional.

---

## M3 — Inventory, tools, economy

- [ ] The farm is reachable, and so is the village shop
- [ ] Buy seeds with currency; currency decreases by the right amount
- [ ] An inventory stack splits across slots when it overflows
- [ ] A full bag accepts nothing and loses nothing (all-or-nothing)
- [ ] Removing an item takes the lowest quality first
- [ ] Removing empties the slot rather than leaving a zero-count ghost
- [ ] Selling updates currency and publishes `item_sold`

---

## M4 — NPCs, dialogue, relationships

- [ ] NPC schedules change with the time of day and the weather
- [ ] Dialogue advances through a real conversation tree
- [ ] Gifting an item the NPC likes raises the relationship
- [ ] Gifting a disliked item lowers it
- [ ] An NPC says different things on different days
- [ ] Relationship changes persist across save and reload

---

## M5 — Quests

- [ ] A quest can be accepted
- [ ] Objective progress updates as the player does the thing
- [ ] A quest can be completed, and its reward is granted
- [ ] Quest state persists across save and reload
- [ ] No quest can be completed without doing its objectives

---

## M6 — Fishing, animals, machines, cooking

- [ ] Fishing works: cast, wait for a bite, hook, land a fish
- [ ] An animal works: buy, place, feed, and collect its product
- [ ] A machine works: place, load input, wait, collect output
- [ ] Cooking works: combine ingredients at a station, get a dish
- [ ] Every one of the above has distinct success and failure feedback

---

## M7 — Mines and combat

- [ ] A mine can be entered and descended
- [ ] Combat works: attack, damage, defeat an enemy
- [ ] A boss can be fought and defeated
- [ ] Combat success and failure sound and look distinct
- [ ] The player can die and respawn without losing save integrity

---

## M8 — Weather and seasons

- [ ] Weather affects gameplay, not just visuals (rain waters crops, winter kills them)
- [ ] The season changes visuals, available crops and weather weights
- [ ] Weather and the forecast survive a day rollover
- [ ] A weather change is announced, not silent

---

## M9 — Cutscene / cinematic system

- [ ] A cutscene plays in the 3D world
- [ ] The player can skip it
- [ ] Camera, input and player control all restore correctly afterwards
- [ ] Skipping mid-cutscene does not leave the world in a broken state

---

## M10 — Festivals and romance

- [ ] A festival happens in the physical 3D world, not a separate scene
- [ ] Attending or skipping a festival has consequences
- [ ] Romance and marriage work as a relationship path
- [ ] A spouse appears in the world and follows a schedule

---

## M11 — Buildings and farm upgrades

- [ ] Buildings can be bought and placed
- [ ] A placed building is usable, not decorative
- [ ] Upgrades have a real effect

---

## M12 — Story progression

- [ ] Main progression reaches its ending
- [ ] The ending completes, and free play continues afterwards

---

## M13 — Save and load

- [ ] Save/reload preserves the complete state: world, farm grid, inventory,
      time, relationships, quests, unlocks
- [ ] Saves from a previous `SAVE_VERSION` migrate forward
- [ ] A corrupt save fails loudly rather than silently discarding progress

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

## M16 — Art and animation polish

- [ ] First-person tool animations exist for every tool
- [ ] Every interactable has a use animation and a reaction
- [ ] No placeholder geometry remains in normal play
- [ ] Missing or invalid assets cannot crash the game

---

## M17 — Performance

- [ ] 60 FPS at the target resolution on target hardware
- [ ] No frame spikes when moving through world boundaries
- [ ] Memory does not grow unbounded over a long session

---

## M18 — Testing and balance

- [ ] A 2-year bot simulation (112 days × 2) completes without crash or soft-lock
- [ ] The economy holds up: the player can afford to progress and cannot idle to infinite money
- [ ] No unbounded growth or decay in any resource

---

## M19 — Release integration

- [ ] A fresh clone builds and runs from the README instructions alone
- [ ] Windows export runs on a clean machine
- [ ] Web export loads and is playable
- [ ] No debug cheats are reachable in a release build
- [ ] Every shipped asset is traced in `docs/ASSET_LICENSES.md`