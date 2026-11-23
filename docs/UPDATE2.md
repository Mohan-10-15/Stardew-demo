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
| W2 | Heartstone, story, collections, logic | COMPLETE at minimum shippable | `docs/STORY_BIBLE.md`; 6 collections / 6 embers; plinth + 3 player-only gates; 4-tab journal; 28-deed ValleyMemory; validator 42 nodes / 200 edges / 0 dangling ids; content expanded to **16 quests, 15 chapters, 8 festivals**; cause→effect rules tested; tests 637→656. | Nothing in minimum; stretch: full dialogue depth per act, replay UI |
| W3 | Block sandbox | PARTIAL (W3.1–W3.6 done) | D20 measured spike; 31 blocks + procedural atlas; chunk rendering with collision; break/place on USE/ALT_USE; Builders' Plot location + generated grid; 10 deterministic Deep Mines floors with lantern rooms and floor-10 boss, weekly reset, save round-trip; `w3-voxel.log`; tests 656→665. | W3.5 terrain hole in the ground mesh, W3.8 perf budget, W3.3 texture-pack swap UI |
| W4 | Anime cast | PARTIAL (W4.1–W4.4 done) | `tools/probe_rig.gd` found 5 rigs × 41 bones × 76 embedded clips → D21 Route C; 13 distinct profiles linked to 12 villagers, cast sheet; Npc now plays real clips by locomotion/activity with procedural fallback, `w4-anime.log` confirms Mira playing `Running_A`; tests 665→669. | W4.5 expressions/gaze/voice blips, W4.6 portraits, W4.8 contact sheet + FPS |
| W5 | Physics and game feel | PARTIAL (W5.1–W5.2, W5.5 done) | D22 Jolt + interpolation with 669/0 evidence; `tools/apply_project_settings.gd` reproducible; coyote/buffer/step-up/apex in MovementConfig + PlayerMotion, wired into PlayerController; `docs/PHYSICS.md`; tests 669→674. | W5.3 drops/water/destructibles, W5.4 juice with accessibility switches, interpolated teleport windowed check |
| W6 | Score and sound | PARTIAL (W6.1–W6.4, W6.7 done) | D23 in-engine original score; 17 real multi-voice stereo cues (>60 s) generated from data; MusicDirector wires cue selection, crossfade, ducking and rests into gameplay (`w6-music.log`); objective not-a-single-tone checks; tests 674→678. | W6.5 layered ambience/SFX refresh, W6.6 jukebox + Now-playing toast, audible device check (human queue 1) |
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
