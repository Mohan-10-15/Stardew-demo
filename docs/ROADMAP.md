# ROADMAP

Milestone status. A box is only ticked when the milestone's quality gates pass
with **real** numbers from a real run — EditMode and PlayMode both green with
actual pass/fail counts, and a successful WebGL `BuildPipeline.BuildPlayer`.
"Compiles in the Editor" is not verified. See `docs/ARCHITECTURE.md` §12.

Anything deferred is recorded here as an unchecked item. Nothing is cut silently.

---

## M0 — Foundations

- [x] Unity 6000.3.25f1 installed and verified (D-0001, `AGENTS.md` line 1)
- [x] WebGL build support installed and verified
- [x] Unity Personal licence activated, including `com.unity.editor.headless`
- [x] Project isolated in `unity/` so the legacy `node_modules` is not imported (D-0002)
- [x] Packages resolved: URP 17.3.0, Cinemachine 3.1.7, Input System 1.20.0,
      Test Framework 1.6.0, AI Navigation 2.0.14
- [x] `EmberHollow.Core` assembly with `"noEngineReferences": true`
- [x] Core simulation ported from the verified TypeScript: `Rng`, `EventBus`,
      `GameClock`, `GameState`, `ContentDb`, `StateFactory`, `InventorySim`,
      `FarmingSim`
- [x] State model documented and constrained for `JsonUtility` (D-0003, D-0004)
- [x] Folder convention `Features/<name>/{Sim,View,UI}` scaffolded for 15 features
- [x] EditMode + PlayMode runner: `scripts/run-tests.ps1`
- [x] EditMode **154/154** and PlayMode **5/5** passing
- [x] Reusable WebGL builder: `EmberHollow.EditorTools.WebGlBuilder.Build`
- [x] WebGL build succeeded — 15.33 MB, 0 errors
- [x] Docs: GDD, ARCHITECTURE, ROADMAP, TASKS, DECISIONS, ASSET_LICENSES
- [x] **WebGL build re-verified after the Core port**
- [x] M0 checkpoint committed — `1c4f20a`

### M0 — dispatched worker tasks

- [x] **T-0101** WORKER-1: KayKit Adventurers + Quaternius Farm Buildings imported
      and logged — 45 prefabs, EditMode **164/164**, PlayMode **5/5**
- [x] **T-0102** WORKER-1: walkable lit farm scene built by script with a
      Cinemachine angled third-person follow — EditMode **171/171**,
      PlayMode **11/11**, WebGL **17.5 MB** 0 errors
 - [x] **T-0103** WORKER-2: `SimulationRunner` owning `GameState`, `EventBus` and
      `Rng` on a fixed timestep, plus `DailyTick` for crop growth, withering and
      weather — EditMode **189/189**, PlayMode **17/17**, WebGL **18.4 MB**
 - [~] **T-0104** WORKER-3: UI Toolkit base style (parchment + wood border, real
      pixel font), HUD, and the Input System action map — **HUD, hotbar, target
      line, action feedback and the input map are done and playable; the pixel
      font is still missing, so the HUD renders in Unity's built-in font**
      (EditMode **199/199**, PlayMode **22/22**)
 - [x] **T-0105** Playable slice: `FarmGrid` tile mapping, `PlayerInteractionController`
      (hotbar, stow, use-in-front), `FarmTileView` pooled tile overlays, and the
      UI Toolkit HUD — till → plant → water → grow → harvest driven through the
      real scene by `FarmInteractionPlayModeTests`
 - [ ] **T-0106** WORKER-3: a real pixel font for the UI, replacing the built-in
      font, plus the shipping-bin and money panels

---

## M1 — Core loop

- [ ] Calendar and energy
- [~] Tools: hoe, watering can, axe, pickaxe, scythe, fishing rod — the sim and
      the controls exist; only the tool-specific feedback is thin
- [x] Till → plant → water → harvest loop
- [x] Hotbar
- [ ] Shipping bin and money
- [ ] Sleep and day rollover
- [ ] Save / load, 3 slots
- [ ] First crops
- [ ] Continuous 8-directional movement from day one
- [ ] Distinct success vs failure feedback from day one (D-0008)

---

## M2 — Village and economy

- [ ] Village scene
- [ ] Shops
- [ ] Seasons and weather
- [ ] Foraging
- [ ] Tree chopping
- [ ] More crops
- [ ] End-of-day summary

---

## M3 — People

- [ ] Schedules and NavMesh pathfinding
- [ ] Dialogue
- [ ] Gifts
- [ ] Friendship
- [ ] First events
- [ ] Quests and journal

---

## M4 — Life skills

- [ ] Fishing
- [ ] Animals
- [ ] Crafting and cooking
- [ ] Machines
- [ ] Skills and professions

---

## M5 — Mines and combat

- [ ] 40+ seeded floors
- [ ] Ores and gems
- [ ] Checkpoints every 5 floors
- [ ] 12+ monsters with distinct AI
- [ ] 2 bosses
- [ ] Weapons, armor, rings
- [ ] Attack telegraphs and hit feedback

---

## M6 — Story and content completion

- [ ] Main progression goal
- [ ] Collections log
- [ ] Ending and credits, then free play continues
- [ ] 8+ festivals (2 per season)
- [ ] Romance and marriage
- [ ] Every content quota in `docs/GDD.md` §4 hit

---

## M7 — Polish

- [ ] Audio pass
- [ ] UI/UX pass
- [ ] Performance
- [ ] Accessibility
- [ ] Gamepad
- [ ] Tutorial
- [ ] Title screen
- [ ] Credits

---

## M8 — Balance, QA, release

- [ ] 2-year PlayMode bot run
- [ ] Economy balance report
- [ ] WebGL build via `BuildPipeline.BuildPlayer`
- [ ] Windows standalone build via `BuildPipeline.BuildPlayer`
- [ ] README

---

## Deferred / not yet scheduled

Nothing cut so far. Items pulled forward or pushed back during implementation are
added here with the milestone that moved them.
