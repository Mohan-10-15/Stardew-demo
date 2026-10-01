# HOLLOWBROOK HOLLOW — Game Design Document

**Genre:** farming-life sim with combat, crafting and village social systems
**Target:** native Windows desktop; a web export is a later goal, not a constraint on architecture
**Engine:** Godot 4.5-stable, GDScript, no addons, no C#
**Target hardware:** RTX 2050-class, 60 FPS
**Session shape:** a day is ~10 real minutes; a full year is 112 in-game days

Original IP. Genre-inspired, never copying another game's names, art or specific
mechanics.

---

## 1. Premise

The ash-fall took the old road and the valley's Heartstone with it. You inherit
a burnt-out farm plot in Hollowbrook Hollow and work it back to life — soil,
livestock, mines, and the twelve people who stayed. Restoring the Heartstone is
the spine of the progression; everything else you build is yours to keep
afterwards.

## 2. Pillars

1. **The day has weight.** Energy and time are the real constraint. Every swing,
   every step, every conversation costs something, so choosing what to do with a
   finite day is the game.
2. **Feedback is never ambiguous.** Success and failure always look and sound
   different (see `SALVAGED_DESIGN.md`). The player must be able to tell
   what happened without reading text.
3. **The valley is populated.** NPCs have schedules, opinions and birthdays. They
   are not vending machines with dialogue.
4. **Nothing is wasted.** Weather, seasons, tools and layout all compose. A crop
   planted in the wrong season still teaches you something.

## 3. Core loop

```
wake ──► plan the day ──► work (farm / forage / fish / mine / social)
  ▲                                              │
  │                                              ▼
  └────── sleep ◄── ship, tidy, spend ◄── end-of-day summary
```

A day runs 06:00 → 02:00, at 10 in-game minutes per tick. At 02:00 the farmer
collapses, is carried home, and loses money; sleeping in your own bed skips to
the summary with no penalty.

## 4. Feature scope

All of the following is mandatory and must be reachable from a new game through
normal play, with no dev cheats, and must survive save → reload.

### 4.1 Time and world
4 seasons × 28 days. Day/night cycle. Weather: sun, rain, storm, snow, wind,
with a forecast. Energy and health. Passing out. Sleep → end-of-day summary.
**10+ scenes**: farm, village, forest, beach, river/lake, mountain, mine
entrance, home, shop interiors. Seasonal lighting and colour changes. Ambient
life.

### 4.2 Farming
Hoe, watering can, axe, pickaxe, scythe, and a fishing rod with **4 upgrade
tiers**. Till / plant / water / fertilize / harvest. **30+ crops** including
regrowing varieties and fruit trees, with quality tiers. Sprinklers, scarecrows,
greenhouse. Weeds and debris. Placeable objects with a ghost preview. Farm
buildings and house upgrades.

### 4.3 Foraging
Trees, rocks, seasonal forageables, bushes, with regrowth.

### 4.4 Fishing
Cast plus a skill minigame. **30+ fish** gated by place, season, weather and time
of day. Bait, tackle, traps.

### 4.5 Animals
**5+ species**. Coop and barn. Feeding. Friendship. Products with quality. A pet
and a rideable horse.

### 4.6 Crafting, cooking, machines
Recipes unlocked by skills, friendships and shops. Buff foods. **8+ processing
machines** with timers. **300+ item definitions** overall.

### 4.7 Skills
Farming, Foraging, Mining, Fishing, Combat. Levels 1–10. Professions at 5 and 10.
Recipe unlocks on level-up.

### 4.8 Mines and combat
**40+ seeded floors**. Ores and gems. Checkpoints every 5 floors. **12+ monsters**
with distinct AI. **2 bosses**. Weapons, armor, rings. Readable attack telegraphs
and hit feedback.

### 4.9 Economy
Shipping bin. Shops: general, blacksmith, carpenter, ranch, fish, and a
traveling merchant. Seasonal stock. Tool upgrades. Quality-based pricing.

### 4.10 People
**12+ original NPCs** with day/season/weather schedules and NavMesh pathfinding.
Contextual dialogue. Gift tastes. Friendship hearts. **3+ scripted heart events**
each. Birthdays. Romance and marriage for **6+**. Quest board.

### 4.11 Story
A main progression goal (collections unlocking areas and features). A
collections log. An ending and credits scene, after which free play continues.
**8+ festivals**, two per season.

### 4.12 UI and UX
HUD. Hotbar plus expandable backpack. Drag-and-drop inventory. Tooltips.
Crafting. Map. Journal. Skills / relationships / collections tabs. Dialogue with
portraits. Shop UI. Title screen with new game and load. Character and farm
creator. Options: audio, graphics, remappable keys via the InputMap, UI scale,
colourblind mode. Pause. Keyboard/mouse and gamepad.

The existing `InteractionHUD` is plain Godot nodes driven by the `EventBus`, not
a theme or markup system. Keep that: build UI from code and signal it, so there
is no second place where layout and logic can disagree.

### 4.13 Audio
Music per location, season and time of day (**12+ loops**). Ambience. SFX for
every action. Volume sliders.

### 4.14 Saves
3 slots. Autosave on sleep. Versioned and migrated. Corruption-safe.
Export/import.

### 4.15 Polish and release
Transitions, particles, camera juice, pickup popups. Tutorial across the first
in-game days. **All strings in a table**, i18n-ready. Credits. README. A
Windows standalone build.

### 4.16 Dev tooling
Content validators as headless test-suite cases. A dev console (skip day, set money,
teleport) stripped from release builds. A headless bot that drives 2 in-game years
to catch crashes and soft-locks. An economy balance report.

### Out of scope
Online multiplayer. Mod tools. Mobile touch controls.

## 5. Economy model

Tuned so that a competent player comfortably buys their first house upgrade in
Spring of Year 1, and a first tool upgrade (1000g) by late Summer Year 1.

| Source | Typical value |
|---|---|
| Parsnip (4-day crop) | 35g base |
| Shipping bin payout | base × quality multiplier (1× / 1.25× / 1.5×) |
| Tool upgrade costs | 1000g / 2500g / 5000g / 10000g |
| Starting money | 500g |
| Starting bag | 12 slots, incl. 15 parsnip seeds |

Harvest quality is ~94% normal, ~5% silver, ~1% gold, rolled on a dedicated RNG
stream so it cannot perturb other outcomes.

A later economy report measures actual earnings per in-game day against this
table, and the balance is adjusted until a realistic Year-1 income lands in
range.

## 6. Art direction

Stylized and detailed, from free CC0 packs — not blocky primitives, and not an
attempt at photorealism.

- **KayKit** for rigged, animated characters (player, NPCs) — 5 characters,
  27 accessories, already in `assets/models/kaykit/`.
- **Quaternius** for buildings, farm animals and nature — 13 buildings and props,
  already in `assets/models/quaternius/`.

Cohesion matters more than any single asset's fidelity, so nothing outside these
two packs is mixed in. See `ART_LICENSES.md`.

## 7. Accessibility

Colourblind mode (at minimum a shape/pattern cue for item quality, not colour
alone). UI scale. Remappable keys. Full gamepad support. Readable attack
telegraphs that do not rely on colour.

## 8. Win condition

Restore the Heartstone by completing the collection milestones that unlock each
valley area, then see the ending and credits. Free play continues afterwards —
nothing is taken away, and the credits are reachable from the pause menu.
