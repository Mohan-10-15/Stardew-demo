# GODOT MASTER BUILD PROMPT — HOLLOWBROOK HOLLOW
## OpenCode / OpenCode4 continuation prompt
## Engine: Godot 4.x | Language: GDScript 2.0 | Target: Windows + Web export
## Project: existing repository, not a new prototype

You are continuing an existing Godot game project. DO NOT replace it with Unity, Three.js,
TypeScript, React, or another engine/framework.

The uploaded/current project is already a Godot 4.x project named "Hollowbrook Hollow".
It already contains core services, a player controller, first/third-person camera support,
interaction raycasting, procedural world generation, scenes, resources, automated tests,
and development tooling. Preserve useful existing work and evolve it into the complete game.

The design goal is:

A COMPLETE ORIGINAL 3D farming/life-simulation/adventure game inspired by the gameplay
loop of games such as Stardew Valley, but experienced primarily from a Minecraft-style
first-person 3D perspective.

This is NOT a demo, prototype, vertical slice, mock-up, or collection of disconnected
systems.

A stranger should be able to start a new game, learn the controls, farm, explore,
interact with NPCs, complete quests, experience story scenes/cutscenes, fish, craft,
cook, raise animals, enter mines, fight enemies, improve relationships, attend festivals,
reach the main ending, continue playing afterward, save/reload, and eventually play for
dozens of hours.

All game content must be ORIGINAL. Do not copy Stardew Valley characters, names, maps,
dialogue, music, sprites, story, UI, or other copyrighted assets. Use the genre and
high-level gameplay ideas only as inspiration.

============================================================
0. NON-NEGOTIABLE RULE: FIX THE EXISTING PROJECT FIRST
============================================================

Before adding major features:

1. Read:
   - README.md
   - DEVELOPMENT_STATUS.md
   - project.godot
   - every file under scripts/core/
   - player/camera/interaction scripts
   - current scenes
   - current resources
   - current tests
   - tools/check.ps1 and boot-check tooling
   - any existing docs/ files

2. Inspect the actual repository state. Do not trust DEVELOPMENT_STATUS.md blindly.

3. Run the existing validation commands.
   Prefer:
       pwsh -File tools/check.ps1

   Also run appropriate Godot headless checks, import checks, tests, and boot checks.

4. Reproduce the CURRENT BUG/FAILURE before changing unrelated systems.

5. Identify:
   - exact error
   - exact file
   - exact line or system
   - root cause
   - why the existing test suite did not catch it

6. Fix the root cause, not merely the visible symptom.

7. Add a regression test for the bug.

8. Run the full existing test suite again.

9. Do not continue to major feature work until the project boots and the regression test
   passes.

IMPORTANT:
The project status currently says there are no known issues, so if the user reports a
bug that is not documented, treat the actual runtime/reproduction result as authoritative.
Do NOT invent a bug and do NOT claim it was fixed unless you reproduced and verified it.

If the project cannot be run because Godot is unavailable in the current environment,
perform static analysis and code inspection, clearly record the limitation, and still
fix demonstrable code defects. Do not falsely report runtime verification.

============================================================
1. GAME VISION
============================================================

Working title:
    Hollowbrook Hollow

Keep the title if it already exists unless the project already contains a better,
deliberately chosen original title. Do not rename randomly.

Core fantasy:

"You inherited a neglected homestead on the edge of a strange valley. Rebuild the farm,
learn the valley's history, form relationships with its people, explore dangerous places,
and uncover why the valley is changing."

Primary perspective:
    First-person 3D, Minecraft-like player viewpoint.

Optional:
    A polished third-person camera may remain available as an accessibility/exploration
    option, but first-person is the default identity of the game.

The player should feel:
    - physically present in the world
    - able to look at objects and interact with them directly
    - able to hold/use tools in first person
    - able to enter buildings
    - able to talk to people face-to-face
    - able to see weather and seasonal changes
    - able to trigger cinematic story scenes naturally
    - able to explore rather than only click menus

Visual direction:
    - stylized 3D
    - cozy but atmospheric
    - readable low-poly / semi-stylized environment
    - warm natural materials
    - strong environmental storytelling
    - attractive lighting
    - soft shadows
    - volumetric/atmospheric effects where performance allows
    - no generic neon "cybersecurity" aesthetic
    - no unfinished grey-box presentation in release builds

Use CC0/permissive assets where external assets are needed and record licenses in:
    docs/ASSET_LICENSES.md

If suitable assets are unavailable, use procedural/generated Godot meshes as a temporary
implementation, but create an asset abstraction so they can later be replaced cleanly.

============================================================
2. CURRENT GODOT ARCHITECTURE — PRESERVE AND IMPROVE
============================================================

Use Godot 4.x and GDScript 2.0.

Do not migrate the project to another engine.

Preserve the existing concepts:
    - EventBus autoload
    - GameState
    - Config
    - Log
    - Debug
    - PlayerController
    - CameraRig
    - InteractionProbe
    - WorldRoot / WorldBuilder
    - existing scene generation tools
    - existing test harness
    - existing deterministic world-generation approach

Improve architecture when necessary rather than rewriting everything.

Recommended structure:

scripts/
    core/
    player/
    camera/
    interaction/
    world/
    time/
    weather/
    seasons/
    farming/
    inventory/
    tools/
    items/
    crafting/
    cooking/
    fishing/
    animals/
    buildings/
    mining/
    combat/
    npc/
    dialogue/
    quests/
    cutscenes/
    relationships/
    festivals/
    economy/
    save/
    audio/
    ui/
    accessibility/
    debug/

scenes/
    core/
    player/
    world/
    farming/
    buildings/
    npc/
    animals/
    enemies/
    items/
    ui/
    cutscenes/
    interiors/
    mines/

resources/
    config/
    items/
    crops/
    recipes/
    npcs/
    dialogue/
    quests/
    maps/
    festivals/
    audio/
    cutscenes/

assets/
    models/
    textures/
    animations/
    audio/
    ui/

tests/
    suites/

docs/
    GDD.md
    ARCHITECTURE.md
    ROADMAP.md
    TASKS.md
    DECISIONS.md
    ASSET_LICENSES.md
    ACCEPTANCE.md
    CUTSCENE_GUIDE.md

Every major system should be modular and testable.

============================================================
3. PLAYER EXPERIENCE
============================================================

Default first-person controls:

WASD
    movement

Mouse
    look

Shift
    sprint

Space
    jump if jumping is enabled in the current design

E
    interact / talk / pick up / open / use

Left mouse
    primary tool/use action

Right mouse
    secondary tool/use action where applicable

1-9
    hotbar

Mouse wheel
    hotbar selection

I
    inventory

J
    journal/quests

Esc
    pause

V
    optional first/third-person camera switch

All controls must be remappable.

Gamepad support must be implemented.

Interaction should be contextual:
    look at a tree -> "Chop"
    look at soil -> "Till"
    look at crop -> "Water" / "Harvest"
    look at NPC -> "Talk"
    look at door -> "Enter"
    look at chest -> "Open"
    look at item -> "Pick up"

Do not make the player memorize dozens of interaction keys.

============================================================
4. WORLD
============================================================

Build a coherent connected valley, not a set of disconnected test rooms.

Required major areas:

1. Player farm
2. Village
3. Player house
4. General shop
5. Blacksmith
6. Carpenter/building shop
7. Animal/ranch shop
8. Tavern/cafe
9. Forest
10. River
11. Lake
12. Beach/coast
13. Mountain
14. Mine entrance
15. Mine floors
16. Secret/story locations
17. Festival/event spaces
18. Additional unlocked late-game area

Buildings must have interiors where appropriate.

World transitions should be seamless or use polished transition scenes.

Use deterministic world seeds where procedural generation is appropriate.

The world must support:
    - day/night
    - seasons
    - weather
    - environmental ambience
    - NPC schedules
    - wildlife
    - resource respawn
    - farm persistence
    - story state

============================================================
5. TIME / CALENDAR
============================================================

Implement:

4 seasons.

28 days per season.

Day progression with a readable clock.

Morning -> daytime -> evening -> night.

Player energy.

Health.

Stamina.

Passing out / exhaustion.

Sleeping.

End-of-day summary.

Daily events.

NPC schedules.

Crop growth.

Animal production.

Machine processing.

Resource regeneration.

Fishing availability.

Shop hours.

Quest deadlines where appropriate.

Festivals.

Birthdays.

Weather forecasts.

Time must be deterministic and saveable.

Do not use scattered timers throughout unrelated scripts.
Create a central time/calendar service.

============================================================
6. FARMING
============================================================

Complete farming loop:

clear debris
    ->
till soil
    ->
plant seed
    ->
water
    ->
fertilize
    ->
growth
    ->
harvest
    ->
sell/process/cook

Implement:

30+ crops.

Multiple growth stages.

Season restrictions.

Regrowing crops.

Fruit trees.

Crop quality.

Crop health.

Watering.

Rain auto-watering.

Fertilizer.

Weeds.

Dead/neglected crops where appropriate.

Sprinklers.

Scarecrows.

Greenhouse.

Farm decorations.

Placeable objects.

Farm buildings.

House upgrades.

Animal buildings.

Tool upgrades.

Farming sound effects.

Tool animations.

Particle effects.

Readable first-person feedback.

The farming system must persist through save/load.

============================================================
7. TOOLS
============================================================

Implement:

Hoe
Watering Can
Axe
Pickaxe
Scythe
Fishing Rod

At least 4 upgrade tiers where appropriate.

Tool use must feel physical in first person.

Include:
    - animation
    - sound
    - particles
    - hit feedback
    - resource changes
    - stamina/energy cost
    - correct tool restrictions
    - upgrade progression

Do not make tools just invisible database buttons.

============================================================
8. INVENTORY / ITEMS
============================================================

Create a proper item database.

At least 300 item definitions over the completed game.

Categories:

seeds
crops
produce
forageables
fish
ore
gems
wood
stone
monster drops
food
cooked meals
tools
weapons
armor
rings/accessories
quest items
building materials
machines
decorations
animal products

Inventory:
    - stack sizes
    - item quality
    - durability where appropriate
    - hotbar
    - backpack expansion
    - drag/drop
    - split stacks
    - discard
    - item tooltips
    - sorting
    - save/load

============================================================
9. ECONOMY
============================================================

Implement:

money
shipping bin
shops
buying
selling
tool upgrades
building costs
seasonal prices/stock
quality-based prices
traveling merchant
quest rewards

Required shops:

General Store
Blacksmith
Carpenter
Ranch
Fishing shop
Traveling Merchant

Do not hard-code prices throughout gameplay scripts.
Use centralized data.

Create an economy balance report tool.

============================================================
10. FISHING
============================================================

Implement a real fishing system.

30+ fish.

Fish gated by:
    - location
    - season
    - time
    - weather
    - player skill

Include:
    - casting
    - bite
    - hook
    - minigame
    - fish movement
    - line tension
    - success/failure
    - bait
    - tackle
    - fishing skill
    - rare fish

Fishing should have dedicated audio and visual feedback.

============================================================
11. ANIMALS
============================================================

At least 5 animal species.

Examples:
    chickens
    cows
    sheep
    goats
    ducks

Also:
    - pet
    - rideable horse

Implement:

purchase
housing
feeding
friendship
daily production
quality
happiness
neglect
products
animal animations
animal sounds
barn/coop interaction
animal UI

============================================================
12. CRAFTING / COOKING
============================================================

Implement:

crafting station system
recipe unlocks
ingredient checking
crafting time where appropriate
processing machines
machine queues
machine output
cooking
recipes
buffs
food consumption

At least 8 processing machine types.

Cooking should have meaningful gameplay effects.

============================================================
13. SKILLS
============================================================

Skills:

Farming
Foraging
Mining
Fishing
Combat

Levels:
    1-10

XP must come from actual gameplay.

At levels 5 and 10:
    profession choices

Profession choices must affect gameplay.

Unlock:
    recipes
    tool efficiency
    new mechanics
    bonuses

Persist all skill state.

============================================================
14. MINES
============================================================

Build 40+ deterministic mine floors.

Seeded generation.

Each seed should produce reproducible layouts.

Include:
    - rocks
    - ore
    - gems
    - ladders
    - hazards
    - enemies
    - treasure
    - checkpoints every 5 floors
    - environmental variations
    - late-game sections

The mine must not feel like a flat test room.

============================================================
15. COMBAT
============================================================

Implement readable first-person combat.

Weapons.

At least 12 enemy types.

Different AI behaviours.

Examples:
    melee
    ranged
    charging
    defensive
    flying
    ambush

Include:

attack
damage
health
hit reactions
stagger
death
loot
telegraphs
blocking/defense where appropriate
weapons
armor
rings/accessories
bosses

At least 2 bosses.

Bosses need:
    - phases
    - telegraphed attacks
    - unique mechanics
    - sound
    - music changes
    - victory sequence
    - rewards

Combat must be optional in normal farming days but required for certain progression.

============================================================
16. NPC SYSTEM
============================================================

At least 12 original NPCs.

Every important NPC needs:

name
appearance
home
occupation
schedule
season schedule
weather schedule
dialogue
gift tastes
friendship
birthday
story role

NPC schedules must be data-driven.

NPCs should move around the actual world.

Use navigation/pathfinding.

Do not teleport NPCs randomly between locations except when explicitly required by
a story event.

Schedules should respond to:
    - time
    - weather
    - season
    - festival
    - quest state
    - friendship/story state

============================================================
17. DIALOGUE
============================================================

Build a real dialogue system.

Requirements:

dialogue boxes
speaker name
portrait
typing effect
skip
continue
branching choices
conditions
friendship reactions
weather-specific dialogue
season-specific dialogue
quest dialogue
gift dialogue
story dialogue
event dialogue

Dialogue must be data-driven.

No giant hard-coded dialogue strings inside gameplay scripts.

Support localization-ready string IDs.

============================================================
18. RELATIONSHIPS
============================================================

Friendship system.

Heart/relationship levels.

Gift reactions.

Loved/liked/neutral/disliked/hated gifts.

Friendship decay if desired by the design.

Relationship milestones.

At least 3 meaningful scripted heart/story events per major NPC.

At least 6 romanceable characters.

Romance progression.

Dating.

Marriage.

Spouse routine.

Post-marriage dialogue.

Relationship state must persist through save/load.

============================================================
19. QUESTS
============================================================

Quest board.

Main quests.

Side quests.

NPC quests.

Collection quests.

Exploration quests.

Festival quests.

Quest states:

locked
available
accepted
in progress
completed
failed
claimed

Quest objectives should be data-driven.

Rewards can include:
    money
    items
    friendship
    access
    recipes
    upgrades
    story progression

============================================================
20. STORY
============================================================

Create a completely original central mystery/progression.

Example direction:

The valley's old irrigation network and ancient heartwood system are failing.
Restoring the valley requires the player to rebuild community projects, recover lost
knowledge, explore dangerous areas, and understand why the natural world is behaving
strangely.

Do not copy Stardew's corporation/community-center story.

Story structure:

ACT 1
    arrival
    farm restoration
    village introduction

ACT 2
    relationships
    exploration
    first mystery

ACT 3
    deeper mines/forest/mountain
    major reveals

ACT 4
    major restoration/project
    major boss/story event

ACT 5
    final valley event
    ending
    credits

After the ending:
    return to free play.

============================================================
21. CUTSCENE SYSTEM — VERY IMPORTANT
============================================================

Cutscenes are a core feature, not an afterthought.

Build a reusable cinematic system in:

scripts/cutscenes/
scenes/cutscenes/

It must support:

camera control
camera cuts
camera interpolation
camera shake
character movement
NPC animation
player lock
player visibility
look-at targets
dialogue
subtitle text
sound effects
music changes
fade in/out
letterbox bars
screen effects
particles
timed events
animation playback
spawn/despawn
object transforms
environment changes
branch conditions
skip
pause/resume
save-safe state restoration

Create a CutsceneDirector.

Cutscenes should be data-driven where practical.

Example event types:

wait
move_actor
rotate_actor
look_at
camera_move
camera_shake
dialogue
play_animation
play_sound
play_music
fade
set_environment
spawn
despawn
set_flag
give_item
start_quest
complete_quest
teleport_player
unlock_area

Every major story beat must have cinematic presentation.

Required cutscene categories:

1. New game introduction
2. Arrival at farm
3. First village introduction
4. First major NPC event
5. First mine discovery
6. First boss encounter
7. Major seasonal story scenes
8. Relationship heart scenes
9. Romance scenes
10. Marriage ceremony
11. Major restoration/progression scenes
12. Final story sequence
13. Ending/credits scene

The player must never become permanently stuck because a cutscene was interrupted.

If a cutscene is skipped:
    - restore player input
    - restore camera
    - restore time state
    - restore NPC states
    - complete required flags
    - avoid duplicate rewards/events

Create automated tests for cutscene state restoration.

============================================================
22. FESTIVALS
============================================================

At least 8 festivals.

2 per season.

Festivals should temporarily transform an area.

Include:

NPC attendance
special dialogue
festival UI
activities
mini-games
music
decorations
rewards
festival-only items
relationship effects
end-of-festival transition

Do not implement festivals as a static menu.

The player should physically attend the event in the 3D world.

============================================================
23. DAY / NIGHT / WEATHER / SEASONS
============================================================

Day/night must visibly affect:

sun
sky
ambient light
fog
environment
NPC schedules
shop availability
wildlife
audio
music
lighting
crop systems
fishing
enemy behaviour

Weather:

sunny
cloudy
rain
storm
snow
wind

Seasonal visuals:

spring
summer
autumn
winter

Season changes should affect:
    vegetation
    forageables
    crops
    weather
    ambience
    NPC dialogue
    festivals
    fish
    world materials

============================================================
24. AUDIO
============================================================

Audio is mandatory.

Create an AudioManager.

Music:
    - title
    - farm
    - village
    - forest
    - beach
    - mines
    - combat
    - festival
    - cutscene
    - night
    - weather variants

At least 12 music loops/variants in the finished project.

SFX for:

walking
grass
wood
stone
hoe
watering
planting
harvesting
axe
pickaxe
scythe
fishing
inventory
UI
NPC interaction
doors
chests
shops
combat
damage
enemy death
weather
rain
thunder
animals
machines
cooking
level-up
quest completion
festival
cutscenes

Use CC0/permissive audio or generated/synthesized audio.
Record licenses.

Add:

master volume
music volume
SFX volume
ambient volume
UI volume
mute
audio device-safe initialization

============================================================
25. UI / UX
============================================================

Create a polished game UI.

Required:

title screen
new game
load game
settings
pause
HUD
clock
date
season
money
health
energy
hotbar
crosshair
interaction prompt
inventory
backpack
crafting
cooking
map
journal
quests
skills
relationships
collections
shop
dialogue
gift screen
animal screen
farm/building placement
end-of-day summary
festival UI
death/respawn
credits

The HUD must be readable in first person.

Avoid covering too much of the world.

Menus are normal Godot Control/CanvasLayer UI.

Do not build the entire UI as world-space 3D labels.

============================================================
26. SAVE / LOAD
============================================================

At least 3 save slots.

Autosave on sleep.

Manual save where appropriate.

Save:

player position
inventory
hotbar
money
time
date
season
weather state where required
farm state
crop states
trees/resources
buildings
animals
NPC relationships
NPC story flags
quests
cutscene flags
unlocked areas
skills
recipes
collections
settings

Versioned save format.

Migration system.

Corruption-safe handling.

Temporary write then atomic replace where possible.

Backup previous save.

Export save to file.

Import save from file.

Never allow a failed save to silently destroy the previous valid save.

Add save/load regression tests.

============================================================
27. DATA-DRIVEN CONTENT
============================================================

Do not hard-code content into systems.

Use Resource files and/or JSON where appropriate.

Validate data.

Required schemas/resources:

items
crops
recipes
fish
animals
npcs
dialogue
schedules
quests
festivals
cutscenes
maps
shops
weapons
enemies
loot tables

Create validation tooling.

Invalid content should produce a useful error identifying:
    file
    record
    field
    expected type/range

============================================================
28. PERFORMANCE
============================================================

Target:

60 FPS at 1080p on a reasonable integrated GPU on Medium settings.

Use:

visibility/culling
instancing
MultiMesh where appropriate
object pooling
reasonable collision layers
efficient navigation
limited per-frame allocations
LOD where useful
texture-size discipline
audio streaming for long tracks
resource reuse

Do not prematurely optimize at the cost of broken gameplay.

Add graphics presets:

Low
Medium
High

Add debug overlay:

FPS
frame time
player position
current map
time
season
weather
draw statistics where useful

============================================================
29. ACCESSIBILITY
============================================================

Implement:

remappable keyboard controls
gamepad controls
UI scale
text size where practical
subtitles
subtitle background
colorblind-friendly mode
camera sensitivity
invert Y
FOV option
motion/camera shake toggle
audio sliders
screen flash reduction if used

============================================================
30. TESTING
============================================================

Every major system needs automated tests.

Keep the existing test harness.

Add regression tests whenever a bug is found.

Tests should cover:

core services
time
calendar
seasons
weather
inventory
items
farming
crops
tools
economy
crafting
cooking
fishing
animals
skills
NPC schedules
dialogue
relationships
quests
cutscenes
save/load
mine generation
combat
boss logic
world transitions
audio state
settings

Also create integration tests.

Create a headless gameplay bot.

The bot must be able to simulate at least 2 in-game years.

It should detect:
    crashes
    invalid states
    impossible inventories
    negative money
    stuck quests
    crops that cannot progress
    NPC schedule failures
    broken transitions
    cutscene locks
    save/load mismatches
    progression deadlocks

Create:

tools/
    bot_simulation.gd
    validate_content.gd
    economy_report.gd
    build_release.ps1

============================================================
31. ACCEPTANCE TESTS
============================================================

Create/update docs/ACCEPTANCE.md.

M0:
    Project imports.
    No parse errors.
    Game boots.
    Existing player/world/camera systems work.

M1:
    New game -> move -> interact -> save -> reload.

M2:
    Hoe -> plant -> water -> sleep -> crop grows -> harvest -> sell.

M3:
    Farm -> village -> shop -> buy seeds -> return.

M4:
    NPC schedule changes with time/weather.
    Dialogue works.
    Gift changes relationship.

M5:
    Quest can be accepted, progressed and completed.

M6:
    Fishing works.
    Animal works.
    Machine works.
    Cooking works.

M7:
    Mine works.
    Combat works.
    Boss works.

M8:
    Cutscene plays.
    Player can skip it.
    Camera/input state restores correctly.

M9:
    Festival works in physical 3D world.

M10:
    Romance/marriage works.

M11:
    Main progression reaches ending.

M12:
    Ending completes and free play continues.

M13:
    Save/reload preserves the complete state.

M14:
    2-year bot simulation completes without crash or soft-lock.

M15:
    Fresh clone builds using README instructions.

============================================================
32. DEVELOPMENT WORKFLOW
============================================================

Use milestone development.

M0 — Stabilize existing project
M1 — Core player/world/interaction
M2 — Time/calendar
M3 — Farming
M4 — Inventory/tools/economy
M5 — NPCs/dialogue
M6 — Quests/relationships
M7 — Fishing/animals/crafting/cooking
M8 — Mines/combat
M9 — Weather/seasons
M10 — Cutscene/cinematic system
M11 — Buildings/farm upgrades
M12 — Festivals
M13 — Story progression
M14 — Audio
M15 — UI/accessibility
M16 — Save/load
M17 — Art/animation polish
M18 — Performance
M19 — Testing/bot/balance
M20 — Release integration

Do not pretend a milestone is complete because a script exists.
A milestone is complete only when it is playable and tested.

============================================================
33. OPEN CODE / MULTI-AGENT RULES
============================================================

If OpenCode4 is available, use:

ORCHESTRATOR:
    architecture
    contracts
    integration
    debugging
    tests
    documentation
    release validation

WORKER 1 — WORLD / ENGINE:
    world
    rendering
    camera
    lighting
    weather
    seasons
    animation
    environment
    performance
    assets

WORKER 2 — SIMULATION:
    time
    farming
    inventory
    tools
    items
    economy
    crafting
    cooking
    fishing
    animals
    mining
    combat
    skills
    save-state logic

WORKER 3 — PEOPLE / PRESENTATION:
    NPCs
    schedules
    dialogue
    relationships
    quests
    festivals
    cutscenes
    UI
    audio
    accessibility
    tutorial

If only one OpenCode agent is available, work sequentially but keep the same module
ownership and documentation rules.

Before assigning work, inspect the repository and current task state.

Each task must include:

    task ID
    goal
    context
    exact files
    systems affected
    acceptance criteria
    tests required
    files not to modify
    verification command

Workers must NOT randomly rewrite unrelated systems.

============================================================
34. SHARED FILE SAFETY
============================================================

Every file should have an owner.

Workers should avoid editing another worker's module without coordination.

Never overwrite working systems just to make a task easier.

Before destructive refactors:
    inspect references
    update dependencies
    run tests
    preserve behaviour

Do not delete existing tests simply because they fail.

Fix tests only when the test itself is demonstrably incorrect.

Do not weaken assertions to make the suite pass.

============================================================
35. GIT / DOCUMENTATION
============================================================

Maintain:

docs/GDD.md
docs/ARCHITECTURE.md
docs/ROADMAP.md
docs/TASKS.md
docs/DECISIONS.md
docs/ASSET_LICENSES.md
docs/ACCEPTANCE.md
docs/CUTSCENE_GUIDE.md
DEVELOPMENT_STATUS.md

After every meaningful milestone:

    run tests
    update docs
    update status
    commit

Commit messages should be descriptive.

Never report a feature as complete if it is not reachable through normal gameplay.

============================================================
36. NO FAKE IMPLEMENTATION
============================================================

Forbidden:

    placeholder buttons
    "coming soon"
    empty methods
    TODO implementations
    fake quest completion
    fake NPC schedules
    fake save systems
    fake dialogue
    fake cutscenes
    fake combat
    fake fishing
    UI that only looks functional
    hard-coded demo state
    teleporting around instead of implementing navigation
    instant crop growth outside testing
    developer cheats required for normal progression
    disabled systems hidden behind menus

Development cheats are allowed only in a dev-only console and must be stripped/disabled
from release builds.

============================================================
37. CREATIVE QUALITY BAR
============================================================

Do not stop at technically functional.

For each feature ask:

    Does it feel good?
    Does it communicate what happened?
    Does it have audio?
    Does it have animation?
    Does it have visual feedback?
    Does it persist?
    Does it interact with other systems?
    Does it work in first person?
    Does it work with save/load?
    Does it have tests?
    Does it fit the game's visual identity?

Example:

Do not implement "cut tree" as:
    click tree -> tree disappears

Implement:
    player equips axe
    first-person axe animation
    swing sound
    hit particle
    hit reaction
    tree shakes
    wood chips
    multiple hits
    stamina cost
    tree health
    tree falls/collapses
    drops appear
    pickup interaction
    resource count changes
    tree regrowth timer
    save/load persistence

Apply this quality standard to every major mechanic.

============================================================
38. START NOW
============================================================

PHASE 1 — AUDIT

1. Read the entire current project.
2. Build a current architecture map.
3. Run all available checks.
4. Reproduce the reported/current bug.
5. Fix it.
6. Add a regression test.
7. Verify the fix.
8. Update DEVELOPMENT_STATUS.md.

PHASE 2 — FOUNDATION

Only after Phase 1 passes:

1. Create/repair docs.
2. Establish module ownership.
3. Establish roadmap.
4. Establish acceptance tests.
5. Create content schemas.
6. Create shared gameplay contracts.
7. Preserve existing working systems.

PHASE 3 — COMPLETE GAME

Continue milestone by milestone through the entire roadmap.

Do NOT stop after a demo.

Do NOT ask the user for permission between ordinary milestones.

Make reasonable engineering and creative decisions and document them in
docs/DECISIONS.md.

Ask the user only if there is a genuine blocker that cannot be resolved safely from
the repository/specification.

============================================================
39. SESSION RESUME RULE
============================================================

At the beginning of every future OpenCode session:

1. Read DEVELOPMENT_STATUS.md.
2. Read docs/ROADMAP.md.
3. Read docs/TASKS.md.
4. Read docs/DECISIONS.md.
5. Run the project checks.
6. Inspect current git status.
7. Find the first incomplete milestone.
8. Continue from there.
9. Never restart the project from scratch.
10. Never silently remove scope.

If context becomes large:

    write current state into DEVELOPMENT_STATUS.md
    update TASKS.md
    update ROADMAP.md
    then continue from those files.

============================================================
40. FINAL RELEASE DEFINITION
============================================================

The project is DONE only when:

[ ] Godot project imports cleanly
[ ] No parser errors
[ ] No unhandled runtime errors during normal play
[ ] Main menu works
[ ] New game works
[ ] Load game works
[ ] First-person gameplay works
[ ] Optional third-person works
[ ] Movement works
[ ] Interaction works
[ ] Farming is complete
[ ] Inventory is complete
[ ] Tools are complete
[ ] Economy is complete
[ ] NPCs are complete
[ ] Dialogue is complete
[ ] Relationships are complete
[ ] Romance/marriage is complete
[ ] Quests are complete
[ ] Fishing is complete
[ ] Animals are complete
[ ] Crafting/cooking are complete
[ ] Skills are complete
[ ] Mines are complete
[ ] Combat is complete
[ ] Bosses are complete
[ ] Weather is complete
[ ] Seasons are complete
[ ] Festivals are complete
[ ] Cutscenes are complete
[ ] Main story is complete
[ ] Ending is complete
[ ] Free play after ending works
[ ] Audio is complete
[ ] UI is complete
[ ] Accessibility is complete
[ ] Save/load is robust
[ ] 2-year bot run succeeds
[ ] Regression tests pass
[ ] Acceptance tests pass
[ ] Performance is acceptable
[ ] Assets have licenses recorded
[ ] README contains clean build/run instructions
[ ] Release build can be produced from a fresh checkout

Do not mark the project complete until these conditions are genuinely satisfied.

============================================================
41. FIRST MESSAGE TO YOURSELF
============================================================

Begin by saying internally:

"I am continuing an existing Godot project, not starting a new demo.
I will inspect before modifying, reproduce the current failure, fix and test it,
then build the complete game in milestones without silently reducing scope."

Then execute Phase 1 immediately.
