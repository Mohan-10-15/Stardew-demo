/**
 * Wrong-module guard: a lane must never touch another lane's files.
 * Imported by every test in tests/sim and used at build time to enforce
 * the shared-tree rules from AGENTS.md. See docs/ARCHITECTURE.md.
 */
export const LANE_OWNER: Record<string, 'world' | 'sim' | 'people' | 'core'> = {
  view: 'world',
  sim: 'sim',
  ui: 'people',
  '../features': 'core',
};

export const LANE_TO_WORKER: Record<string, string> = {
  world: 'WORKER-1',
  sim: 'WORKER-2',
  people: 'WORKER-3',
  ui: 'WORKER-3',
  core: 'ORCHESTRATOR',
};