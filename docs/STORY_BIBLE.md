# Story Bible — The Ash and the Heartstone

Update 2, W2.1. This is the source of truth for the story added in Update 2.
The GDD's canon (§1) and the six existing `StoryChapter` resources stay
untouched: their ids live in saves and are never renamed or renumbered.

## Tone

Cozy, warm, a little melancholy. The antagonist is forgetting, not a villain.
Villagers are funny and specific; the stakes are emotional, not world-ending.
The valley's tagline — "A valley that remembers you" — is literal: the world
keeps a ledger of what the player actually did (W2.6, ValleyMemory).

## Canon

- The ash-fall took the old road and the valley's Heartstone with it.
- The player inherits a burnt-out farm; twelve people stayed.
- The Heartstone was the valley's hearth-stone: it kept the seasons gentle and
  let the Hollow remember its people. Broken, it scattered six Embers.
- Restoring it is the spine; free play follows.
- Each completed collection coaxes one Ember home. Without them, small
  wrongnesses creep in — early frost, a well that runs low, a path that closes.
- The last Ember (Hearts) needs friendship. The Mending recites real deeds the
  valley remembers of *this* player, not generic praise.

## Glossary

| Term | Meaning |
|---|---|
| Heartstone | The valley's broken hearth-stone on the square's plinth. |
| Ember | One of six fragments: Fields, Waters, Stone, Table, Wilds, Hearts. |
| Collection | A data-driven set of things the valley remembers (crops, fish, ore, dishes, forage, friendship). |
| Tier | A collection milestone at 40 %, 70 %, 100 %; each unlocks something tangible. |
| The Mending | The Act III scene at the plinth that restores the Heartstone. |
| ValleyMemory | The ledger of deeds the player actually performed. |

## Timeline

| Act | Name | Season | Chapters | Beat |
|---|---|---|---|---|
| I | Cinders | Spring, year 1 | ch01–ch04 | Arrival, burnt plot, first harvest, the square wakes, the empty plinth, Bloom Day without the Heartstone. Ends with the first Ember glowing in the orchard. |
| II | Embers | Summer–autumn | new | Collection tiers open the orchard, pier, forest road and Deep Mines. Heart events at 4♥ and 8♥. The Mine Warden guards the Deep Ember. Harvest Tide brings the first real wrongness. |
| III | Hearth | Winter onward | ch06 becomes the epilogue | Early frost; the Frost Lantern cannot be lit; the village looks to the player; the last Ember; The Mending at the plinth; ending, credits, free play. |

Existing chapters `ch01_arrival` … `ch06_ending` keep their ids. New chapters
get `ch07_`+ ids with explicit `act` and `order` fields.

## The six collections and their Embers

| Collection | Ember | Tier 1 unlock | Tier 2 unlock | Tier 3 |
|---|---|---|---|---|
| Fields | Fields | Orchard path | Sprinkler recipe | First Ember |
| Waters | Waters | Pond pier | Bait and better rod | Second Ember |
| Stone | Stone | Deep Mines stairs | Lantern recipe | Third Ember |
| Table | Table | Advanced recipes | Festival feast | Fourth Ember |
| Wilds | Wilds | Forest road | Foraging basket | Fifth Ember |
| Hearts | Hearts | The plinth wakes | A heart event | Sixth Ember |

The final table is confirmed against the real `LocationData` ids in W2.3; the
world has no inn or separate mine location, so gates are placed against the
existing `village_square`, `village_orchard`, `pond_shore`, `forest_edge`,
`kitchen_garden`, `general_store`, `village_well`, `farm_home`, the twelve
cottages and the `mine_entrance` prop.

## The twelve — want, fear, secret, loved gift, cost of the ash

Grounded in the shipped `NpcData` descriptions, five quests and dialogue lines;
those lines remain canon. Details may be refined by the owner (human queue 10).

| Villager | Want | Fear | Loved gift | What the missing Heartstone costs them |
|---|---|---|---|---|
| Mira | For the farm to live again | That everyone leaves | Parsnip | Her lessons have no one to teach them |
| Bram | To rebuild the square | That his work is forgotten | Wood | Every foundation he lays cracks by spring |
| Fen | A quiet firewood routine | The dark of the old road | Wood | He cannot remember why he stays past dusk |
| Odette | Gentle winters | The first frost | Wild berry | Her forecasts keep being wrong |
| Sable | A fence that holds | Losing the last livestock | Egg | Nothing stays mended for long |
| Aurel | To be useful | Being overlooked | Fish | His victories feel small without an audience |
| Lyra | Music in the square | Silence | Berry | She has forgotten half the old songs |
| Cassia | Answers in the ash | That the past cannot return | Mushroom | Her notes keep contradicting themselves |
| Elke | A garden of her own | Being rootless | Flower | Seeds she plants forget how to grow |
| Garrick | To protect the hollow | Failing again | Stone | The old road's dangers keep returning |
| Halda | To remember the old days | Forgetting them | Milk | Her stories lose a name each season |
| Dorian | To belong | That he is only passing through | Egg | He cannot feel the valley remembering him |

## Deeds the Mending may recite

First harvest; a birthday gift; a missed birthday; finishing someone's job; a
promise kept; a promise broken; a storm slept through; the first fish; the
first ore; a festival attended; the plinth first touched. At least five and at
most seven are spoken, chosen from the real ValleyMemory ledger.
