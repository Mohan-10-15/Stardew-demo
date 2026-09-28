# Ember Hollow — Roadmap

Checklist. Unchecked = not done. Checked only when the milestone gate passes
(`npm run check` + playable + boot test where a browser exists).

- [x] M0 Foundations: git, tooling, AGENTS, docs, core contracts (types, Rng,
      EventBus, Store, save skeleton, content schemas + validator, feature
      contract, game bootstrap), `npm run check` green, seed content, commit.
- [x] M1 Core loop: calendar/energy, tools, till > plant > water > harvest,
      hotbar, shipping bin, money, sleep/rollover, save/load flow, farm map +
      engine walkable, first crops. Result: a playable season.
- [x] M2 Village and economy: village map, shops, seasons + weather + forecasts,
      foraging, tree chopping, more crops, end-of-day summary.
- [x] M3 People: schedules + pathfinding, dialogue, gifts, friendship, heart
      events, quests + journal.
- [x] M4 Life skills: fishing, animals, crafting/cooking/machines, skills +
      professions. (T-0401 skills, T-0402 fishing, T-0403 animals + hay stock,
      T-0404 machines/recipes/buffs, T-0405 skills panel + UI affordances,
      T-0510 content quota, T-0511 day-loop input bindings.)
      **Quotas now met and measured from the loaded content tree: 33 crops,
      9 machines, 312 obtainable items, 34 fish, 5 animals, 119 recipes.**
      The reason this was still a demo is now gone: every action in the loop is
      bound to a key (X ship, G eat, Q contextual use, R sleep, B barn) and each
      refusal raises a visible toast naming the key that would have worked.
      A full day — till, plant, water, four real nights, harvest, ship, day
      close — was driven end to end with real keystrokes in Chromium,
      11/11 verdicts, see docs/ACCEPTANCE.md ADDENDUM C.
      Honest gap: mining and combat XP are unreachable because M5 does not
      exist yet, so those two skills cannot level. No fake XP source was added.
- [x] M4.9 Presentation & audio (parallel track): first-person "Minecraft-POV"
      voxel presentation over the 2D sim world, original procedural WebAudio
      soundtrack. Landed: T-0406 renderer, T-0460 soundtrack, T-0501 voxel
      rebuild (424/424 BoxGeometry, flat-shaded, 16×16 nearest textures),
      T-0503 pixel UI + single-AudioContext staging, T-0504 first-person camera
      locked to the interaction target with an honest reticle, T-0505 named SFX
      cue recorder so audio claims are falsifiable. All verified in real
      Chromium; see docs/ACCEPTANCE.md ADDENDUM B. Still open: terrain height,
      gamepad, and the audio settings UI (M7).
- [x] ADDENDUM B: core-loop feel — distinct success/failure feedback (visual +
      audio), continuous 8-way movement with full-speed diagonals, pixel UI
      panels + pixel font, first-person voxel presentation. **Verified in real
      Chromium**, 13/13 harness verdicts, stable over three consecutive runs;
      playtested per docs/ACCEPTANCE.md.
- [ ] M5 Mines and combat: 40+ floors, 12+ monsters, 2 bosses, gear, checkpoints.
- [ ] M6 Story + content completion: Heartstone progression, festivals,
      romance/marriage, collections; hit every quota (30+ crops, 30+ fish,
      300+ items, 12+ NPCs, 6+ romanceable).
- [ ] M7 Polish: art pass, audio pass, UI/UX, performance, accessibility,
      gamepad, tutorial, title screen, credits.
- [ ] M8 Balance/QA/release: 2-year bot run, economy report, bug bash, web zip +
      optional Electron, README.

## Quotas reminders (all mandatory)
10+ maps | 12+ NPCs | 30+ crops | 30+ fish | 5+ animals | 8+ machines | 300+
items | 12+ monsters | 2 bosses | 6+ romanceable | 8 festivals | 12+ music
loops | 3 save slots | 5 skills (lvl 1-10, professions at 5/10) | 4 tool
upgrade tiers.