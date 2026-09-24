/**
 * Factory for a fresh, valid GameState. Deterministic given seed+player
 * identity. WORKER-2 extends this as the sim grows; keep it a pure function.
 */
import type { GameState, MapState, Weather } from './types';
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

export interface NewGameOptions {
  playerName: string;
  farmName: string;
  /** Nickname for deriving the save's RNG seed. */
  seedPhrase?: string;
}

export function createInitialState(seed: number, saveName: string, opts?: Partial<NewGameOptions>): GameState {
  const player = opts?.playerName ?? 'Rowan';
  const farm = opts?.farmName ?? 'Rustleaf Farm';

  const farmMap = emptyMap('farm', 48, 40);
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
      inventory: {
        slots: new Array(12).fill(null),
        capacity: 12,
        selected: 0,
        cursor: { x: 0, y: 0 },
      },
      stats: {},
    },
    farm: farmState,
    maps: { farm: farmMap },
    relationships: {},
    quests: { active: [], completed: [] },
    progression: { flags: ['started'], collections: {}, heartstoneProgress: 0, story: [] },
    extensions: {},
  };
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