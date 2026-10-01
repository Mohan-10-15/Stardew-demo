# Legacy Content (JSON)

Balance data inherited from the two retired builds. **Nothing in the game reads
these files yet.** They are the tuned numbers, item ids and schedules that were
designed and iterated on, preserved so they are not lost and not re-guessed.

| File | Entries | What it holds |
|---|---|---|
| `items.json` | 312 | Every item: tools with 4 upgrade tiers, seeds, crops, fish, forage, ores, gems, food, placeables |
| `recipes.json` | 119 | 57 crafting + 62 cooking, with skill unlock gates and food energy/health/buffs |
| `crops.json` | 33 | Growth days, seasons, regrow rate, yield, sale price, quality chances |
| `fish.json` | 46 | Gated by place, season, weather and time of day; difficulty, motion table |
| `dialogue.json` | 6 | Per-NPC greeting/favour/heart lines |
| `schedules.json` | 6 | Daily routine windows plus weather/season/day overrides |
| `npcs.json` | 6 | Name, home, role, colour, gift taste profile |
| `quests.json` | 5 | Collect / deliver / talk objectives with gold and heart rewards |
| `skills.json` | 5 | Farming, Foraging, Mining, Fishing, Combat with professions at 5 and 10 |
| `machines.json` | 9 | Processing recipes with tick timers |
| `animals.json` | 5 | Species, product, happiness and friendship rules |
| `maps/*.json` | 2 | Tile grids and region metadata for the farm and the village |
| `shops/*.json` | 4 | General store, seed shop, clinic, travelling merchant stock and prices |

## Why these are JSON and not Resources

The live project uses Godot `Resource` subclasses (`resources/config/`) so that
content is validated by the engine and shows up in the Inspector. These files
predate that convention and are kept in their original shape on purpose:

- Converting 500+ definitions by hand is mechanical work that must be done when
  the group that needs it arrives, not speculatively.
- They are plain JSON, so they are trivially loadable at runtime as a
  migration source and easy to diff.
- The ids are the stable contract. `parsnip`, `wood`, `rowan` are referenced by
  recipes, quests, schedules and dialogue alike; keeping the files intact
  preserves those cross-references exactly.

## When to convert

Each group's first task: read the relevant file, define a `Resource` subclass
for it, write a loader, and add an EditMode-style test that loads every entry
and validates cross-references. Follow the pattern in
`resources/config/movement_config.gd`. Convert a file when a group needs it;
do not convert all of them up front.

## Naming

These are original names written for this game — `parsnip`, `hollow-pumpkin`,
`rustleaf`, `ember-bloom`. They are not copied from any commercial title. Keep
them when porting.
