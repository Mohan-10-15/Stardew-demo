# Update 2 — The Living Valley

Living plan for `docs/UPDATE2_PROMPT.md`. Written against `f1fb70a`. Update this
at the end of every group. Status is never upgraded on a headless green alone —
the behaviour, its test and its playtest evidence must all exist (§0.7).

---

## 1. Interpretation table (owner's words → what is being built)

| Owner's words | Reading used here | Wave |
|---|---|---|
| "like Minecraft" | A block sandbox layer — break, place, mine, build, light, craft, in first person — added to the existing farm/life sim. Blocks live in two places only: a Builders' Plot and the Deep Mines. Detailed art by default; swappable texture packs. Mechanics only, no Mojang assets. | W3 |
| "NPCs like anime characters" | All 12 villagers and the player read as individually designed anime characters: distinct silhouettes/hair/faces, clip animation, expressive faces, secondary motion, dialogue portraits. | W4 |
| "any MCP or plugin that makes the game better" | The AI installs and verifies dev tooling itself, in Wave 0. | W0 |
| "perfect background score" | A real adaptive score: ≥ 16 distinct cues, seamless loops, selection by location/season/time/weather/state, ducking, jukebox. Taste signed off by the owner. | W6 |
| "cutscenes … so it looks like a perfect game" | A cinematic toolkit and ≥ 14 authored cutscenes, including opening and ending. | W7 |
| "good physics" | Jolt, a tuned controller, physical drops, water/swimming, destructibles, hit-stop/knockback, deterministic tests. | W5 |
| "some logic" | The world obeys visible rules — Heartstone progression, collections, cause→effect, "the valley remembers you" — proven by a content-graph validator and a feasibility simulation; plus a small contraption layer in the Deep Mines. | W2 + W3 |
| "easy controls" | One-hand-per-device defaults, context glyphs, remap + assist screen, autosave, first-day tutorial. | W1 |
| "a starting page so the user knows what the actual game is" | Title gains About the Game, first-run welcome cards, Help, Credits. | W1 |
| "a story line" | The GDD premise made real: Heartstone arc in three acts, twelve villager arcs, collections, ending, credits. | W2 |

## 2. Wave status

| Wave | Scope | Status | Evidence | Open items |
|---|---|---|---|---|
| W0 | Foundation, honesty, tooling | COMPLETE | `w0-baseline.log` (first run 620/1, rerun 621/0; flaky modal setup fixed), `w0-fresh-clone.log` (621/0, all stages OK); D17–D19 written; MCP `godot` connected and `check_project` called; `docs/DEV_TOOLING.md` records all outputs. | Nothing blocking; human queue items 5–7 stand |
| W1 | Front door, easy controls | COMPLETE at minimum shippable | `w1-controls.log`, `w1-title-v2.log`, `w1-tutorial.log`, `art_review_title_v2_*.png`, `art_review_tutorial_*.png`; 10 tutorial steps advance on real events; 6 About pages + How to Play; generated credits cover all licensed packs; tests 621→637. Check timeout default raised to 300 s with a measurement. | Not in minimum: W1.3 extended options, W1.4 autosave slot, W1.7 welcome cards |
| W2 | Heartstone, story, collections, logic | OPEN | — | — |
| W3 | Block sandbox | OPEN | — | — |
| W4 | Anime cast | OPEN | — | — |
| W5 | Physics and game feel | OPEN | — | — |
| W6 | Score and sound | OPEN | — | — |
| W7 | Cutscenes, set pieces, release | OPEN | — | — |

## 3. Baseline (W0.1, recorded 2026-11-23)

- Local owner's machine, full `check.ps1`: **first run 620 passed / 1 failed**;
  `test_modal::opening_the_shop_really_stops_the_player` failed because the
  player had not moved before the modal opened. Rerun: **621 passed / 0 failed**.
  Root cause: a timing-sensitive setup, not a game defect. The setup now retries
  within a bounded frame budget while keeping the original assertion.
- Stages: `csharp OK · import OK · tests OK · boot OK` on the green rerun.
- Prompt's fresh-clone baseline (Linux, plain Godot): 612 passed / 9 failed —
  8 missing-C# cases plus the `export_presets.cfg` defect. Reproduced differently
  on this Windows machine: the local clone with only the git-ignored engine files
  copied in ran **621 passed / 0 failed**, because the Mono binary and
  `GodotSharp` assemblies were present. `export_presets.cfg` is now committed and
  the fresh-clone proof is `docs/evidence/update2/w0-fresh-clone.log`. No green
  has been faked; the first red run is committed as evidence.
- W0.5: `godot-mcp-runtime@4.0.1` (MIT, no addon) connected via `opencode.json`;
  `check_project` returned the project name, Godot version and structure.
  `tools/probe_engine.gd` confirmed Jolt, all animation/audio classes except
  `AccessibilityServer`, and the `stencil_*` properties exist in 4.5-stable.

## 4. Decision index

| # | Title | Wave |
|---|---|---|
| D17 | Blocks in the Builders' Plot and Deep Mines only | W0 |
| D18 | Asset sources widened to CC0 / CC-BY with credits | W0 |
| D19 | Dev-only MCP servers and portable CLI tools | W0 |

## 5. Assumptions

- The owner will not answer questions during execution; reasonable readings are
  written here and in `DECISIONS.md` and work continues.
- The two render paths (launcher opengl3, exported Vulkan) both have to work;
  Forward+-only features are out.
- "Perfect" is the owner's taste call. Everything objective is measured; taste
  goes to the human queue.

## 6. Human-only queue

| # | Needs the owner | Default |
|---|---|---|
| 1 | Listen to the score via `AUDIO_REVIEW.md`, mark cues 👍/👎 | Ship as-is, labelled unreviewed |
| 2 | Approve the cast's look (`art_review_cast.png`) | Ship the route chosen in W4.1 |
| 3 | Optionally export up to 12 VRoid characters into `assets/models/anime/incoming/` | Route B skipped |
| 4 | Approve any share-alike / CC-BY asset deemed necessary | CC0 only |
| 5 | Confirm .NET SDK and Mono Godot exist on the PC | C# stage reported honestly as failing |
| 6 | Install Node 18+ and restart OpenCode if MCP tools did not load | Fallback tooling (§4.4) |
| 7 | Test the controller layout with a real gamepad | Ship synthetic-input-tested layout |
| 8 | Provide GitHub push credentials | Commits stay local |
| 9 | Fetch any login-gated asset that was skipped | Generated/CC0 substitute |
| 10 | Taste calls — story tone, villager arcs, About copy | Ship; data files the owner can edit |

## 7. Cuts made

None yet. A cut is a decision and is recorded here with its reason.
