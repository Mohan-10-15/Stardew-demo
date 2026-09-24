/**
 * Factory for a fresh, valid GameState. Deterministic given seed+player
 * identity. WORKER-2 extends this as the sim grows; keep it a pure function.
 */
import type { GameState, MapState, PlacedObject, Weather } from './types';
import type { MapDef } from './schemas';
import { createRngFromState, Rng } from './rng';
import { DAYS_PER_SEASON, SEASONS_PER_YEAR } from './types';

export function emptyMap(id: string, width: number, height: number): MapState {
  return {
    id,
    grid: { tiles: new Array(width * height).fill('grass'), width, height },
    placed: {},
    npcs: {},
    version: 1,
  };
}

/** Canonical "x,y" map tile key (placed-object record index). */
export function tileKeyOf(x: number, y: number): string {
  return `${x},${y}`;
}

/** Build a concrete MapState from an authored field-map definition. */
export function mapStateFromDef(def: MapDef): MapState {
  const ground = def.layers.ground.replace(/\s+/g, '');
  const placed: Record<string, PlacedObject> = {};
  for (const p of def.initialPlaced) {
    placed[tileKeyOf(p.x, p.y)] = { id: p.id, x: p.x, y: p.y, data: { ...p.data } };
  }
  return {
    id: def.id,
    grid: { tiles: ground.split(''), width: def.width, height: def.height },
    placed,
    npcs: {},
    version: def.version ?? 1,
  };
}

/** Initial concrete maps for every field map in content (new games). */
export function buildInitialMaps(defs: Map<string, MapDef>): Record<string, MapState> {
  const out: Record<string, MapState> = {};
  for (const def of defs.values()) out[def.id] = mapStateFromDef(def);
  return out;
}

/**
 * Migrate saved maps to the current content layout. When the authored version
 * of a map is newer than the saved grid, rebuild the tile grid from content
 * and keep any placed objects that still fall inside the new bounds. Content
 * that does not exist (or is unchanged) is left untouched.
 */
export function migrateAllMaps(
  savedMaps: Record<string, MapState>,
  defs: Map<string, MapDef>,
): Record<string, MapState> {
  const out: Record<string, MapState> = { ...savedMaps };
  for (const def of defs.values()) {
    const saved = out[def.id];
    if (!saved) {
      out[def.id] = mapStateFromDef(def);
      continue;
    }
    if ((saved.version ?? 0) >= (def.version ?? 1)) continue;
    const kept: Record<string, PlacedObject> = {};
    for (const [key, p] of Object.entries(saved.placed)) {
      if (p.x < def.width && p.y < def.height) kept[key] = p;
    }
    const fresh = mapStateFromDef(def);
    out[def.id] = {
      id: def.id,
      grid: fresh.grid,
      placed: { ...fresh.placed, ...kept },
      npcs: saved.npcs ?? {},
      version: def.version ?? 1,
    };
  }
  return out;
}

export interface NewGameOptions {
  playerName: string;
  farmName: string;
  /** Nickname for deriving the save's RNG seed. */
  seedPhrase?: string;
  /** Initial concrete maps for the new game. */
  maps?: Partial<Record<string, MapState>>;
}

export function createInitialState(seed: number, saveName: string, opts?: Partial<NewGameOptions>): GameState {
  const player = opts?.playerName ?? 'Rowan';
  const farm = opts?.farmName ?? 'Rustleaf Farm';

  const maps: Record<string, MapState> = {};
  for (const [id, mapState] of Object.entries(opts?.maps ?? {})) {
    if (mapState) maps[id] = mapState;
  }
  if (!maps.farm) maps.farm = emptyMap('farm', 48, 40);
  const farmState: GameState['farm'] = { mapId: 'farm', name: farm };

  return {
    version: 1,
    meta: {
      saveName,
      createdAt: Date.now(),
      updatedAt: Date.now(),
      playCount: 1,
    },
    rngSeed: seed,
    world: {
      calendar: { year: 1, seasonIndex: 0, dayOfMonth: 1 },
      clock: { hour: 6, minute: 0 },
      weather: 'sun',
      forecast: ['sun', 'sun', 'sun'] as Weather[],
      dayCount: 1,
      passedOut: false,
      playSeconds: 0,
    },
    player: {
      name: player,
      farmName: farm,
      position: { mapId: 'farm', x: 24, y: 20 },
      facing: 'down',
      energy: 270,
      energyMax: 270,
      health: 100,
      healthMax: 100,
      money: 500,
      skills: {
        farming: { level: 0, xp: 0 },
        foraging: { level: 0, xp: 0 },
        mining: { level: 0, xp: 0 },
        fishing: { level: 0, xp: 0 },
        combat: { level: 0, xp: 0 },
      },
      inventory: applyStarterItems({
        slots: new Array(12).fill(null),
        capacity: 12,
        selected: 0,
        cursor: { x: 0, y: 0 },
      }),
      stats: {},
    },
    farm: farmState,
    maps,
    relationships: {},
    quests: { active: [], completed: [] },
    progression: { flags: ['started'], collections: {}, heartstoneProgress: 0, story: [] },
    extensions: {},
  };
}

/** Starter loadout handed to a brand-new farmer. */
export const STARTER_ITEMS: { id: string; qty: number }[] = [
  { id: 'hoe-t0', qty: 1 },
  { id: 'watering-can-t0', qty: 1 },
  { id: 'axe-t0', qty: 1 },
  { id: 'pickaxe-t0', qty: 1 },
  { id: 'scythe-t0', qty: 1 },
  { id: 'fishing-rod-t0', qty: 1 },
  { id: 'sword-t0', qty: 1 },
  { id: 'parsnip-seed', qty: 15 },
];

/** Apply a starter loadout to an inventory (used by createInitialState). */
export function applyStarterItems(inv: GameState['player']['inventory']): GameState['player']['inventory'] {
  const slots = [...inv.slots];
  let slot = 0;
  for (const it of STARTER_ITEMS) {
    while (slot < slots.length && slots[slot] !== null) slot += 1;
    if (slot >= slots.length) break;
    slots[slot] = { id: it.id, qty: it.qty, quality: 0 };
    slot += 1;
  }
  return { ...inv, slots };
}

export function createRestoredState(saved: GameState): GameState {
  return JSON.parse(JSON.stringify(saved)) as GameState;
}

export function newRngFor(seed: number): Rng {
  return createRngFromState(seed);
}

/** Deterministic calendar string for rollover math. */
export function calendarKey(world: GameState['world']): number {
  return (
    world.calendar.year * (SEASONS_PER_YEAR * DAYS_PER_SEASON) +
    world.calendar.seasonIndex * DAYS_PER_SEASON +
    world.calendar.dayOfMonth
  );
}