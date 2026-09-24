# Ember Hollow — Decisions Log

Each non-obvious choice gets an entry. Newest last.

1. **Working title: Ember Hollow.** Substitutes the intended "original name/art/
   music" requirement. Logged M0.
2. **oc-grid adaptation (M0).** This machine has no `~/.local/state/oc-grid`,
   no `oc-send`/`oc-todo-clear`, no worker panes. The 4-agent team is emulated:
   briefs written to docs/tasks/T-####.md, "workers" run as opencode subagents,
   roles WORKER-1 (world/engine), WORKER-2 (sim), WORKER-3 (people/UI). Reports
   follow `DONE T-#### | files | verify | issues`. Recorded in AGENTS.md.
3. **Sim tick = 10 in-game minutes, deterministic.** `advanceClock` is pure;
   RNG seeded from state.rngSeed; view only reads sim state. Headless bot and
   tests replay exactly.
4. **Content is single-file-per-kind JSON.** items.json/crops.json/npcs.json +
   maps/<id>.json, Zod-validated. Map layers allow newlines (whitespace
   stripped) so maps stay authorable by hand.
5. **Features self-register via import.meta.glob.** Nobody edits a shared
   registry; src/features/index.ts pulls all index.ts side-effects. Works under
   Vite and Vitest via the same transform.
6. **SaveStore is an interface.** Memory (tests), IndexedDB (browser), fs
   (node bot). Chosen so the sim stays headless and corruption-safe tests run
   without a browser.
7. **Base time reducer is core-owned in M0.** `time:tick` reduces via
   advanceClock. WORKER-2 replaces it with the full time/energy module in M1;
   the contract (pure, deterministic, JSON-safe) stays.
8. **secondsPerTick defaults to 7** (about 16 min real per in-game day) —
   genre-aligned; tunable; sim step content is independent of real time.
9. **Pass-out hour = 2:00 AM (PASS_OUT_HOUR=26).** Clock logic stays pure;
   pass-out clamping happens in advanceClock.
10. **Content in M0 is intentionally tiny seed data.** Full quotas arrive in
    the owning lanes' milestones (M1-M6). Not a scope cut — tracked in
    ROADMAP quotas.