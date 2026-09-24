# Agreed Rules (M0) — read before any work

## 0. WHAT "DONE" MEANS (copy from the brief, verbatim)

This is NOT a prototype, tech demo or vertical slice. The finished product is a game a stranger could download, play for 40+ hours and reach an ending in. Every feature in the scope must be reachable from a new game through normal play, work end to end, survive save/load, and have automated tests wherever there is logic. No stubs, no "TODO: implement", no placeholder menus, no "coming soon" buttons, no grey-box art in the final build. If scope feels too big, split it into smaller tasks; never cut features silently. Anything deferred goes into docs/ROADMAP.md as an unchecked item.

## Shared-tree rules

- Every file has exactly one owning lane (see LANES below), and a worker never edits outside its lane — it asks the orchestrator instead.
- Only the ORCHESTRATOR runs git commits; workers must never commit, reset, stash or checkout.
- Docs are the orchestrator's; workers put doc-worthy notes in their report and the orchestrator folds them in.
- Dev servers use distinct ports (orchestrator 5170, workers 5171-5173).
- Workers run only the tests for their own module; the orchestrator runs the full suite at integration points.
- NEW (adapted 2026-09): this environment has no oc-grid; workers are opencode subagents, each dispatched by brief. Keep reports in the exact `DONE T-#### | ...` format.

## Lanes

| Lane        | Owner     | Owns |
|-------------|-----------|------|
| world/view  | WORKER-1  | rendering, camera, lighting, day/night/weather/season visuals, maps/terrain, animation, particles, asset pipeline, performance |
| sim         | WORKER-2  | time/calendar, farming, inventory, tools, economy, skills, crafting/cooking, fishing, animals, mines, combat |
| people/ui   | WORKER-3  | NPCs, schedules, dialogue, quests, events/festivals, all DOM UI, audio, settings, tutorial |
| core        | ORCHESTRATOR | src/core contracts, content schemas, build config, test infra, docs, integration glue |

Content ownership: maps -> WORKER-1; items/crops/recipes/fish/monsters/animals -> WORKER-2; NPCs/dialogue/schedules/quests/festivals -> WORKER-3.

## 6. QUALITY GATES (copy from the brief, verbatim)

- `npm run check` passes: typecheck + lint + unit/sim tests + content validation (created in M0).
- The feature works from a fresh new game through normal play (no dev cheats) and survives save -> reload.
- A headless sim/bot test covers its core loop. A Playwright boot smoke test also passes; if a browser can't run here, the sim-level tests are the gate.
- No TODO/FIXME/stub left behind (grep before accepting).
- Docs updated: ROADMAP checkbox, ARCHITECTURE notes, a DECISIONS entry for any non-obvious choice.

## Commands

```
npm run dev          # Vite dev server on :5170 (always keep working)
npm run check        # typecheck + lint + all tests + content validation (gate)
npm run test         # vitest run
npm run build        # production build
npm run format       # prettier
```

## Current status

Milestone M0 (foundations) — in progress. See docs/ROADMAP.md for the full checklist.

## Tech stack (fixed)

TypeScript (strict), Vite, Three.js. DOM/CSS UI overlay. Vitest. ESLint + Prettier. Zod for content. Playwright smoke tests. WebAudio. IndexedDB saves. Everything from the terminal.