# Ember Hollow - Task Index

Format: `T-#### | lane | title | status`. Status: DONE | TODO | BLOCKED.
Milestones are committed only when `npm run check` is green AND the matching
docs/ACCEPTANCE.md script rows pass.

| Task | Lane | Title | Status |
|------|------|-------|--------|
| T-0001 | core | M0 foundations (repo, tooling, docs, contracts, check gate) | DONE (e1c4545) |
| T-0101..0109 | all | M1 core loop bundle (briefs T-0107 world / T-0101 sim / T-0109 ui; also energy, saves) | DONE (709f567) |
| T-0201 | world | M2 village map + warps + season/weather/day-night visuals | DONE (89816e1) |
| T-0202 | sim | M2 shop sim + foraging + weather/season effects + day:summary | DONE (89816e1) |
| T-0203 | people/ui | M2 summary UI + shop UI (F key) + i18n | DONE (89816e1) |
| T-0300 | core | M3 contracts + schemas (schedules, dialogue, quests) + ACCEPTANCE.md gate | DONE (a13dc88) |
| T-0301 | people | M3 NPC schedules + pathfinding + position-on-map; dialogue selection; gifts + friendship hearts; heart events; content (npcs/dialogue/schedules) | DONE (1c32b36) |
| T-0302 | world | M3 NPC view rendering + walking animation + Home interior map for first heart event | DONE (1c32b36) |
| T-0303 | people | M3 quests: quest board NPC, quest content, accept/complete/turn-in, journal UI (quests + hearts tabs) | DONE (1c32b36) |
| T-0304 | sim | M3 seasonal shop stock + Friday traveling merchant (content + sim, seeded) | DONE (1c32b36) |
| T-AB01 | all | ADDENDUM B: core-loop feel (tool feedback split, engine FX, continuous walk, audio:ui, ui-kit restyle) | DONE (ba709e9) |
| T-0400 | core | M4 contracts + schemas (skills, fishing, animals, machines) + ACCEPTANCE.md M4 rows | DONE (23a72d9) |
| T-0401 | sim | M4 skills + XP: earning farming/foraging/mining/fishing/combat levels, unlocks at 5 + one profession at 5/10 (profession buff effects land in T-0404) | DONE (23a72d9) |
| T-0402 | sim+world | M4 fishing: 34 fish content, season/weather/time gating, cast/wait/hook mini-loop (sim), water bobber visual (world) | DONE (7e30e54) |
| T-0403 | sim | M4 animals: buy, feed daily, hunger, heart growth, product + quality from friendship/happiness | DONE (38fcbd6) |
| T-0404 | sim+ui | M4 crafting/cooking/machinery: recipes from unlocks, cook once + eat buff, machine processes (keg/preserves/etc.), crafting UI | DONE (ea23c49) |
| T-0405 | ui | M4 skills panel + fishing/animal/machine UI affordances + buff display | DONE (e694ac3, verified in browser) |
| T-0406 | world | M4.9 first-person "Minecraft-POV" voxel presentation: block columns (water rims/pools, trees, houses) + eye-level camera, mouse look, F toggle over the 2D sim | DONE (6e04002) |
| T-0460 | ui | M4.9 original procedural WebAudio soundtrack: day/night/season/weather/biome/health themes, deterministic bars, headless-safe engine; music starts on first player move, `music:set-enabled`/`music:set-volume` controls; settings UI later | DONE (303d2c7) |
| T-0500 | core | Browser observation harness: dev-only `__EH__`/`__EH_SCENE__` hooks, `scripts/observe.ts` + `observe-lib.ts` + `audit-scene.ts` + `audit-camera.ts`, Playwright + Chromium installed so `browser`-marked acceptance steps can actually run | DONE |
| T-0501 | world | Voxel rebuild: 424/424 BoxGeometry world, procedural 16×16 nearest-filtered textures, flat shading, cubic NPCs/assets, first-person default, `V` toggle, pointer lock, held arm, block outline, success particles, failure flash, `__EH_SCENE__` metrics | DONE |
| T-0502 | sim | Real-input audit of farming/machines/fishing: `tool:use-requested` now carries `mapId` (it was omitted, so every real tool swing failed `reason:"no-map"`), machine placement caller, fishing gated to water, regression tests | DONE |
| T-0503 | ui | Pixel UI pass: procedural 16×16 item icons, hard-edged CSS, one lazy gesture-created AudioContext, gain staging, modal ownership, settings + J skills verification | DONE |
| T-0504 | world | First-person camera coherence: yaw follows the authoritative sim `facing` (eased, wrap-aware), mouse-look feeds `player:face` so camera and target cannot disagree, playable with no pointer lock, honest reticle projected onto the real target, avatar placed on its tile (it was stuck at world origin), tilled-soil unified with authored farmland | DONE |
| T-0505 | ui | Named dev-only SFX cue recorder (`__EH_SFX__`, `SfxCue` union, ring buffer) so "a sound played" is a falsifiable claim instead of an oscillator count that the soundtrack satisfied on its own | DONE |
| T-0506 | world | Diagonal movement: each held axis advances at the full single-axis walk speed (the `Math.hypot` normalisation capped the whole diagonal at one axis of distance, so diagonals ran at 0.71x). Per-axis ratio 0.756-0.766 -> 1.000 on all four diagonals | DONE |
| T-0507 | sim | M4 content quota + the missing player-facing dispatch paths (`player:eat`, `shipping:insert`, animal care) so the skills loop is reachable from the keyboard. 9/30 crops, 4/8 machines today | TODO |
