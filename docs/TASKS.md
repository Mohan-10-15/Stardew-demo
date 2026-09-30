# TASKS

Task index and worker assignments. One file per task at `docs/tasks/T-####.md`.
Dispatch with the opencode `Task` tool — one subagent per task, briefed from
its task file.

Workers report back in exactly this form:

```
DONE T-#### | files changed | how to verify | open issues
```

A report is **not** accepted until the ORCHESTRATOR has confirmed the asset or
scene exists on disk. Any task built with the Editor-automation pattern must
state the actual `-executeMethod` invocation used, so acceptance is a command,
not a claim.

---

## Roles

| Lane | Owner | Owns |
|------|-------|------|
| — | **ORCHESTRATOR** | project and packages, shared `GameState`/`EventBus` core, ScriptableObject schemas, Editor-automation conventions, build/test scripts, docs, integration, git commits |
| World & Engine | **WORKER-1** | scenes/prefabs (via automation), Cinemachine camera, lighting, day/night, weather VFX, terrain/maps, animation, asset/material pipeline, URP settings, performance |
| Simulation | **WORKER-2** | time/calendar, farming, inventory, tools, economy, skills, crafting/cooking, fishing, animals, mines, combat — plain C#, no MonoBehaviour or scene dependency |
| People & Interface | **WORKER-3** | NPCs, schedules, dialogue, quests, events/festivals, all UI via UI Toolkit, audio, settings, tutorial |

**Workers never commit, reset, stash or checkout.** Only the ORCHESTRATOR
commits. Workers never edit outside their lane — ask the orchestrator instead.
Docs are the orchestrator's; put doc-worthy notes in the task report.

## Standing rules for every worker

1. The Unity Editor path is line 1 of `AGENTS.md`. Use exactly that path.
2. The project root is `unity/`, never the repo root.
3. Nothing is placed by hand in the Editor. Everything is a static method under
   an `Editor/` folder, run with `-executeMethod`, using
   `AssetDatabase.CreateAsset`, `PrefabUtility.SaveAsPrefabAsset`,
   `EditorSceneManager.SaveScene`, `GameObject.CreatePrimitive` and friends.
4. Every Editor method **logs the asset path it wrote**, so acceptance can be
   verified by checking the file on disk.
5. Simulation code is plain C# with no `UnityEngine` dependency, so it is
   EditMode-testable with no scene. No gameplay logic in a MonoBehaviour.
6. Every interact-style action publishes a clearly distinct **success** and
   **failure** event. They must never look or sound the same. See D-0008.
7. Before reporting done: `scripts/run-tests.ps1` is green in both tiers, with
   real counts in the report. A WebGL build succeeds at milestone boundaries.
8. No TODO, FIXME or stub left behind. Grep before reporting.

## Status

| Task | Lane | Description | Status |
|------|------|-------------|--------|
| T-0001 | ORCHESTRATOR | M0 pipeline bootstrap: project, packages, asmdefs, Core port, runner, WebGL builder, docs | **DONE** — EditMode 154/154, PlayMode 5/5, WebGL 15.33 MB |
| T-0101 | WORKER-1 | Import one KayKit character pack + one Quaternius farm pack; log in ASSET_LICENSES | **DONE** — KayKit Adventurers + Quaternius FarmBuildings, 45 prefabs, 85 shared URP materials, EditMode 164/164, PlayMode 5/5 |
| T-0102 | WORKER-1 | Walkable lit farm scene from imported prefabs + Cinemachine angled third-person follow | **DONE** — `Assets/Scenes/Farm.unity`, 45 objects, EditMode 171/171, PlayMode 11/11, WebGL 17.5 MB |
| T-0103 | WORKER-2 | `SimulationRunner` MonoBehaviour adapter wiring Core to the scene, with EditMode tests | **DONE** — EditMode 189/189, PlayMode 17/17, WebGL 18.4 MB |
| T-0104 | WORKER-3 | UI Toolkit base style (parchment/wood, real pixel font) + HUD + Input System action map | queued |

### T-0103 completion notes

```
"C:\Users\mohan\Unity\Hub\Editor\6000.3.25f1\Editor\Unity.exe" -batchmode -quit -projectPath "C:\mohan\Game\Stardew dmeo\unity" -executeMethod EmberHollow.EditorTools.FarmSceneBuilder.Build -logFile "...t0103-scene.log"
```

`SimulationRunner` is now the single owner of `GameState`, `EventBus`, `Rng` and
`ContentDb` for a session, and the farm scene carries exactly one of them. Time
moves as a **fixed step**: `Update` converts elapsed real time into whole
`GameConstants.TickMinutes` steps with a per-frame cap, so the simulation behaves
identically at 30, 60 or 144 FPS and a hitch cannot fast-forward a day. `Step`
lets a test or a cutscene drive the clock by hand and honours `Paused`;
`StepForced` is the explicit escape hatch.

Three genuine bugs were found by the new tests rather than by playing:

- **`SimulationRunner` discarded the clock.** `GameClock.Advance` is pure and
  returns the rolled `WorldState` on the transition. Not adopting it meant the
  clock never moved at all, while `TickCount` happily climbed.
- **`GameClock.RollForward` wrote an absolute hour where a display hour was
  expected.** After a rollover the clock read back as already past midnight, so
  every following tick rolled another day. See D-0013.
- **Crops could never ripen.** Nothing ever incremented `PlacedObject.Stage`, and
  nothing consumed the forecast. `DailyTick` now owns both. See D-0014.

Content ids also had to be reconciled: `StateFactory.StarterItems` hands the player
`hoe-t0` and `parsnip-seed`, so `DefaultContent` had to use exactly those ids or a
new game started holding undefined tools and planting always failed with
`no-seed`. Two tests now lock that pairing in both directions.

`SimulationRunnerTests` builds a bare runner with no scene and covers: the farm
map coming from content, one tick advancing exactly `TickMinutes`, twenty ticks
matching twenty calls of one, same-seed determinism, different seeds diverging, the
day roll publishing one `DayEnded` then one `DayStarted`, a 28-day season rolling
over, pause and resume, the RNG resuming from the save seed, and a complete
till -> plant -> water -> grow -> harvest loop that ends with parsnips in the bag
and a `CropHarvested` event on the bus.

`FarmSimulationPlayModeTests` drives that runner inside the shipped
`Farm.unity` over real frames.

### Running the game

**As a native app** (recommended for local play — a real window, no browser):

```
powershell -ExecutionPolicy Bypass -File scripts\run-windows.ps1
```

Build it first:

```
"C:\Users\mohan\Unity\Hub\Editor\6000.3.25f1\Editor\Unity.exe" -batchmode -quit -projectPath "C:\mohan\Game\Stardew dmeo\unity" -executeMethod EmberHollow.EditorTools.WindowsBuilder.Build -logFile "C:\mohan\Game\Stardew dmeo\Logs\windows-build.log"
```

`WindowsBuilder.Build` uses the Mono backend for fast iteration;
`-executeMethod EmberHollow.EditorTools.WindowsBuilder.BuildRelease` compiles with
IL2CPP for a shipping build. Output is `unity/Builds/Windows/EmberHollow.exe`.

**As a WebGL build** (the primary delivery target):

```
powershell -ExecutionPolicy Bypass -File scripts\serve-webgl.ps1
```

Then play at <http://localhost:8000/>. The script exists because Unity's WebGL
output is Brotli compressed (`.wasm.br`, `.data.br`) and the loader only
decompresses when the response carries `Content-Encoding: br`. It also answers
the byte-range requests Unity's loader streams its data files with, and streams
responses in chunks; opening `index.html` from disk, or serving it from a naive
static server, gives a blank screen.

**The Content-Type of a `.br` file must describe the decoded content, not the
file.** `WebGL.wasm.br` has to be served as `application/wasm` with
`Content-Encoding: br`, because the browser decompresses it before
`WebAssembly.compile` sees it and that call rejects anything else. Keying the
lookup off the `.br` extension sends `application/octet-stream` and the loader
dies with *"Incorrect response MIME type. Expected 'application/wasm'"*.

Check a running server end to end, without a browser:

```
node scripts\verify-webgl.mjs http://localhost:8123/
```

It fetches every asset the loader requests, asserts the status, content type,
encoding and range behaviour, then decompresses the wasm and asks
`WebAssembly.validate` whether the result is a real module. All checks pass
before the build is worth opening in a browser.

A WebGL player cannot be launched as a standalone application: it is web
technology and needs a browser engine, which is why the native build above
exists.

### T-0102 completion notes

```
"C:\Users\mohan\Unity\Hub\Editor\6000.3.25f1\Editor\Unity.exe" -batchmode -quit -projectPath "C:\mohan\Game\Stardew dmeo\unity" -executeMethod EmberHollow.EditorTools.FarmSceneBuilder.Build -logFile "C:\mohan\Game\Stardew dmeo\Logs\t0102-scene.log"
```

`Farm.unity` contains a fenced 26 m yard, a tilled plot, 8 Quaternius buildings,
a Knight player with a CharacterController and a held axe, a directional sun with
shadows plus a fill light, a procedural skybox, fog, and a Cinemachine
`CinemachineThirdPersonFollow` rig with a `CinemachineDeoccluder`.

`FarmSceneTests` (EditMode) opens the saved scene and asserts every renderer uses a
shared, instanced URP material, the camera follows the Player with a positive
vertical arm and a deoccluder, shadows are on, fog and skybox are set, and the
farm is fenced. `FarmScenePlayModeTests` (PlayMode) drives the real scene over
real frames: all eight directions resolve to unit vectors, held input actually
translates the player, diagonals are normalised, the player turns to face travel
and settles facing where they stopped, no-input drifts zero, and the camera sits
behind and above at third-person distance.

Four real bugs were caught by those tests rather than by eye:

- `PlayerMovementController` stopped turning the instant input was released, so
  the player froze mid-turn. It now remembers the last heading and settles into
  it.
- `DayNightController` assigned a `Gradient`-evaluated `Color` into
  `Mathf.Lerp`, which does not compile.
- The EditMode sun test picked the shadowless fill light instead of the
  clock-driven sun.
- The 8-direction test asserted `delta.x > 0` regardless of input sign, so moving
  *left* read as a failure.

Known gaps, deliberately deferred: the ground plane, tilled-plot tiles and
skybox are generated geometry on shared URP materials rather than a Quaternius
nature pack, and there is no tree/foliage pack yet. Those are art, not systems,
and belong with the next art import.

### T-0101 completion notes

Invoked as:

```
"C:\Users\mohan\Unity\Hub\Editor\6000.3.25f1\Editor\Unity.exe" -batchmode -quit -projectPath "C:\mohan\Game\Stardew dmeo\unity" -executeMethod EmberHollow.EditorTools.ArtPackImporter.Build -logFile "C:\mohan\Game\Stardew dmeo\Logs\t0101-import.log"
```

`Assets/Editor/ArtPackImporter.cs` rebuilds every prefab from the source FBX and
is idempotent, so re-running it is the way to fix a bad import. It normalises
characters to 1.800 m with the pivot at the feet, generates an AnimatorController
per character from that character's own clips, and routes every renderer through
85 shared `Universal Render Pipeline/Lit` materials with GPU instancing on.

`Assets/Tests/EditMode/ArtPackImportTests.cs` (164 total EditMode tests) fails
loudly on the four ways a headless import silently breaks: missing or non-URP
materials, per-instance materials, a pivot that is not at the feet, and
inconsistent character scale.

Two bugs worth remembering, both from the first attempt:

- `AssetDatabase.GetAssetPath` on an `Object.Instantiate` clone returns empty in
  Unity 6, so the animator controllers were built with zero clips. The source FBX
  path is now threaded through explicitly.
- Rebuilding an `AnimatorController` by assigning `controller.layers = new[] { … }`
  orphans the original state machine, silently discarding every state added. The
  importer now deletes and recreates the controller instead.
