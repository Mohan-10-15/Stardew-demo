# ARCHITECTURE

How Ember Hollow is put together, and why. Read `docs/DECISIONS.md` alongside
this — most structural choices have a decision entry.

## 1. Layering

```
┌─────────────────────────────────────────────────────────────┐
│  EmberHollow.Content     ScriptableObject definitions        │
│  (UnityEngine)           CropDefinition, ItemDefinition,    │
│                          MapDefinition, NpcDefinition, ...  │
└────────────────────────────┬────────────────────────────────┘
                             │ converted at boot
                             ▼
┌─────────────────────────────────────────────────────────────┐
│  EmberHollow.Core        NO UnityEngine reference            │
│  (pure C#)               Rng, EventBus, GameClock,         │
│                          GameState, InventorySim,           │
│                          FarmingSim, ContentDb              │
└────────────────────────────┬────────────────────────────────┘
                             │ read / call
                             ▼
┌─────────────────────────────────────────────────────────────┐
│  EmberHollow.Runtime     thin MonoBehaviours                │
│                          SimulationRunner, PlayerController,│
│                          GridRenderer, DayNightController   │
└────────────────────────────┬────────────────────────────────┘
                             │ reads state, publishes events
                             ▼
┌─────────────────────────────────────────────────────────────┐
│  EmberHollow.UI          UI Toolkit (UXML + USS)            │
│                          HudView, DialogueView, ShopView... │
└─────────────────────────────────────────────────────────────┘
```

The single most important constraint: **`EmberHollow.Core` has
`"noEngineReferences": true`**. It cannot call `UnityEngine.Random`,
`MonoBehaviour`, `Debug.Log` or anything else. That is enforced by the compiler,
not by convention, and it is what makes the EditMode test tier able to run a
full day of simulation with no scene.

### Assembly definitions

| Assembly             | Location                              | Engine refs | Owner        |
|----------------------|---------------------------------------|-------------|--------------|
| `EmberHollow.Core`      | `Assets/Scripts/Core`               | **none**    | ORCHESTRATOR / WORKER-2 |
| `EmberHollow.Content`   | `Assets/Scripts/Content`            | yes         | ORCHESTRATOR |
| `EmberHollow.Runtime`   | `Assets/Scripts/{Engine,Features}`  | yes         | WORKER-1     |
| `EmberHollow.UI`        | `Assets/Scripts/UI`                 | yes         | WORKER-3     |
| `EmberHollow.Editor`    | `Assets/Editor`                     | Editor only | ORCHESTRATOR |
| `EmberHollow.Tests.EditMode` | `Assets/Tests/EditMode`        | yes         | all          |
| `EmberHollow.Tests.PlayMode` | `Assets/Tests/PlayMode`        | yes         | all          |

`EmberHollow.Core` referencing nothing is what stops a simulation feature from
quietly acquiring a scene dependency and becoming untestable.

## 2. Feature folder convention

```
Assets/Scripts/Features/<feature>/
    Sim/    WORKER-2  pure C#, no engine
    View/   WORKER-1  GameObjects, materials, animation, VFX
    UI/     WORKER-3  UXML/USS panels and their presenters
```

Engine-level movement and the Cinemachine camera are infrastructure and stay
with WORKER-1 outside this tree.

Current features are scaffolded (empty) at: Time, Weather, Farming, Inventory,
Skills, Foraging, Fishing, Mining, Combat, Crafting, Animals, Economy, Shipping,
People, Quests.

## 3. State model

`GameState` is a plain C# POCO, entirely `[Serializable]` with public fields,
holding:

- `World` — calendar, clock, weather, forecast, day count, pass-out flag
- `Player` — identity, vitals, money, skills, bag, stat counters
- `Farm`, `Maps`, `Relationships`, `Quests`, `Progression`, `Extensions`

**No `Dictionary` anywhere in the state.** `JsonUtility` cannot serialize one,
and it turns a `null` list element into `{}` rather than `null`. So maps and
relationships are lists with id-keyed lookups (`state.Map(id)`), and an empty
inventory slot is an `ItemStack` with `Qty <= 0`. See D-0003.

Feature state that needs a free-form shape goes in `ExtensionState.Json`, keyed
by feature id. This stops `GameState` acquiring a compile-time dependency on
every feature as the game grows.

### Sizing constants

| Constant                    | Value |
|-----------------------------|-------|
| Tick length                 | 10 in-game minutes |
| Day starts                  | 06:00 |
| Pass-out                    | 02:00 (absolute minute 1200 from 06:00) |
| Days per season             | 28 |
| Seasons per year            | 4 |
| Starting energy / health    | 270 / 100 |
| Starting money              | 500 |
| Default bag                 | 12 slots |
| Max stack                   | 999 |
| Save slots                  | 3 |

## 4. Determinism

Every draw that can affect simulation outcome goes through `EmberHollow.Core.Rng`,
seeded from `GameState.RngSeed`. `Rng` is a line-for-line port of the legacy
mulberry32 generator including 32-bit wraparound, so a given seed replays
identically in the Editor, in WebGL and in the headless bot.

`Rng.Fork(label)` gives a subsystem its own stream (harvest quality uses
`Fork("crop:quality")`) so one subsystem's extra draws cannot perturb another's
outcomes. See D-0006.

## 5. EventBus and the interact contract

Features never reach into each other's internals; they publish on `EventBus`.
Subscriptions return `IDisposable` and must be disposed, so no feature leaks a
handler across a scene load.

The bus buffers the last 200 events and **replays them to late subscribers**, so
UI that boots after the sim still sees what it missed. Emission iterates a
snapshot taken before any handler runs, so a handler may subscribe or
unsubscribe during delivery safely.

Every interact-style action publishes **exactly one** of a clearly distinct
success or failure event — never both, never neither. Success and failure must
never look or sound the same. The full table is in `Core/GameEvents.cs` and
D-0008. This is the project's most load-bearing UI/audio rule: the player must be
able to tell "that worked" from "that did nothing" with the screen off.

A feature that does not own a tile or item stays **silent** rather than
reporting failure, so the owning feature is not preceded by someone else's error
cue. `FarmingSim` does this for machine tiles and fishing rods.

## 6. Simulation mutates in place

`InventorySim`, `FarmingSim` and friends mutate the `GameState` they are given
and return a small result. They do **not** return a fresh copy per call — that
would allocate a full deep copy on every swing and tick. Tests use
`StateFactory.Clone` when they need isolation. See D-0005.

The one exception is `GameClock.Advance`, which returns a new `WorldState`,
because a day rollover legitimately replaces it.

## 7. MonoBehaviours are thin

A `MonoBehaviour` may: read input (Input System), call into POCO logic, reflect
results into transforms, animation, particles and audio, and subscribe to the
bus. It may not contain gameplay logic. If a rule cannot be expressed as a
function over state, it belongs in the wrong layer.

`SimulationRunner` is the only place that advances the fixed-timestep tick, and
it owns the authoritative `GameState`, `EventBus` and `Rng`. The simulation state
outlives the MonoBehaviour, so a scene teardown cannot lose progress.

## 8. Content is data

Every definition is a ScriptableObject created as a `.asset` by an Editor script
(`AssetDatabase.CreateAsset`), never hand-placed. At boot they are converted into
immutable POCOs and collected into a single `ContentDb`, which is the only thing
the simulation sees. See D-0007.

An EditMode test loads every definition asset and validates cross-references
(a crop's `SeedId` exists, a machine's recipe exists, a map's legend covers its
ground codes). That test is what catches content drift before it reaches a
PlayMode run.

## 9. Editor-automation convention

Nobody on this team can open the Editor and click. Anything that would mean
dragging a GameObject into a scene, wiring an Inspector reference or
right-clicking an asset is instead a static method on a class under an `Editor/`
folder, run headlessly:

```
"<Editor.exe path>" -batchmode -quit -projectPath "<repo>\unity" ^
  -executeMethod Namespace.ClassName.MethodName ^
  -logFile "<repo>\unity\Logs\<name>.log"
```

It builds the asset with `GameObject.CreatePrimitive`,
`AssetDatabase.CreateAsset`, `PrefabUtility.SaveAsPrefabAsset`,
`EditorSceneManager.SaveScene`, then saves to disk and logs the resulting asset
path. See `Assets/Editor/WebGlBuilder.cs` for the working reference
implementation.

Every such method must **log the path it wrote**, so acceptance can be verified
by checking the file exists on disk rather than by trusting the report.

## 10. Save, load and migration

`JsonUtility` against `GameState`. `GameConstants.SaveVersion` is carried in the
save, and maps track their own `Version` independently because layouts change far
more often than the schema. `StateFactory.MigrateMaps` rebuilds a stale map grid
from content and keeps placed objects still inside the new bounds. See D-0003
and D-0004.

## 11. Performance rules

Target is 60 FPS in the WebGL build on RTX 2050-class hardware.

- Static batching for static geometry; GPU instancing for repeated props
  (fence posts, crops, trees).
- Object pooling for particles. No per-frame allocation in hot paths.
- Textures and materials are shared and reused, never created per instance.
- The simulation allocates nothing per swing or per tick (D-0005).
- KayKit characters share one texture atlas; stay within similarly optimized
  packs. Frame Debugger and Profiler once real scenes exist.

## 12. Testing strategy

| Tier      | Scope                                                        | Runner |
|-----------|--------------------------------------------------------------|--------|
| EditMode  | Pure C# simulation, no scene. Heaviest use.                  | `scripts/run-tests.ps1 -Platform EditMode` |
| PlayMode  | Real MonoBehaviours, real frames, real assertions.            | `scripts/run-tests.ps1 -Platform PlayMode` |
| Both + WebGL build | Milestone gate.                                    | `scripts/run-tests.ps1` then `EmberHollow.EditorTools.WebGlBuilder.Build` |

Because nobody can watch a screen, the PlayMode suite is the substitute for a
playtest. `GameLoopPlayModeTests` mounts a real `MonoBehaviour`, lets Unity tick
it, and asserts on resulting state — including that the success and failure
halves of the interact contract stay distinct in a live loop, not just in
isolation.

A milestone is not done until both tiers are green **with real counts**, a WebGL
`BuildPipeline.BuildPlayer` succeeds, and nothing is left stubbed.
