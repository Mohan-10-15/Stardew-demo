# Ember Hollow â€” Task Index

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
| T-0402 | sim+world | M4 fishing: 30+ fish content, seasons/time gating, cast/wait/hook mini-loop (sim), water bobber visual (world) | TODO |
| T-0403 | sim | M4 animals: buy, feed daily, hunger, heart growth, product + quality from friendship/happiness | TODO |
| T-0404 | sim+ui | M4 crafting/cooking/machinery: recipes from unlocks, cook once + eat buff, machine processes (keg/preserves/etc.), crafting UI | TODO |
| T-0405 | ui | M4 skills panel + fishing/animal/machine UI affordances + buff display | TODO |
