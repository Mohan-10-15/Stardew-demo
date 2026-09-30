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
| T-0101 | WORKER-1 | Import one KayKit character pack + one Quaternius farm pack; log in ASSET_LICENSES | queued |
| T-0102 | WORKER-1 | Walkable lit farm scene from imported prefabs + Cinemachine angled third-person follow | queued, after T-0101 |
| T-0103 | WORKER-2 | `SimulationRunner` MonoBehaviour adapter wiring Core to the scene, with EditMode tests | queued |
| T-0104 | WORKER-3 | UI Toolkit base style (parchment/wood, real pixel font) + HUD + Input System action map | queued |
