# DECISIONS

Every non-obvious choice, and why. Newest last. The ORCHESTRATOR owns this file.

---

## D-0001 — Unity installed by direct download, not through Hub

**Date:** 2026-09-30

Unity Hub 3.22.0.65535 installed fine as an MSIX package, but its headless
`install` command failed twice with:

```
The Windows elevation prompt was cancelled or timed out.
```

This box has no elevated shell, and Hub's MSIX-packaged installer cannot present
the UAC prompt it needs. Worked around by downloading the official installers
directly and running them per-user:

- `https://download.unity3d.com/download_unity/e1dba0a9aba4/Windows64EditorInstaller/UnitySetup64-6000.3.25f1.exe`
- `https://download.unity3d.com/download_unity/e1dba0a9aba4/TargetSupportInstaller/UnitySetup-WebGL-Support-for-Editor-6000.3.25f1.exe`

Installed to the per-user Hub path, then registered with Hub so
`editors -i` reports it. Unity's own docs mark the Hub CLI experimental; on this
machine it is not merely unreliable but unusable for installs.

**Consequence:** the Editor is *not* at `C:\Program Files\Unity\Hub\Editor`. It is
`C:\Users\mohan\Unity\Hub\Editor\6000.3.25f1\Editor\Unity.exe`, which is line 1
of `AGENTS.md`.

---

## D-0002 — Unity project lives in `unity/`, not the repository root

**Date:** 2026-09-30

The repository root still holds the legacy TypeScript/Vite project including its
`node_modules/` tree. Passing the repo root as `-projectPath` makes Unity import
every one of those files as an asset, which is slow and pollutes the asset
database.

The project is therefore at `unity/`. Every `-projectPath` and every artifact
path in `scripts/` points there. The legacy web project is untouched and still
buildable.

---

## D-0003 — Saves use lists and explicit lookups, never `Dictionary`

**Date:** 2026-09-30

Unity's `JsonUtility` is the specified save serializer. It has two hard
limitations that shape the entire state model:

1. It cannot serialize `Dictionary<K,V>` at all — silently drops the field.
2. It serializes a `null` element inside a `List<T>` as an empty object
   (`{}`), not as `null`, so a "null means empty slot" convention does not
   round-trip.

Consequences, applied consistently:

- `GameState.Maps`, `Relationships`, `Extensions` are `List<T>` with
  id-keyed lookup helpers (`state.Map(id)`, `state.Relationship(id)`), never
  dictionaries.
- An empty inventory slot is an `ItemStack` with `Qty <= 0`, **not** a null
  reference. `ItemStack.IsEmpty` is the only emptiness test.
- Map contents use explicit coordinates (`PlacedAt(x, y)`) rather than a
  `"x,y"` string key, which also removes a per-tile string allocation in the
  hot path.
- Feature-owned state that needs a free-form shape is stored as a JSON string in
  `ExtensionState`, so `GameState` does not grow a dependency on every feature.

A custom serializer would lift all four constraints. It is deliberately not
written yet: `JsonUtility` is adequate now, and the save format is versioned so
swapping it later is a contained change (see D-0004).

---

## D-0004 — Save format is versioned from day one, migrations are explicit

**Date:** 2026-09-30

`GameConstants.SaveVersion` is `1` and every state carries it. `StateFactory.MigrateMaps`
already handles the case that will bite first: an authored map layout changing
under an existing save. Migration rebuilds the tile grid from content and keeps
placed objects that still fall inside the new bounds.

Maps track their own `Version` independently of the save version, because map
layouts change far more often than the rest of the schema. A save whose map
version is greater than or equal to the authored version is left untouched.

---

## D-0005 — The simulation mutates state in place and returns a result

**Date:** 2026-09-30

The legacy TypeScript core returned a fresh state object per call (structural
sharing). A direct C# port of that pattern allocates a full deep copy of the game
state on every single tool swing, action and tick — hundreds of allocations per
in-game day, in the exact hot path the 60 FPS WebGL target forbids.

`EmberHollow.Core` therefore mutates the `GameState` it is given and returns a
small result struct (`ToolResult`, `int` added, `ClockTransition`). Tests clone
with `StateFactory.Clone` when they need isolation, and `GameClock.Advance`
returns a new `WorldState` because a day rollover legitimately replaces it.

The assembly has `"noEngineReferences": true`, so an EditMode test can construct
state, run a full day of ticks and assert with no scene loaded. That is the
cheapest and heaviest-use test tier, and it is the main reason for keeping the
core engine-free.

---

## D-0006 — Determinism is a hard requirement; all randomness flows through `Rng`

**Date:** 2026-09-30

`UnityEngine.Random` is neither seedable to a known value nor guaranteed stable
across Unity versions, and WebGL runs single-threaded with different float
behaviour than the Editor. A headless two-year bot run (M8) and an economy
balance report are only meaningful if the same seed replays identically.

Every draw therefore goes through `EmberHollow.Core.Rng`, seeded from
`GameState.RngSeed`. `Rng` is a line-for-line port of the verified TypeScript
mulberry32 generator, including its 32-bit wraparound, so the legacy web build
and the Unity build agree for a given seed.

`Rng.Fork(label)` gives subsystems their own stream so quality rolls cannot
perturb crop outcomes. Forking consumes exactly one draw from the parent; this
is deliberate and documented on the method.

---

## D-0007 — Core content definitions are plain POCOs; ScriptableObjects adapt into them

**Date:** 2026-09-30

Content is authored as ScriptableObjects, but the simulation must not depend on
`UnityEngine` (D-0005). So:

- `EmberHollow.Content` holds `ScriptableObject` definitions
  (`CropDefinition`, `ItemDefinition`, `MapDefinition`, ...).
- At boot they are converted into immutable POCO definitions (`CropDef`,
  `ItemDef`, `MapDef`) and collected into a single `ContentDb`.
- The simulation only ever sees `ContentDb`.

This keeps authoring in the Inspector-friendly ScriptableObject workflow while
leaving every simulation test scene-free. Cross-references between definitions
are validated by an EditMode test that loads every `.asset` and checks it, which
is what catches a crop pointing at a seed item id that no longer exists.

---

## D-0008 — Interact actions publish distinct success *and* failure events

**Date:** 2026-09-30

Enforced from the brief, and carried over from the legacy `FarmingSim`'s
`tool:used` / `tool:failed` split. Every interact-style system publishes one of
two clearly distinct events, never both and never neither:

| Action   | Success                    | Failure                    |
|----------|----------------------------|----------------------------|
| tool use | `tool:used`                | `tool:failed`              |
| fishing  | `fishing:caught`           | `fishing:failed` / `fled`  |
| mining   | `mining:hit` / `broke`     | `mining:failed`            |
| combat   | `combat:hit`               | `combat:missed` / `dodged` |
| gifting  | `gift:liked` / `gift:loved` | `gift:disliked` / `rejected` |
| crafting | `craft:succeeded`          | `craft:failed`             |

Event names are constants in `Core/GameEvents.cs` so the split cannot drift by
typo. `FarmingSim` additionally emits a distinct `farming:blocked` for frozen
winter soil, because "the ground is frozen" must not sound like "you hit a wall".

`ApplyToolUse` also stays *silent* on tiles and items owned by another feature
(a machine tile, a rod in hand), so the fishing feature is not preceded by the
farming module's failure thud. Those paths return a reason but publish no event,
which is asserted directly in `FarmingSimTests`.

---

## D-0009 — Wasted tool swings still cost energy

**Date:** 2026-09-30

Carried from the legacy core, where the comment read "energy cost per
successful-or-wasted swing". Charging energy before the effect is resolved means
swinging at untillable ground costs the same as tilling it.

Rationale: a free failed swing makes tool choice meaningless and lets a player
brute-force their way through a full day of energy. Charging only on success
would make "am I holding the right tool" a free oracle. The failure reason is
still distinct so the player learns *why*, and the exhausted case never charges
at all (`player:exhausted` fires first).

---

## D-0010 — Art is real CC0 pack content, not procedural primitives

**Date:** 2026-09-30

The art direction was changed from "flat-shaded primitives only" to real
modelled/textured/animated CC0 assets, because primitives produce a toy that
cannot meet the stated quality bar.

Sources, restricted to keep the game reading as one deliberate style:

- **KayKit** — rigged, animated characters (player, NPCs).
- **Quaternius** — buildings, animated farm animals, nature.
- **Kenney.nl** — supplementary.

Imported into `Assets/Art/<pack-name>/` and referenced from prefabs built by the
same Editor-automation pattern as everything else. Every pack is logged in
`docs/ASSET_LICENSES.md` with source URL and license. CC0 needs no attribution;
it is logged for our own record.

Cohesion is treated as more important than any single asset's fidelity, so no
one-off downloads from outside these three packs.
## D-0011 — Engine code lives in `EmberHollow.Runtime`, not Assembly-CSharp

**Date:** 2026-09-30

The test assemblies are asmdefs, and **an asmdef cannot reference a predefined
assembly**. While `Assets/Scripts/Engine` had no asmdef it compiled into
`Assembly-CSharp`, so `FarmSceneTests` could not see `PlayerMovementController`
at all — it failed with `CS0234: The type or namespace name 'Engine' does not
exist`.

`Assets/Scripts/Engine` therefore has its own `EmberHollow.Runtime.asmdef`
(referencing `EmberHollow.Core`, `Unity.Cinemachine`, `Unity.InputSystem`,
`Unity.RenderPipelines.Universal.Runtime`), and `Assets/Editor` has
`EmberHollow.Editor.asmdef`. Both test asmdefs reference `EmberHollow.Runtime`
explicitly.

This is not cosmetic: it is what lets a test validate the scene and the
controller that the scene is built from.

## D-0012 — Cinemachine 3.1.7 API names, recorded so nobody burns 20 minutes again

**Date:** 2026-09-30

Cinemachine 3.1.7 differs from both the 2.x docs and the 3.0 pre-release notes in
ways that compile-fail rather than warn. Verified by reading the package source
in `Library/PackageCache/com.unity.cinemachine@f3f96bcb59af`.

| Thing | Wrong | Correct in 3.1.7 |
|-------|-------|-----------------|
| Namespace | `Cinemachine` | `Unity.Cinemachine` |
| Third-person body | `Cinemachine3rdPersonFollow` (deprecated) | `CinemachineThirdPersonFollow` |
| Body/Aim components | `AddCinemachineComponent<T>()` (deprecated virtual camera only) | `gameObject.AddComponent<T>()` |
| Camera collision | `CinemachineCollider` (deprecated) | `CinemachineDeoccluder` |
| Follow target | `Camera.Follow` / `LookAt` | `CinemachineCamera.Target` (a `CameraTarget` struct) |

Also gone in Unity 6: `Material.glossiness`. Use `GetFloat("_Glossiness")`.

The scene builder is `Assets/Editor/FarmSceneBuilder.cs`. Re-running it rebuilds
`Assets/Scenes/Farm.unity` from scratch and re-registers it as the first enabled
scene in Build Settings, which is what makes `WebGlBuilder` ship the farm rather
than the template's SampleScene.

---


---

## D-0013 - `Clock.Hour` is a display hour, and a day is 6:00 AM to midnight

**Date:** 2026-09-30

`GameClock` held two incompatible conventions for `Clock.Hour` in the same file.
`Advance` and `StateFactory` wrote a **display** hour, where 6:00 is the start of
the day and `ToAbsoluteMinutes` maps an `Hour < 6` back through `+18h`.
`RollForward` wrote the **raw rollover overflow** with no offset.

The consequence was not cosmetic. After a rollover the clock held, say, `0:05`.
`ToAbsoluteMinutes` read that as 18:05 the previous day, so the clock was already
past the day boundary again and **every subsequent tick rolled another day**. A
planted crop would have ripened and the season would have turned inside a single
in-game minute of real time.

The ported web build had hidden it because its test asserted the buggy output: 108
ticks to reach midnight, then 12 more ticks of a broken clock to reach the 2 AM
collapse, and the test called that 120.

`RollForward` now applies the same `DayStartHour` offset as `Advance`, and
`GameClockTests` pins the real contract:

- A playable day is **6:00 AM to midnight, 108 ten-minute ticks**.
- The 2:00 AM collapse is a **clamp for a stalled frame**, not a scheduled event.
  Once the day rolls at midnight the clock is back at 6:00 AM, so ordinary ticking
  can never reach 2 AM; reaching it needs one oversized tick.
- A new test asserts the day *after* a rollover is also a full 108 ticks. That is
  the assertion that fails loudly if the offset is ever dropped again.

## D-0014 - `DailyTick` owns the once-a-day rules, and the runner calls it

**Date:** 2026-09-30

`GameState.PlacedObject` carried `Stage`, `GrownDays` and `MissedWater`, and
harvest refused anything below `CropDef.MatureStage`, but **nothing in the project
ever incremented `Stage`**. `WorldState.Forecast` and
`GameClock.SeasonWeatherWeights` were likewise written but never consumed. A crop
could be tilled, planted and watered and would then never ripen.

`DailyTick.Run(state, content, rng, bus)` in `EmberHollow.Core` now owns the
per-day work: crops advance a stage, unwatered crops wither on the third
consecutive missed day, today's weather comes off yesterday's forecast, and a new
day is rolled onto the end of it. It takes an injected `Rng` and a `ContentDb`, so
a fortnight can be replayed in an EditMode test with no scene loaded.

`SimulationRunner.AdvanceOneTick` calls it on `DayRolled` **before** publishing
`DayStarted`, so a panel reacting to the new day already sees fully grown crops
and settled weather instead of having to wait a frame for them.

Two smaller things fell out of the same work and are worth not undoing:

- `SimulationRunner.Step` honours `Paused`, because a system calling it every
  frame would otherwise quietly defeat the pause. `StepForced` is the explicit
  escape hatch for save migration and tests.
- `EventBus.On` replays buffered events to a late subscriber. That is deliberate,
  so a HUD built mid-session still learns the current day, and the day-rollover
  test asserts the full sequence including that replay.

---

## D-0015 - A native Windows build ships alongside WebGL, not instead of it

**Date:** 2026-09-30

WebGL is still the primary delivery target, but it has a hard limit worth stating
plainly: a WebGL player **cannot be launched as a standalone application**. It is
web technology, so it always needs a browser engine behind it. Anyone asking to
"just run it" wants a window with no browser attached, and the answer is a native
player.

`windowsstandalonesupport` was already installed, so `WindowsBuilder` produces
`unity/Builds/Windows/EmberHollow.exe` through `BuildPipeline.BuildPlayer`, scripted
exactly like the WebGL builder.

- `WindowsBuilder.Build` uses the **Mono** backend with `BuildOptions.Development`.
  A local build lands in well under a minute, which matters more than a smaller
  executable while the game is still being written.
- `WindowsBuilder.BuildRelease` switches to **IL2CPP**, which is what a shipping
  build needs.

Verified by launching the exe: a windowed player on Direct3D 11 over the RTX 2050,
303 MB resident, Input System initialised, PhysX up, first frame rendered, and no
exceptions in `Player.log`.

## D-0016 - Nullable reference types are now actually enabled, per file

**Date:** 2026-09-30

The rulebook has always specified C# with nullable reference types enabled, but
there was no `csc.rsp` anywhere in the project, so it was not. `EmberHollow.Core`
and the Engine assembly were full of `?` annotations compiled in a context where
those annotations are illegal, which produced a stream of `CS8632` warnings in
every player build.

Each file that uses nullable annotations now opens with `#nullable enable`. Done
per file rather than through a shared `csc.rsp` so the context is visible at the
top of the file it governs instead of being implied by a sibling file.

Enabling it took the Windows player build from **80 warnings to 0**, and surfaced
exactly one genuine defect: `DailyTick.AdvanceStage` took a non-nullable `EventBus`
while the rest of that class deliberately allows none, so the parameter is now
`EventBus?`. All 189 EditMode and 17 PlayMode tests still pass.

## D-0017 - The farm grid is centred on the origin, so the origin is a tile corner

**Date:** 2026-09-30

The authored farm map is 32x24 at one world unit per tile. It is laid out centred
on the origin, which means no tile centre sits at `(0,0)`; the origin is the
shared corner of the four central tiles. The map is symmetric about it.

This is deliberate. The camera follows the player through the middle of the
field, so a grid anchored at a corner would put the playable area under one edge
of the screen. `FarmGridTests` pins the symmetry and the round trip rather than
the origin itself, because "the centre tile is at 0.5" is an implementation
detail while "the field is balanced under the camera" is the actual requirement.

## D-0018 - Tools can be stowed, because the sim only harvests bare-handed

**Date:** 2026-09-30

`FarmingSim` routes harvesting through `ApplyHands`, which is reached when the
held tool is null. Every real tool instead takes its own branch, and a watering
can on a mature crop simply sets `Watered` and reports **success**. So before this
change there was no route to picking a ripe crop at all: the correct tool reports
success and yields nothing, which is worse than a visible failure.

Rather than change the rule, the player can now put a tool away with **Q**
(gamepad right shoulder). Bare hands then harvest, and picking a slot takes the
tool back out so the player never has to remember which of the two they left on.

The alternative, letting any tool harvest, was rejected: it would have meant
editing `FarmingSim` in `EmberHollow.Core` to paper over a missing control, and
the sim's current rule is defensible on its own.

## D-0019 - The HUD markup is generated by the scene builder

**Date:** 2026-09-30

`Hud.uxml`, `Hud.uss` and the panel theme are written by `FarmSceneBuilder.Build`
rather than committed as hand-placed files. Nobody on this team can open the
Editor, so a committed uxml would have no way to be authored or corrected: a
single `-executeMethod` reproducing the whole playable game, markup included, is
the only version of this that is actually maintainable here.

`WriteIfChanged` keeps the generated text stable so re-running the builder does
not churn the files.

UI Toolkit ships as a built-in module in Unity 6, so `com.unity.ui` is not
installed and the usual `DefaultRuntimeTheme.tss` path does not exist. The theme
is therefore generated as a one-line `.tss` importing `unity-theme://default`,
which is what the editor's own "create panel settings" would have assigned.
