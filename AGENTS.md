`C:\Users\mohan\Unity\Hub\Editor\6000.3.25f1\Editor\Unity.exe`

# Ember Hollow — Team Rulebook (Unity 6 LTS)

> **The line above is the ONLY verified Unity Editor on this machine.** Every
> headless `-executeMethod`, test, and `BuildPipeline.BuildPlayer` invocation in
> this project must use that exact path. It was confirmed on 2026-09-30 via
> `Unity Hub.exe -- --headless editors -i`, which reported:
>
> ```
> 6000.3.25f1 installed at C:\Users\mohan\Unity\Hub\Editor\6000.3.25f1\Editor\Unity.exe
> ```
>
> Note the location is **not** `C:\Program Files\Unity\Hub\Editor`. This box has
> no elevated shell, and Hub's MSIX-packaged installer fails there with
> `The Windows elevation prompt was cancelled or timed out`. See
> docs/DECISIONS.md entry D-0001.

## 0. Canonical editor invocation

```
"C:\Users\mohan\Unity\Hub\Editor\6000.3.25f1\Editor\Unity.exe" ^
  -batchmode -projectPath "C:\mohan\Game\Stardew dmeo\unity" ^
  -executeMethod Namespace.ClassName.MethodName ^
  -logFile "C:\mohan\Game\Stardew dmeo\unity\Logs\<name>.log"
```

The Unity project root is **`unity/`**, a subdirectory of this repo — NOT the repo
root. The repo root still holds the legacy `node_modules/` tree, and Unity would
try to import every file in it as an asset. Never pass the repo root as
`-projectPath`.

Verified working on 2026-09-30: EditMode 2/2 passed, PlayMode 1/1 passed, and a
real WebGL `BuildPipeline.BuildPlayer` succeeded (15.33 MB, 0 errors, 866s).
Run both test tiers with `scripts/run-tests.ps1`; build WebGL with
`-executeMethod EmberHollow.EditorTools.WebGlBuilder.Build`.

Unity Hub (installed, but its CLI install path is unreliable here):

```
"C:\Program Files\WindowsApps\UnityTechnologies.UnityHub_3.22.0.65535_x64__2vrhnee42bhxm\app\Unity Hub.exe" -- --headless <cmd>
```

## 1. THE RULE THAT MAKES THIS WORK WITH A CLI-ONLY TEAM

Nobody can open the Unity Editor and click. Anything that would normally mean
dragging a GameObject into a scene, wiring an Inspector reference, or
right-clicking to create an asset MUST instead be a C# Editor script under an
`Editor/` folder (`UnityEditor` namespace) with a static method, run headlessly
via the invocation above, using `GameObject.CreatePrimitive`,
`AssetDatabase.CreateAsset`, `PrefabUtility.SaveAsPrefabAsset`,
`EditorSceneManager.SaveScene`, `AssetDatabase.ImportAsset`, etc. If a task
can't be expressed this way, restructure it — never leave a note asking a human
to finish something in the Editor.

## 2. Lanes

| Lane          | Owner       | Owns |
|---------------|-------------|------|
| World & Engine | WORKER-1    | scenes/prefabs (via the automation pattern), Cinemachine camera, lighting, day/night, weather VFX (Particle System), terrain/maps, animation, asset/material pipeline, URP settings, performance |
| Simulation    | WORKER-2    | time/calendar, farming, inventory, tools, economy, skills, crafting/cooking, fishing, animals, mines, combat — plain C# classes, no MonoBehaviour/scene dependency |
| People & Interface | WORKER-3 | NPCs, schedules, dialogue, quests, events/festivals, ALL UI via UI Toolkit (UXML/USS), audio, settings, tutorial |
| core          | ORCHESTRATOR | project/package setup, GameState/EventBus core, ScriptableObject schemas, Editor-automation conventions, build/test scripts, docs, integration, git commits |

Folder convention mirrors the lanes:
`Assets/Scripts/Features/<name>/{Sim,View,UI}/` — Sim=WORKER-2, View=WORKER-1,
UI=WORKER-3. Engine-level movement/camera sim stays with WORKER-1.

## 3. Shared-tree rules

- Only the ORCHESTRATOR runs git commits; workers never commit, reset, stash or checkout.
- Workers never edit outside their lane — they ask the orchestrator instead.
- Docs are the orchestrator's; workers put doc-worthy notes in their report.
- Workers are opencode subagents, dispatched by brief. Reports use the exact
  format `DONE T-#### | files changed | how to verify | open issues`, and must
  state the actual `-executeMethod` invocation for anything built via the
  automation pattern.

## 4. Architecture rules

- Simulation state lives in plain C# POCOs (`GameState` + per-feature state
  classes) with zero `UnityEngine` dependency where possible, so EditMode tests
  construct state, call logic and assert with no scene loaded. Heaviest tier —
  use it.
- MonoBehaviours are thin: read input (Input System), call into POCO logic,
  reflect results into transforms/animation/particles/audio. No gameplay logic
  in a MonoBehaviour.
- EventBus pattern in Core/ is how features communicate. Every interact-style
  action publishes a clearly distinct success event AND a clearly distinct
  failure event (see `FarmingSim.cs`'s `InteractSucceeded`/`InteractFailed`).
  Mandatory for fishing, mining, combat, gifting. Success and failure must never
  look or sound the same.
- Content is data: every definition is a ScriptableObject (`CropDefinition`,
  `ItemDefinition`, `NpcDefinition`, `RecipeDefinition`, `MapDefinition`, ...)
  created as `.asset` via `AssetDatabase.CreateAsset`, never hand-placed.
  Cross-references validated by an EditMode test that loads all of them.
- Art: real modeled/textured/animated assets from free CC0 packs — KayKit
  (characters), Quaternius (buildings, animals, nature), Kenney.nl
  (supplementary). Imported into `Assets/Art/<pack-name>/`. Stylized and
  detailed, not primitives and not photoreal. Stay within these packs so the
  game reads as one deliberate style. Every pack logged in
  docs/ASSET_LICENSES.md with source URL and license.
- 60 FPS in the WebGL build on RTX 2050-class hardware: static batching, GPU
  instancing for repeated props, object pooling for particles, no per-frame
  allocations in hot paths. KayKit characters share one texture atlas — keep to
  similarly optimized assets.
- Original IP only: genre-inspired, never copy Stardew Valley's or Minecraft's
  actual names, art, or mechanics verbatim.
- Save files: `JsonUtility` (or a small custom serializer), versioned + migrated,
  corruption-safe.

## 5. Tech stack (fixed)

Unity 6 LTS 6000.3.25f1, C# with nullable reference types enabled, URP,
Cinemachine (angled third-person follow camera), Input System package (not
legacy Input Manager), UI Toolkit (UXML + USS) for every menu/HUD/dialogue box,
Unity Test Framework (NUnit) for EditMode + PlayMode tests. WebGL is the
primary iteration target; Windows standalone is a later deliverable.

## 6. Quality gates

- EditMode AND PlayMode tests green, with actual pass/fail counts from real
  results — not a claim that tests exist.
- Works from a fresh new game through normal play (no dev cheats), survives
  save -> reload.
- At least one PlayMode test drives the feature's core loop by simulating real
  frames/input and asserting on resulting state.
- A successful WebGL build via `BuildPipeline.BuildPlayer` at every milestone
  boundary. "Compiles in the Editor" is not verified.
- No TODO/FIXME/stub left behind (grep before accepting).
- Docs updated: ROADMAP checkbox, ARCHITECTURE notes, DECISIONS entry for any
  non-obvious choice.

## 7. Milestones

- **M0** Foundations: project + packages (URP, Cinemachine, Input System),
  URP config, Editor-automation convention, folder structure, docs (GDD,
  ARCHITECTURE, ROADMAP, TASKS, DECISIONS, ASSET_LICENSES), Core scripts, an
  EditMode+PlayMode test runner, a real WebGL build. Then: WORKER-1 builds one
  walkable lit farm scene with a Cinemachine follow using an imported KayKit
  character + Quaternius farm pack; WORKER-2 wires Core logic to a MonoBehaviour
  adapter with EditMode tests; WORKER-3 builds the UI Toolkit base style
  (parchment/wood, real pixel font) + HUD + Input System action map.
- **M1** Core loop: calendar/energy, tools, till->plant->water->harvest, hotbar,
  shipping bin, money, sleep/rollover, save/load, first crops. Continuous 8-dir
  movement from day one. Distinct success vs failure feedback from day one.
- **M2** Village and economy: village scene, shops, seasons + weather,
  foraging, tree chopping, more crops, end-of-day summary.
- **M3** People: schedules + NavMesh pathfinding, dialogue, gifts, friendship,
  first events, quests + journal.
- **M4** Life skills: fishing, animals, crafting/cooking/machines, skills +
  professions.
- **M5** Mines and combat.
- **M6** Story and content completion: progression goal, festivals,
  romance/marriage, collections; hit every quota.
- **M7** Polish: audio pass, UI/UX pass, performance, accessibility, gamepad,
  tutorial, title screen, credits.
- **M8** Balance, QA, release: 2-year PlayMode bot run, economy report, WebGL +
  Windows standalone builds via `BuildPipeline.BuildPlayer`, README.

## 8. Legacy web build

The previous TypeScript + Vite + Three.js implementation (M0-M3) is still in
this repo. Its rulebook is archived at docs/legacy-web/AGENTS-web.md. See
docs/DECISIONS.md before deleting or moving any of it.

## 9. Current status

Unity 6000.3.25f1 + WebGL module installed, verified, and **licensed** (Unity
Personal, with the `com.unity.editor.headless` entitlement) on 2026-09-30.

M0 pipeline is proven: EditMode **171/171** and PlayMode **11/11** pass, and a
real WebGL `BuildPipeline.BuildPlayer` succeeds with the farm scene
(17.5 MB, 0 errors). The engine-free `EmberHollow.Core` assembly carries the
ported clock, EventBus, RNG, inventory and farming sim with EditMode coverage.
`Assets/Scenes/Farm.unity` is built entirely by
`EmberHollow.EditorTools.FarmSceneBuilder.Build` from imported CC0 prefabs.
See docs/ROADMAP.md for the first unchecked item.