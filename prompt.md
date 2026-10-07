# HOLLOWBROOK HOLLOW

## FINAL MASTER GAME DEVELOPMENT PROMPT

### OpenCode / OpenCode4

### Existing Godot Repository — Multi-Language Architecture

---

# 0. PROJECT

Repository:

`https://github.com/Mohan-10-15/Stardew-demo`

Local project:

`C:\mohan\Game\Stardew dmeo`

Engine:

**Godot 4.5**

Primary target:

**Windows PC**

Primary perspective:

**First-person 3D**

Project type:

**3D farming + life simulation + exploration + adventure + RPG**

---

# 1. YOUR MISSION

You are the primary development system responsible for turning the existing repository into a complete, polished, original game called:

# HOLLOWBROOK HOLLOW

This is an existing project.

Do NOT throw away the existing architecture.

Do NOT restart from zero.

Do NOT convert everything to another engine.

Do NOT create a simple demo.

Do NOT build only technical prototypes.

Build a complete playable game.

The final experience should feel like a real commercial-quality indie farming/life-simulation/adventure game.

The game may be inspired by the broad genre conventions of farming/life-sim games, but everything specific to Hollowbrook Hollow must be original:

* characters
* world
* names
* dialogue
* story
* quests
* music
* sound effects
* artwork
* environments
* items
* monsters
* festivals
* gameplay systems
* visual identity

Do not copy Stardew Valley's copyrighted assets, characters, maps, dialogue, music, UI artwork or other protected content.

---

# 2. CORE DESIGN VISION

The player arrives in a large original valley called:

# HOLLOWBROOK HOLLOW

The player can:

* build a farm
* grow crops
* explore a large world
* meet villagers
* build friendships
* romance characters
* marry
* fish
* raise animals
* craft
* cook
* mine
* fight monsters
* complete quests
* discover secrets
* participate in festivals
* experience story events
* explore changing seasons
* experience weather
* experience day/night
* experience cinematic cutscenes
* eventually complete the main story
* continue playing afterward

The world should feel alive.

The player should feel that they are living in an actual place rather than navigating a collection of test scenes.

---

# 3. MOST IMPORTANT CONTENT RULE

## THERE IS NO ARBITRARY CONTENT LIMIT.

All numbers mentioned in this specification are:

**MINIMUM ACCEPTANCE TARGETS**

They are NOT maximum limits.

For example:

```text
30+ crops
```

means:

> At least 30 crops, with more allowed.

It does NOT mean:

> Exactly 30 crops.

The same applies to:

* fish
* NPCs
* items
* recipes
* quests
* festivals
* monsters
* mine floors
* dialogue
* cutscenes
* sounds
* locations
* buildings
* weapons
* tools
* collectibles
* story events

Never remove content merely to satisfy a numerical limit.

If the architecture can support more content cleanly, add more.

Do not artificially cap the game.

---

# 4. EIGHT DEVELOPMENT GROUPS

Do NOT create 30+ workers.

Use exactly these 8 major development groups.

Each group can contain internal tasks/subtasks, but the architecture remains organized around these 8 groups.

---

## GROUP 1 — CORE & ARCHITECTURE

Responsible for:

* Godot configuration
* project architecture
* GDScript
* C#
* C++/GDExtension integration
* EventBus
* GameState
* Config
* save architecture
* input architecture
* shared resources
* shared APIs
* cross-language boundaries
* build system
* testing framework
* integration
* documentation
* project tooling

This group owns the foundation.

---

## GROUP 2 — WORLD & ENVIRONMENT

Responsible for:

* large world
* terrain
* farm
* village
* forest
* mountain
* mines
* lake
* river
* beach
* buildings
* interiors
* roads
* paths
* bridges
* secret areas
* day/night
* seasons
* weather
* lighting
* fog
* environment
* shaders
* particles
* vegetation
* world streaming/chunking
* world map
* minimap

---

## GROUP 3 — GAMEPLAY & SIMULATION

Responsible for:

* farming
* crops
* tools
* inventory
* items
* fishing
* animals
* crafting
* cooking
* skills
* economy
* shops
* mining
* combat
* enemies
* bosses
* loot
* progression
* buffs
* player stats

---

## GROUP 4 — NPCs & AI

Responsible for:

* villagers
* NPC schedules
* navigation
* NPC AI
* daily routines
* relationships
* friendship
* romance
* marriage
* gifts
* birthdays
* NPC reactions
* NPC movement
* NPC decision-making
* contextual behaviour

---

## GROUP 5 — STORY & CONTENT

Responsible for:

* main story
* side quests
* dialogue
* festivals
* heart events
* romance events
* story events
* lore
* secrets
* collections
* progression events
* cutscenes
* endings
* post-game content

---

## GROUP 6 — UI & PLAYER EXPERIENCE

Responsible for:

* HUD
* inventory
* hotbar
* menus
* dialogue UI
* character portraits
* quest journal
* map
* minimap
* skills
* relationships
* collections
* shops
* settings
* interaction prompts
* crosshair
* accessibility
* controller support

---

## GROUP 7 — AUDIO & VISUAL PRESENTATION

Responsible for:

* sound effects
* music
* ambience
* footsteps
* weather audio
* NPC audio
* combat audio
* farming audio
* fishing audio
* UI audio
* dynamic music
* character animation
* visual effects
* cinematic presentation
* audio mixing
* environmental presentation

---

## GROUP 8 — QA, PERFORMANCE & RELEASE

Responsible for:

* automated tests
* regression tests
* gameplay testing
* performance profiling
* memory checks
* save testing
* long-session testing
* balance testing
* 2-year simulation testing
* crash testing
* release builds
* packaging
* validation
* final polish

---

# 5. MULTI-LANGUAGE ARCHITECTURE

The project must NOT be GDScript-only.

The project must NOT be C#-only.

Use the appropriate technology for the appropriate task.

---

## GDSCRIPT

Primary use:

* Godot scenes
* Nodes
* gameplay orchestration
* UI
* player controller
* interactions
* dialogue presentation
* quests
* cutscenes
* game flow
* signals
* EventBus
* scene management
* input
* save orchestration

Keep existing working GDScript systems unless there is a concrete reason to change them.

---

## C#

Use C# for systems where it provides meaningful advantages.

Potential uses:

* complex simulation
* economy simulation
* AI calculations
* procedural generation
* path-cost calculations
* large data processing
* balance simulation
* analytics
* performance-sensitive algorithms
* offline game simulation
* deterministic calculations

Do not convert existing GDScript just for the sake of using C#.

---

## C++ / GDExtension

Use only where profiling or technical requirements justify native code.

Potential uses:

* very expensive algorithms
* specialized spatial structures
* extremely heavy procedural generation
* native integrations
* performance-critical systems

Rules:

1. Measure first.
2. Implement.
3. Benchmark.
4. Test.
5. Document.

Never use C++ merely because it sounds faster.

---

## GODOT SHADERS

Use Godot shader language for:

* water
* rain
* snow
* wet surfaces
* vegetation movement
* lighting effects
* fog
* seasonal effects
* environmental effects
* outlines
* particles
* post-processing
* special story effects

---

## PYTHON

Python is allowed for offline development tools.

Use it for:

* content generation
* validation
* data processing
* balancing
* reports
* asset processing
* dialogue validation
* item generation
* economy analysis
* development utilities

Do not make Python a required runtime dependency unless there is a compelling reason.

---

## POWERSHELL

Use PowerShell for:

* Windows build automation
* test scripts
* packaging
* validation
* project tooling

Support Windows PowerShell 5.1 when PowerShell 7 is unavailable.

---

## DATA

Use appropriate data formats:

* Godot Resources
* JSON
* CSV
* YAML where useful

Use SQLite/SQL only when genuinely useful for offline tools or analytics.

---

# 6. NO ARTIFICIAL LANGUAGE COMPLEXITY

Never do this:

```text
GDScript → C# → Python → C++ → SQL
```

for a simple feature.

Keep interfaces simple.

Every cross-language dependency must have a reason.

Document the boundary.

Test the boundary.

---

# 7. EXISTING PROJECT FIRST

Before writing new systems:

Inspect:

```text
project.godot
AGENTS.md
README.md
prompt.md
DEVELOPMENT_STATUS.md
docs/
scripts/
scenes/
resources/
tests/
tools/
assets/
```

Understand the existing architecture.

Preserve:

* EventBus
* GameState
* Config
* logging
* debug systems
* PlayerController
* CameraRig
* InteractionProbe
* WorldBuilder
* resource architecture
* generated scenes
* tests
* validation scripts

Do not destroy working systems.

---

# 8. ARCHITECTURE DOCUMENTATION

Create/update:

```text
docs/ARCHITECTURE.md
docs/MULTI_LANGUAGE_ARCHITECTURE.md
docs/TECH_STACK.md
docs/GDD.md
docs/ROADMAP.md
docs/TASKS.md
docs/DECISIONS.md
docs/ASSET_LICENSES.md
docs/AUDIO_GUIDE.md
docs/CUTSCENE_GUIDE.md
docs/ACCEPTANCE.md
DEVELOPMENT_STATUS.md
```

The architecture documentation must explain the 8 groups and language ownership.

---

# 9. WORLD — LARGE CONNECTED MAP

The world must be substantially larger than a prototype test map.

Create a large explorable valley containing, at minimum:

* player farm
* village
* town center
* general store
* blacksmith
* carpenter/building shop
* animal/ranch shop
* fishing shop
* traveling merchant
* forest
* river
* lake
* beach
* mountain
* mines
* caves
* hidden areas
* NPC homes
* public buildings
* festival grounds
* fishing areas
* forage areas
* combat areas
* secret areas
* quest locations

More locations are encouraged.

---

# 10. WORLD CONNECTIVITY

Prefer one coherent world.

Use:

* roads
* paths
* bridges
* trails
* tunnels
* cave entrances
* gates
* building entrances

Use scene transitions/loading only when technically necessary.

The world must not feel like disconnected menu screens.

---

# 11. WORLD MAP

Create a full world map.

The map must show:

* player
* farm
* village
* shops
* homes
* mines
* fishing locations
* important landmarks
* quest locations
* discovered areas
* festival locations
* secret locations when discovered

Support:

* zoom
* pan
* markers
* legend
* discovery
* quest tracking

Do not reveal everything immediately if discovery is appropriate.

---

# 12. MINIMAP

Create a persistent minimap.

Default:

**top-right of screen**

Show:

* player position
* player direction
* nearby NPCs
* roads
* buildings
* water
* important landmarks
* quest markers
* enemies where appropriate

Use a clean player direction indicator.

Allow:

* enable/disable
* size
* opacity
* marker settings

Do not make the minimap consume too much screen space.

---

# 13. CROSSHAIR

The first-person crosshair must be:

# `+`

Not a large FPS reticle.

Default:

```text
   |
---+---
   |
```

Small, clean and unobtrusive.

When looking at an interactable:

```text
+
[E] Talk
```

or:

```text
+
[E] Harvest
```

or:

```text
+
[E] Open
```

For controller:

```text
+
[A] Talk
```

The prompt must dynamically change based on the current interaction.

---

# 14. DAY / NIGHT

Implement a full time system.

Support:

* morning
* afternoon
* evening
* night
* late night
* sleep
* day rollover

Time affects:

* NPC schedules
* shops
* crops
* animals
* fishing
* enemies
* quests
* dialogue
* weather
* lighting
* ambience
* story events

Day rollover occurs according to the established game rules.

---

# 15. SEASONS

Implement:

* Spring
* Summer
* Autumn
* Winter

Minimum:

**4 seasons × 28 days**

But the architecture must support expansion.

Season affects:

* crops
* forage
* fish
* NPC dialogue
* festivals
* weather
* vegetation
* lighting
* ambience
* world appearance
* quests
* events

---

# 16. WEATHER

Support:

* sunny
* cloudy
* rain
* storm
* snow
* special weather events

Weather affects:

* visuals
* sound
* NPC schedules
* dialogue
* farming
* fishing
* ambience
* lighting
* gameplay where appropriate

Weather must be visually noticeable.

---

# 17. FARMING

Implement a complete farming system.

Minimum:

**30+ crops**

No maximum.

Support:

* seeds
* planting
* soil
* watering
* growth stages
* crop quality
* harvesting
* regrowth
* seasonal crops
* fertilizer
* sprinklers
* scarecrows
* fruit trees
* greenhouse
* farm upgrades
* farm buildings

Every major action should have:

* animation
* sound
* visual feedback
* item update
* gameplay consequence

---

# 18. TOOLS

Implement:

* hoe
* watering can
* axe
* pickaxe
* scythe
* fishing rod

Minimum:

**4 upgrade tiers**

Support:

* tool durability/energy considerations if appropriate
* animations
* sounds
* particles
* upgraded effectiveness

---

# 19. FORAGING

Implement a substantial foraging system.

Include:

* seasonal items
* forest resources
* rare items
* hidden items
* gathering locations
* respawn logic
* collection tracking

No arbitrary content ceiling.

---

# 20. FISHING

Minimum:

**30+ fish**

No maximum.

Fish depend on:

* location
* season
* weather
* time
* conditions

Implement:

* casting
* waiting
* bite
* fishing minigame
* reeling
* catch
* failure
* bait
* tackle
* fishing progression
* rare fish
* collection

Fishing must have proper sound and visual feedback.

---

# 21. ANIMALS

Minimum:

**5+ animal species**

Support:

* feeding
* friendship
* products
* quality
* growth
* care
* animations
* sounds
* weather behaviour
* seasonal behaviour

Also include:

* pet
* horse

---

# 22. CRAFTING

Minimum:

**8+ machine types**

But no content maximum.

Implement:

* crafting recipes
* machines
* processing
* material requirements
* output
* timing
* quality
* upgrades

---

# 23. ITEMS

Minimum:

**300+ item definitions**

No maximum.

Items must be data-driven.

Include categories such as:

* crops
* seeds
* forage
* fish
* minerals
* ores
* gems
* tools
* weapons
* armor
* rings
* food
* recipes
* materials
* quest items
* collectibles
* machine products
* gifts
* special items

Do not hard-code hundreds of items into one script.

---

# 24. COOKING

Implement:

* recipes
* ingredients
* cooking stations
* buffs
* food quality where appropriate
* energy/health restoration
* recipe discovery
* collection

---

# 25. SKILLS

Implement at least:

* Farming
* Foraging
* Fishing
* Mining
* Combat

Each:

**Level 1–10**

Support:

* XP
* level-up events
* unlocks
* professions
* passive benefits

No artificial content ceiling.

---

# 26. MINES

Minimum:

**40+ floors**

Support:

* procedural/semi-procedural layouts
* ores
* gems
* resources
* enemies
* secrets
* ladders
* hazards
* treasure
* bosses

Minimum:

**12+ monster types**

Minimum:

**2 bosses**

No maximum.

---

# 27. COMBAT

Implement:

* melee
* ranged where appropriate
* enemy AI
* damage
* health
* attack animations
* hit effects
* knockback
* death
* loot
* weapons
* armor
* rings
* buffs
* bosses

Combat must remain compatible with the peaceful farming/life-sim identity.

---

# 28. ECONOMY

Implement:

* currency
* selling
* shipping
* buying
* prices
* shops
* upgrades
* rewards

Minimum:

**6 shop types**

But no content maximum.

Economy should respond coherently to progression.

---

# 29. NPC SYSTEM

Minimum:

**12+ original villagers**

No maximum.

Every important NPC should have:

* name
* personality
* home
* workplace
* schedule
* preferences
* likes
* dislikes
* dialogue
* portrait
* animations
* relationships
* birthday
* seasonal behaviour
* weather behaviour
* story involvement

---

# 30. NPC SCHEDULES

NPCs should behave like people living in the world.

Schedules depend on:

* time
* day
* season
* weather
* festival
* friendship
* quest
* story progression

NPCs should:

* wake up
* travel
* work
* socialize
* eat
* visit places
* return home
* sleep

---

# 31. NPC AI

Use appropriate technology.

Simple behaviour can remain in GDScript.

Complex calculations can use C#.

Native C++ is allowed only when justified.

NPC AI must not require dozens of unnecessary cross-language calls every frame.

---

# 32. FRIENDSHIP

Implement:

* friendship points
* friendship levels
* gifts
* favourite gifts
* disliked gifts
* conversations
* birthdays
* events
* relationship changes
* contextual dialogue

---

# 33. ROMANCE

Minimum:

**6+ romance candidates**

No maximum.

Support:

* friendship progression
* romantic dialogue
* gifts
* romance events
* relationship milestones
* proposal
* marriage
* post-marriage behaviour
* spouse schedules
* spouse dialogue

Characters must be original.

---

# 34. NPC PORTRAITS

Important NPCs should have dialogue portraits.

Support expressions such as:

* neutral
* happy
* sad
* angry
* surprised
* excited
* embarrassed
* worried
* romantic

Portrait selection should respond to dialogue context.

---

# 35. DIALOGUE SYSTEM

Create a polished dialogue system inspired by the readability of classic farming/life-sim games.

Do NOT copy Stardew Valley's UI artwork or dialogue.

Dialogue must appear clearly on screen.

Example:

```text
┌──────────────────────────────────────────────┐
│ [NPC PORTRAIT]                              │
│                                             │
│ ELIAS                                       │
│                                             │
│ "The river looks different after the rain." │
│                                             │
│                                ▼ Continue   │
└──────────────────────────────────────────────┘
```

Support:

* NPC name
* portrait
* text
* typewriter effect
* continue
* skip typewriter
* branching choices
* player responses
* consequences
* story flags
* relationship changes
* quest updates
* seasonal dialogue
* weather dialogue
* festival dialogue
* time-based dialogue
* friendship dialogue
* romance dialogue

---

# 36. DIALOGUE CONTENT

Dialogue should be extensive.

Do NOT artificially limit dialogue to a small number of lines.

NPCs should have contextual dialogue for:

* different days
* different seasons
* weather
* time
* festivals
* friendship levels
* romance
* marriage
* quests
* story progression
* locations
* player actions

All dialogue must be original.

---

# 37. PLAYER CHARACTER

The main character must have a proper visual presence.

Support:

* appearance customization where practical
* walking
* running
* tool use
* farming
* fishing
* combat
* interaction
* eating
* sleeping
* damage
* healing
* reactions

Gameplay remains primarily first-person.

---

# 38. CINEMATIC CAMERA

Use cinematic camera control for:

* cutscenes
* major story moments
* festivals
* romance events
* marriage
* important discoveries
* ending

Support transitions:

```text
First Person
     ↓
Camera transition
     ↓
Cinematic
     ↓
Event
     ↓
Restore player
     ↓
First Person
```

---

# 39. CUTSCENE SYSTEM

Build a reusable cutscene framework.

Support:

### Camera

* camera cuts
* movement
* follow
* zoom
* look-at
* shake
* cinematic framing

### Actors

* player
* NPCs
* animals
* enemies
* props

Support:

* movement
* animation
* facing
* look-at
* gestures
* dialogue
* spawn
* despawn

### Effects

* fade
* letterboxing
* lighting
* particles
* weather
* sound
* music
* environmental changes

### Game state

* player lock
* time pause
* time advancement
* story flags
* quest updates
* relationship updates
* scene changes
* state restoration

---

# 40. CUTSCENE SKIPPING

Support:

**Skip Cutscene**

Skipping must still apply gameplay consequences.

Example:

```text
Cutscene
 ↓
story flag
 ↓
quest update
 ↓
relationship update
 ↓
unlock
```

Skipping only removes presentation, not gameplay state changes.

---

# 41. FESTIVALS

Minimum:

**8+ festivals**

No maximum.

Festivals can include:

* competitions
* food events
* fishing events
* seasonal celebrations
* races
* social events
* special quests
* minigames
* unique shops
* unique rewards
* cinematic events

Festivals should feel substantially different from normal gameplay.

---

# 42. QUEST SYSTEM

Support:

* main quests
* side quests
* repeatable quests
* collection quests
* delivery quests
* exploration quests
* combat quests
* NPC quests
* story quests
* festival quests

Rewards:

* money
* items
* friendship
* unlocks
* access
* recipes
* story progression

---

# 43. MAIN STORY

Create an original long-form progression.

The story must contain:

* introduction
* early objectives
* world discovery
* character development
* mysteries
* progression
* major conflicts
* important reveals
* climax
* ending

The story must support:

* quests
* cutscenes
* dialogue
* world changes
* NPC reactions
* unlocks

---

# 44. ENDING + FREE PLAY

The game must have:

* meaningful ending
* credits
* post-ending free play

After the ending:

* player can continue
* farming continues
* NPCs remain active
* economy continues
* collections remain
* exploration remains
* optional content remains

---

# 45. COLLECTIONS

Implement collections for things such as:

* crops
* fish
* minerals
* monsters
* recipes
* items
* achievements
* NPC relationships
* discoveries

No arbitrary collection limit.

---

# 46. AUDIO

Audio is mandatory.

The game must NOT be silent.

Create sound categories:

```text
audio/
    music/
    ambience/
    footsteps/
    farming/
    fishing/
    combat/
    mining/
    animals/
    NPC/
    UI/
    weather/
    cutscenes/
```

---

# 47. SOUND EFFECTS

Implement sounds for:

### Environment

* wind
* leaves
* birds
* insects
* water
* river
* ocean
* rain
* thunder
* snow
* forest
* village
* nighttime

### Player

* footsteps
* different surfaces
* tools
* pickup
* drop
* eating
* damage
* healing

### Farming

* hoe
* planting
* watering
* harvesting
* chopping
* mining

### Fishing

* casting
* splash
* bite
* reel
* catch
* failure

### Combat

* swing
* impact
* enemy attack
* damage
* death
* boss effects

### UI

* menu
* selection
* confirmation
* error
* notification
* quest completion
* level-up

---

# 48. MUSIC

Create dynamic music.

Music can respond to:

* season
* time
* location
* weather
* festival
* combat
* danger
* mines
* story
* cutscene

Use smooth transitions.

---

# 49. ENVIRONMENTAL AUDIO

Different areas should sound different.

Example:

Forest:

```text
wind
+
birds
+
leaves
+
insects
+
forest music
```

Village:

```text
people
+
doors
+
shops
+
footsteps
+
village music
```

Rain:

```text
rain
+
wind
+
thunder
+
wet environment
```

Mine:

```text
cave ambience
+
drips
+
echo
+
distant monsters
```

---

# 50. CHARACTER AUDIO

Support:

* dialogue blips
* reaction sounds
* event sounds
* optional voiced lines
* future voice acting

Voice acting is optional.

Important dialogue must always be readable as text.

---

# 51. SEASONAL VISUALS

Spring:

* flowers
* green growth
* rain
* fresh atmosphere

Summer:

* dense vegetation
* warm lighting
* insects

Autumn:

* changing foliage
* falling leaves
* warm colours

Winter:

* snow
* frozen areas
* reduced vegetation
* cold ambience

Do not simply apply a single colour filter.

Change actual environmental presentation.

---

# 52. WEATHER VISUALS

Rain:

* particles
* wet surfaces
* darker lighting
* puddles where appropriate
* rain audio
* thunder

Snow:

* snow particles
* snow-covered surfaces
* footsteps
* wind

Storm:

* lightning
* thunder
* wind
* dramatic lighting

---

# 53. UI

Implement:

* title screen
* new game
* load game
* character creation
* farm creation
* HUD
* hotbar
* inventory
* crafting
* cooking
* map
* minimap
* quest journal
* skills
* relationships
* collections
* shops
* settings
* pause
* credits

---

# 54. ACCESSIBILITY

Support:

* UI scaling
* readable fonts
* colourblind-friendly presentation
* text speed
* dialogue speed
* audio volume controls
* subtitle settings
* controller support
* remappable controls
* minimap toggle
* crosshair options

---

# 55. CONTROLLER SUPPORT

Support:

* movement
* camera
* interaction
* tools
* inventory
* menus
* dialogue
* map
* minimap
* combat
* fishing

All important gameplay must be accessible without requiring a mouse.

---

# 56. SAVE SYSTEM

Support:

**3+ save slots**

with:

* autosave
* manual save where appropriate
* versioning
* migration
* corruption protection
* safe writing
* reload
* cross-language data safety

Do not serialize transient runtime objects directly.

Use stable data structures.

---

# 57. PERFORMANCE

Use:

* profiling
* chunking
* culling
* LOD where appropriate
* efficient AI updates
* cached map data
* minimap throttling
* object pooling where useful
* shader optimization
* efficient audio streaming
* efficient resource loading

Do not optimize blindly.

Measure first.

---

# 58. C# / C++ PERFORMANCE POLICY

For every performance-oriented implementation:

```text
measure
↓
identify bottleneck
↓
implement
↓
benchmark
↓
test
↓
document
```

Never introduce C++ or C# solely for appearance.

---

# 59. TESTING

Maintain real automated tests.

Test:

* time
* seasons
* weather
* farming
* crop growth
* inventory
* crafting
* economy
* fishing
* animals
* mining
* combat
* NPC schedules
* relationships
* quests
* dialogue
* cutscenes
* save/load
* cross-language systems
* world generation
* content validation

No fake tests.
No empty tests.
No assertions that always pass.

---

# 60. LONG-TERM SIMULATION TEST

Create a headless gameplay simulation capable of running an extended game period.

Minimum target:

**2 in-game years**

Test:

* economy
* crops
* NPC schedules
* relationships
* seasons
* weather
* quests
* item generation
* save/load
* progression

Produce a report.

---

# 61. CONTENT VALIDATION

Create automated validation for:

* duplicate item IDs
* invalid references
* missing dialogue
* missing portraits
* missing sounds
* missing recipes
* invalid NPC schedules
* broken quests
* invalid story flags
* missing cutscene dependencies
* missing assets
* invalid resource references

The game should fail validation clearly rather than silently breaking.

---

# 62. ASSET LICENSING

Use only:

* original assets
* properly licensed assets
* CC0 assets
* compatible permissive assets

Maintain:

`docs/ASSET_LICENSES.md`

Record:

* asset
* source
* author
* license
* usage
* attribution requirements

Never use copyrighted Stardew Valley assets.

---

# 63. NO PLACEHOLDER FINAL SYSTEMS

Do not ship:

```text
empty map
generic NPC
silent world
fake dialogue
dummy cutscene
blank minimap
placeholder crosshair
fake economy
fake combat
fake fishing
fake farming
fake save system
```

A placeholder may exist temporarily during development, but every final system must be replaced with the actual implementation before completion.

---

# 64. NO ARTIFICIAL CONTENT LIMITS

Do not tell yourself:

> "The specification only needs 30 crops."

Instead:

> "The specification requires at least 30 crops, and the content system should support as many as the game design benefits from."

The same principle applies everywhere.

The architecture must be expandable.

---

# 65. CONTENT GENERATION

Use data-driven content.

Examples:

```text
resources/
    crops/
    fish/
    items/
    recipes/
    NPCs/
    dialogue/
    quests/
    monsters/
    weapons/
    tools/
    festivals/
    cutscenes/
```

Large content sets should not become giant hard-coded scripts.

---

# 66. DEVELOPMENT ORDER

Work in dependency order.

### PHASE 1

Audit existing project.

### PHASE 2

Establish multi-language architecture.

### PHASE 3

Configure Godot .NET.

### PHASE 4

Verify C# integration.

### PHASE 5

Establish C++/GDExtension only where justified.

### PHASE 6

Build data architecture.

### PHASE 7

Build world.

### PHASE 8

Build farming/gameplay.

### PHASE 9

Build NPCs.

### PHASE 10

Build dialogue/UI.

### PHASE 11

Build story/cutscenes.

### PHASE 12

Build audio.

### PHASE 13

Build advanced content.

### PHASE 14

Optimize.

### PHASE 15

Long-term simulation.

### PHASE 16

Release preparation.

Do not attempt everything simultaneously.

---

# 67. INTEGRATION RULE

Every group must integrate with the same core architecture.

Example:

```text
WORLD
  ↓
NPC
  ↓
DIALOGUE
  ↓
QUEST
  ↓
STORY
  ↓
CUTSCENE
  ↓
AUDIO
  ↓
REWARD
  ↓
SAVE
```

Systems must work together.

---

# 68. EXAMPLE COMPLETE GAME LOOP

A player might:

```text
Wake up
 ↓
Check weather
 ↓
Check minimap
 ↓
Water crops
 ↓
Harvest crop
 ↓
Hear farming SFX
 ↓
Gain Farming XP
 ↓
Walk to village
 ↓
See NPC on schedule
 ↓
Talk to NPC
 ↓
Dialogue box appears
 ↓
NPC portrait appears
 ↓
Receive quest
 ↓
Quest marker appears
 ↓
Open world map
 ↓
Navigate to forest
 ↓
Forage
 ↓
Fish at river
 ↓
Catch fish
 ↓
Return to village
 ↓
Sell items
 ↓
Buy seeds
 ↓
Attend festival
 ↓
Experience cutscene
 ↓
Story flag changes
 ↓
Return home
 ↓
Save
 ↓
Sleep
 ↓
Next day
```

The game should support this kind of interconnected experience.

---

# 69. CUTSCENE EXAMPLE

A major story event:

```text
Player enters forest
        ↓
music fades
        ↓
camera transitions
        ↓
player movement locked
        ↓
NPC walks into scene
        ↓
NPC looks at player
        ↓
dialogue appears
        ↓
portrait changes
        ↓
forest ambience changes
        ↓
music begins
        ↓
NPC reveals story information
        ↓
environmental effect
        ↓
camera movement
        ↓
story flag
        ↓
quest update
        ↓
camera restores
        ↓
player control returns
```

This must be implemented as a real reusable system.

---

# 70. FINAL QUALITY STANDARD

The final game should satisfy these questions:

### WORLD

Does the world feel large?

Does it feel connected?

Are there meaningful places to explore?

### FARM

Is farming satisfying?

Do actions have visual/audio feedback?

### NPCs

Do villagers feel alive?

Do they move according to schedules?

Do they remember relationships?

### DIALOGUE

Is dialogue readable?

Does it show portraits?

Does it respond to context?

### STORY

Are important moments cinematic?

### AUDIO

Does the world sound alive?

### UI

Is the interface clear?

### MAP

Can the player understand where they are?

### MINIMAP

Can the player navigate naturally?

### CROSSHAIR

Is the `+` crosshair subtle and useful?

### CONTENT

Does the game have enough content to feel complete?

### PERFORMANCE

Can the game run for long sessions without degrading?

### SAVE

Can players save and reload safely?

### POLISH

Does it feel like a real game?

---

# 71. ABSOLUTE RULES

Never:

* switch to Unity
* reintroduce Unity
* use Three.js as the game engine
* rebuild the game as a web application
* replace Godot with another engine
* rewrite everything unnecessarily
* artificially limit content
* create fake features
* create fake tests
* use copyrighted Stardew assets
* copy Stardew dialogue
* copy Stardew maps
* copy Stardew music
* create meaningless language files
* introduce unnecessary dependencies
* delete working architecture without justification
* leave major systems as placeholders

---

# 72. WHEN A FEATURE IS COMPLETE

A feature is complete only when:

1. It works.
2. It is connected to the actual game.
3. It is playable.
4. It has proper feedback.
5. It has audio where appropriate.
6. It has visual feedback where appropriate.
7. It saves correctly where applicable.
8. It is tested.
9. It has no known critical errors.
10. Documentation is updated.

---

# 73. DEVELOPMENT REPORT

After every major milestone, update:

`DEVELOPMENT_STATUS.md`

Use:

```text
STATUS:
COMPLETED:
FILES CHANGED:
TESTS:
MANUAL VERIFICATION:
PERFORMANCE:
KNOWN ISSUES:
NEXT:
```

Do not claim something is complete when it has not been tested.

---

# 74. FINAL DEFINITION OF DONE

Hollowbrook Hollow is complete when a new player can:

1. Launch the game.
2. Create a character.
3. Start a farm.
4. Learn the controls.
5. Explore a large connected world.
6. Use the world map.
7. Use the minimap.
8. Farm.
9. Fish.
10. Forage.
11. Raise animals.
12. Craft.
13. Cook.
14. Mine.
15. Fight monsters.
16. Upgrade equipment.
17. Earn money.
18. Visit shops.
19. Meet villagers.
20. Follow NPC schedules.
21. Build friendships.
22. Give gifts.
23. Romance characters.
24. Marry.
25. Complete quests.
26. Attend festivals.
27. Experience story events.
28. Experience cinematic cutscenes.
29. Hear environmental sounds.
30. Hear action sound effects.
31. Experience dynamic music.
32. See seasonal changes.
33. Experience weather.
34. Complete the main story.
35. See the ending.
36. Continue playing afterward.
37. Save.
38. Reload.
39. Change settings.
40. Play with keyboard/mouse.
41. Play with controller.
42. Play for long sessions reliably.

---

# 75. FINAL PHILOSOPHY

Do not build Hollowbrook Hollow as:

> "a Stardew clone with 3D graphics."

Build it as:

> **an original first-person 3D farming/life-simulation adventure with a huge living world, memorable characters, deep systems, cinematic storytelling, dynamic audio, exploration, progression and unlimited expandable content.**

The player should enter the world and think:

# "This is a real place."

They should hear the wind.

They should hear footsteps.

They should hear the river.

They should hear rain.

They should see villagers going about their lives.

They should see the seasons change.

They should farm.

They should explore.

They should fish.

They should mine.

They should fight.

They should build relationships.

They should experience stories.

They should watch cinematic events.

They should open the map and understand the valley.

They should glance at the minimap and know where they are.

They should see the clean `+` crosshair in first-person.

They should talk to villagers through polished dialogue boxes.

They should feel that their actions matter.

And all systems must work together as one coherent game.

---

# START NOW

Do NOT immediately begin adding random features.

First:

1. Inspect the existing repository.
2. Understand its architecture.
3. Reproduce the current state.
4. Identify existing systems.
5. Identify existing tests.
6. Identify current Godot version.
7. Identify available .NET/C# tooling.
8. Identify available C/C++ tooling.
9. Establish the 8-group architecture.
10. Establish the multi-language architecture.
11. Document the architecture.
12. Verify the build.
13. Verify the tests.
14. Create a prioritized implementation roadmap.
15. Then begin implementation.

Preserve working systems.

Fix root causes.

Add regression tests.

Integrate features properly.

Do not create fake implementations.

Do not impose artificial content limits.

Build the game until it is genuinely complete. # 76. OPENCODE EXECUTION & REPORTING RULES

These rules govern how OpenCode and all development groups operate on the Hollowbrook Hollow repository.

The goal is to make development:

* organized
* parallel where safe
* deterministic
* testable
* traceable
* recoverable
* integration-safe

The 8 groups are development ownership boundaries, not isolated games.

All groups ultimately contribute to one integrated Godot project.

---

## 76.1 EIGHT GROUP OWNERSHIP

Use exactly these groups:

```text
GROUP 1 — CORE & ARCHITECTURE
GROUP 2 — WORLD & ENVIRONMENT
GROUP 3 — GAMEPLAY & SIMULATION
GROUP 4 — NPCs & AI
GROUP 5 — STORY & CONTENT
GROUP 6 — UI & PLAYER EXPERIENCE
GROUP 7 — AUDIO & VISUAL PRESENTATION
GROUP 8 — QA, PERFORMANCE & RELEASE
```

Each group must remain within its ownership area unless cross-group work is explicitly required.

---

## 76.2 ORCHESTRATOR

One OpenCode process acts as the:

# ORCHESTRATOR

The orchestrator is responsible for:

* planning
* task assignment
* dependency ordering
* integration
* conflict resolution
* final verification
* documentation synchronization
* milestone completion
* release decisions

The orchestrator must understand the entire project.

Workers should focus on their assigned group.

---

## 76.3 WORKER RULE

A worker must:

1. Read the project instructions.
2. Read the relevant architecture documentation.
3. Read the current development status.
4. Inspect existing implementation before modifying it.
5. Understand dependencies.
6. Work only on assigned tasks.
7. Test changes.
8. Report exactly what changed.
9. Report how it was verified.
10. Report remaining issues.

Never blindly overwrite existing code.

---

## 76.4 SHARED TREE RULE

All groups work against the same repository.

Therefore:

### Workers MUST NOT:

* reset the repository
* delete another group's work
* force checkout another branch
* run destructive git commands
* rewrite unrelated files
* stash another group's work
* overwrite unknown changes
* revert another group's implementation
* mass-format unrelated files

If unexpected changes are found:

```text
STOP
↓
INSPECT
↓
IDENTIFY OWNER
↓
COORDINATE
↓
CONTINUE
```

Do not destroy unknown work.

---

## 76.5 COMMIT OWNERSHIP

Only the orchestrator performs final integration commits.

Workers should not independently create repository-wide commits unless specifically instructed.

Workers may prepare changes and report them.

The orchestrator decides:

* what gets integrated
* when it gets integrated
* commit boundaries
* milestone tags
* release commits

---

## 76.6 TASK CREATION

Every implementation task must have:

```text
TASK ID
GROUP
OBJECTIVE
DEPENDENCIES
FILES / SYSTEMS
ACCEPTANCE CRITERIA
TEST PLAN
STATUS
```

Example:

```text
TASK:
G3-FARM-001

GROUP:
Gameplay & Simulation

OBJECTIVE:
Implement crop growth progression.

DEPENDENCIES:
Time system
Season system
Crop Resource definitions

ACCEPTANCE:
Crop advances through valid growth stages.
Season rules are respected.
Watering affects growth.
Harvest produces correct item.
Save/load preserves crop state.

TEST:
Automated crop progression test.
Save/load regression test.

STATUS:
IN PROGRESS
```

---

## 76.7 TASK STATES

Every task uses one of these states:

```text
PLANNED
READY
IN PROGRESS
BLOCKED
IN REVIEW
VERIFIED
INTEGRATED
DONE
REJECTED
```

Never mark a task `DONE` merely because code was written.

---

## 76.8 DEPENDENCY RULE

Do not start a task whose required dependency does not exist unless the work is explicitly designed as parallel preparation.

Example:

```text
Core Time System
        ↓
Crop Growth
        ↓
Crop Harvest
        ↓
Inventory
        ↓
Economy
```

If Crop Growth requires the Time System API, the worker must either:

* wait for the Time System, or
* work against an agreed documented interface.

Do not create incompatible temporary APIs that become permanent technical debt.

---

## 76.9 PARALLEL EXECUTION

Parallel work is encouraged when tasks are independent.

Safe example:

```text
GROUP 2 → world environment
GROUP 3 → crop simulation
GROUP 7 → audio
```

These can proceed simultaneously if their interfaces are clear.

Unsafe example:

```text
Worker A edits PlayerController
Worker B rewrites PlayerController
```

Do not allow simultaneous ownership of the same critical implementation.

---

## 76.10 FILE OWNERSHIP

Prefer clear ownership.

Example:

```text
scripts/world/          → Group 2
scripts/simulation/     → Group 3
scripts/npcs/           → Group 4
scripts/story/          → Group 5
scripts/ui/             → Group 6
scripts/audio/          → Group 7
tests/                  → Group 8
core/shared/            → Group 1
```

This is guidance, not permission to create unnecessary duplicate systems.

If an existing project structure differs, preserve the established architecture and document the ownership mapping.

---

## 76.11 CROSS-GROUP CHANGES

A feature may require multiple groups.

Example:

```text
Fishing
    ↓
Gameplay & Simulation
    ↓
UI
    ↓
Audio
    ↓
NPC/Quest integration
    ↓
QA
```

Assign one group as the:

# FEATURE OWNER

Other groups become:

# SUPPORT GROUPS

The feature owner remains responsible for integration.

---

## 76.12 API CONTRACTS

Before a cross-group system is implemented, define its interface.

Example:

```text
CropSystem
    get_growth_stage()
    water()
    harvest()
    get_quality()
```

The implementation may change internally.

The contract should remain stable unless the orchestrator approves a breaking change.

---

## 76.13 EVENTBUS RULE

Use the project's EventBus for cross-system events where appropriate.

Examples:

```text
crop_harvested
item_added
item_sold
fish_caught
npc_friendship_changed
quest_completed
festival_started
cutscene_started
cutscene_finished
player_level_up
weather_changed
season_changed
day_started
day_ended
```

Do not create dozens of competing global event systems.

---

## 76.14 DATA-FIRST RULE

When adding large content sets, prefer data-driven resources.

Do not create:

```text
300 separate hard-coded conditional branches
```

Prefer:

```text
Item Resources
Crop Resources
Fish Resources
NPC Resources
Dialogue Resources
Quest Resources
Recipe Resources
```

Content expansion must remain easy.

---

## 76.15 UNLIMITED CONTENT RULE

OpenCode must never interpret minimum requirements as maximum limits.

For example:

```text
30+ crops
```

means:

```text
minimum = 30
maximum = unlimited
```

The same applies to:

* fish
* NPCs
* items
* quests
* dialogue
* recipes
* festivals
* monsters
* locations
* cutscenes
* sounds

Do not stop content development merely because the minimum target was reached.

Stop when the design milestone is complete.

---

## 76.16 IMPLEMENTATION RULE

Do not generate massive amounts of code in one uncontrolled operation.

Use incremental implementation:

```text
Design
↓
Interface
↓
Small implementation
↓
Test
↓
Integrate
↓
Expand
↓
Test again
```

For large systems:

```text
Foundation
↓
Core functionality
↓
Integration
↓
Content
↓
Polish
↓
Optimization
```

---

## 76.17 TEST AFTER EVERY SIGNIFICANT CHANGE

After a significant implementation:

1. Run relevant automated tests.
2. Run project validation.
3. Run boot validation.
4. Run affected gameplay tests.
5. Check for script errors.
6. Check save/load if affected.
7. Check integration with dependent systems.

Do not accumulate hundreds of unverified changes.

---

## 76.18 VALIDATION

Use the repository's canonical validation tooling.

Where available, run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/check.ps1
```

Also use the project's Godot validation commands documented in `AGENTS.md`.

For headless testing, use the repository's configured Godot executable.

Do not invent a different validation system when an existing canonical one exists.

---

## 76.19 WINDOWS COMMAND RULE

The project path contains a space:

```text
C:\mohan\Game\Stardew dmeo
```

Therefore all commands must correctly quote paths.

Do not assume:

```text
godot
```

is globally available.

Use the repository's portable Godot executable when required.

Do not assume:

```text
pwsh
```

exists.

If PowerShell 7 is unavailable, use Windows PowerShell 5.1-compatible commands.

---

## 76.20 SCRIPT ERROR RULE

A task cannot be considered verified if the relevant run produces:

```text
SCRIPT ERROR
```

or another fatal runtime error.

Warnings should be investigated when relevant.

Never hide errors merely to make a validation command pass.

---

## 76.21 NO FALSE SUCCESS

Never report:

```text
DONE
```

when the implementation is:

* incomplete
* untested
* mocked
* disconnected
* placeholder-only
* known to crash
* known to corrupt saves
* missing required integration

Instead report:

```text
BLOCKED
```

or:

```text
IN PROGRESS
```

with the exact reason.

---

## 76.22 FAILURE HANDLING

If a task fails:

Do NOT immediately rewrite everything.

Use:

```text
Failure
↓
Capture error
↓
Identify root cause
↓
Check recent changes
↓
Fix smallest correct layer
↓
Run regression test
↓
Re-run original test
```

---

## 76.23 BLOCKED TASKS

If blocked, report:

```text
BLOCKED BY:
REQUIRED FROM:
WHY:
TEMPORARY WORKAROUND:
WHAT CAN CONTINUE:
```

Example:

```text
BLOCKED BY:
Navigation mesh generation

REQUIRED FROM:
World & Environment

WHY:
NPC navigation cannot be validated without navigable world geometry.

TEMPORARY WORKAROUND:
AI decision logic can continue independently.

WHAT CAN CONTINUE:
Schedule data and dialogue logic.
```

---

## 76.24 REGRESSION RULE

Every bug fix must include a regression test when practical.

Example:

```text
BUG:
Player could fish outside the pond.

FIX:
Interaction validation now checks valid fishing water.

REGRESSION:
Added pond-boundary fishing test.
```

Never repeatedly fix the same class of bug without adding protection.

---

## 76.25 SAVE SAFETY

Any modification to persistent state must consider:

* new game
* save
* reload
* older save
* missing data
* default values
* version migration

If a system changes save data:

```text
Test:
new save
save
reload
old save
migration
```

---

## 76.26 CONTENT VALIDATION

When adding content, automatically validate:

* IDs
* references
* required fields
* duplicate IDs
* missing resources
* invalid paths
* broken dialogue references
* invalid NPC schedules
* invalid quest conditions
* invalid item references
* missing audio
* missing portraits
* missing cutscene actors

Large content sets must remain maintainable.

---

## 76.27 VISUAL VERIFICATION

Automated tests alone are not sufficient for visual features.

For:

* UI
* minimap
* crosshair
* dialogue
* portraits
* cutscenes
* lighting
* weather
* animations
* world presentation

perform actual runtime verification.

Check:

* placement
* scale
* readability
* clipping
* animation
* transitions
* performance

---

## 76.28 AUDIO VERIFICATION

For audio features verify:

* correct sound plays
* correct timing
* volume
* looping
* transitions
* no unwanted overlap
* correct mixer category
* settings affect volume
* audio stops/changes correctly during cutscenes

Do not merely verify that an audio file exists.

---

## 76.29 CUTSCENE VERIFICATION

Every important cutscene must verify:

```text
camera
actor movement
dialogue
audio
music
player lock
story flags
quest updates
effects
skip
pause
resume
state restoration
```

Especially verify:

```text
Cutscene
↓
Skip
↓
Player control restored
↓
Story state correct
```

---

## 76.30 PERFORMANCE REPORTING

Performance work must report actual measurements.

Do not say:

```text
Performance improved.
```

Say:

```text
Before:
average FPS = X
frame time = Y ms

After:
average FPS = X
frame time = Y ms

Scenario:
large farm + 20 NPCs + rain

Change:
NPC update batching
```

Use measured data whenever possible.

---

## 76.31 MILESTONE EXECUTION

Use milestones.

Each milestone must have:

```text
OBJECTIVE
REQUIRED FEATURES
DEPENDENCIES
IMPLEMENTATION
TESTS
MANUAL VERIFICATION
PERFORMANCE
DOCUMENTATION
STATUS
```

Do not declare a milestone complete until all acceptance criteria pass.

---

## 76.32 DAILY / SESSION START

At the beginning of an OpenCode session:

1. Read `AGENTS.md`.
2. Read `DEVELOPMENT_STATUS.md`.
3. Read relevant architecture documentation.
4. Inspect current repository status.
5. Identify unfinished tasks.
6. Identify blockers.
7. Select the highest-priority unblocked task.
8. Check for changes made since the previous session.

Do not assume the repository is unchanged.

---

## 76.33 SESSION END

At the end of a development session:

1. Run relevant tests.
2. Run validation.
3. Update documentation.
4. Update `DEVELOPMENT_STATUS.md`.
5. Record incomplete work.
6. Record known issues.
7. Record next actions.
8. Report exact verification status.

---

## 76.34 STANDARD WORKER REPORT

Every worker must end its task with exactly this structure:

```text
DONE | <task ID>

GROUP:
<group name>

OBJECTIVE:
<what was intended>

IMPLEMENTED:
<what actually changed>

FILES CHANGED:
<files>

SYSTEMS AFFECTED:
<systems>

TESTS:
<tests executed>

VALIDATION:
<validation commands/results>

MANUAL VERIFICATION:
<what was tested manually>

PERFORMANCE:
<measurements or N/A>

OPEN ISSUES:
<remaining issues or NONE>

BLOCKED BY:
<dependency or NONE>

NEXT:
<recommended next action>
```

---

## 76.35 ORCHESTRATOR REPORT

The orchestrator must provide a milestone-level report:

```text
MILESTONE:
<name>

STATUS:
<PLANNED / IN PROGRESS / BLOCKED / VERIFIED / DONE>

GROUP STATUS:

1. Core & Architecture:
<status>

2. World & Environment:
<status>

3. Gameplay & Simulation:
<status>

4. NPCs & AI:
<status>

5. Story & Content:
<status>

6. UI & Player Experience:
<status>

7. Audio & Visual Presentation:
<status>

8. QA, Performance & Release:
<status>

COMPLETED:
<summary>

TESTS:
<summary>

VALIDATION:
<summary>

KNOWN ISSUES:
<summary>

BLOCKERS:
<summary>

NEXT MILESTONE:
<summary>
```

---

## 76.36 REPORTING LANGUAGE

Use precise language.

Good:

```text
Implemented crop growth logic and verified 47 crop definitions.
```

Bad:

```text
Finished farming.
```

Good:

```text
Minimap renders player position, nearby buildings and quest markers.
```

Bad:

```text
Map done.
```

Good:

```text
Cutscene skip restores player control and applies story flag.
```

Bad:

```text
Cutscene system completed.
```

---

## 76.37 NO INFLATED REPORTS

Do not report content counts unless they were actually measured.

If the project contains:

```text
37 crops
```

report:

```text
37 crop definitions validated.
```

Do not claim:

```text
50 crops
```

because the architecture can support 50.

---

## 76.38 AUTOMATION

Automate repetitive work whenever useful.

Examples:

* content validation
* resource generation
* duplicate ID checking
* save compatibility checks
* asset verification
* dialogue validation
* item validation
* economy reports
* long simulation
* build verification

But automation must produce meaningful results.

Do not create scripts that merely print:

```text
PASS
```

without actually testing anything.

---

## 76.39 CODE QUALITY

Prefer:

* small systems
* clear ownership
* typed data
* reusable components
* data-driven resources
* deterministic simulation
* testable logic
* documented interfaces

Avoid:

* giant scripts
* global state everywhere
* circular dependencies
* duplicated logic
* magic numbers
* hidden dependencies
* unnecessary language bridges

---

## 76.40 ARCHITECTURE CHANGES

If an existing architectural decision must change:

1. Explain why.
2. Identify affected systems.
3. Update `docs/DECISIONS.md`.
4. Update architecture documentation.
5. Update tests.
6. Migrate existing code.
7. Verify the project.
8. Record the change in the development report.

Do not silently change foundational architecture.

---

## 76.41 TECHNOLOGY CHANGE RULE

Adding a new language, library, addon or framework requires a justification.

Report:

```text
TECHNOLOGY:
<name>

PURPOSE:
<reason>

WHY EXISTING TECHNOLOGY IS INSUFFICIENT:
<reason>

BENEFIT:
<reason>

COST:
<reason>

MAINTENANCE:
<reason>

DECISION:
<approved/rejected>
```

---

## 76.42 NO TECHNOLOGY FOR DECORATION

Do not add:

* C#
* C++
* Python
* SQL
* shaders
* external libraries

just to increase the number of technologies.

Every technology must solve a real problem.

---

## 76.43 GROUP COORDINATION

Groups communicate through:

* documented APIs
* resources
* EventBus
* task reports
* development status
* architecture documents

Do not communicate only through assumptions.

---

## 76.44 INTEGRATION ORDER

When multiple groups finish related work:

```text
1. Core
2. World / Simulation foundations
3. NPC / Story dependencies
4. UI
5. Audio / Presentation
6. QA
7. Performance
8. Release
```

However, independent work may continue in parallel.

---

## 76.45 INTEGRATION CHECKPOINT

Before integrating a major feature:

```text
BUILD
TEST
LOAD
SAVE
PLAY
CHECK UI
CHECK AUDIO
CHECK DEPENDENCIES
CHECK PERFORMANCE
```

Then integrate.

---

## 76.46 PLAYABLE BUILD RULE

At reasonable milestones, maintain a playable build.

Do not allow the repository to remain broken for long periods while every system is being rewritten.

If a large migration is required:

```text
old working state
↓
migration branch/state
↓
incremental migration
↓
tests
↓
playable state
```

---

## 76.47 NEVER SACRIFICE PLAYABILITY

New architecture must not permanently destroy:

* player movement
* world loading
* new game
* save/load
* basic gameplay

Keep the project recoverable.

---

## 76.48 FINAL QA GATE

Before calling the entire project complete:

### BUILD

* clean build
* no fatal errors

### GAMEPLAY

* new game works
* player movement works
* interaction works
* farming works
* fishing works
* mining works
* combat works
* animals work
* crafting works
* cooking works
* economy works

### WORLD

* world loads
* map works
* minimap works
* seasons work
* weather works
* day/night works

### NPC

* schedules work
* dialogue works
* relationships work
* romance works
* marriage works

### STORY

* quests work
* festivals work
* cutscenes work
* skip works
* ending works
* free play works

### AUDIO

* music works
* SFX work
* ambience works
* dynamic transitions work

### UI

* HUD works
* inventory works
* menus work
* map works
* minimap works
* crosshair works
* accessibility works
* controller works

### SAVE

* save works
* reload works
* multiple slots work
* migration works

### QA

* automated tests pass
* regression tests pass
* long simulation passes
* no known critical issues

---

## 76.49 FINAL REPORT

The final report must contain:

```text
HOLLOWBROOK HOLLOW
FINAL DEVELOPMENT REPORT

ENGINE:
Godot 4.5

LANGUAGES:
GDScript
C#
C++ / GDExtension where justified
Godot Shader Language
Python tooling
PowerShell tooling
Data formats

GROUPS:
8

CONTENT:
Minimum requirements exceeded where applicable.

WORLD:
<summary>

GAMEPLAY:
<summary>

NPCs:
<summary>

STORY:
<summary>

DIALOGUE:
<summary>

CUTSCENES:
<summary>

AUDIO:
<summary>

UI:
<summary>

MAP:
<summary>

MINIMAP:
<summary>

SAVE SYSTEM:
<summary>

TESTING:
<summary>

PERFORMANCE:
<summary>

RELEASE:
<summary>

KNOWN ISSUES:
<summary>

FINAL VALIDATION:
PASS / FAIL
```

---

## 76.50 GOLDEN RULE

The most important execution rule is:

> **Never confuse "code written" with "feature complete."**

A feature is complete only when:

```text
IMPLEMENTED
+
INTEGRATED
+
PLAYABLE
+
TESTED
+
VERIFIED
+
DOCUMENTED
```

And the most important reporting rule is:

> **Always report what is actually true, not what you intended to build.**

The orchestrator must keep the project moving toward a single goal:

# A COMPLETE, PLAYABLE, POLISHED, ORIGINAL HOLLOWBROOK HOLLOW GAME.
