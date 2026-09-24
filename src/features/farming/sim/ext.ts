/**
 * Feature-owned extension state for the sim lane. Everything here is
 * JSON-safe (extensions ride along in saves untouched).
 */
import type { GameState, ItemStack, SeasonIndex, Weather, WorldState } from '@game/core/types';

export const FARMING_EXT_ID = 'farming';
export const WEATHER_EXT_ID = 'weather';

/** Snapshot of a day as it opened, used by the end-of-day summary. */
export interface OpenDaySnapshot {
  /** world.dayCount of the snapshot (1-based absolute game day). */
  dayCount: number;
  year: number;
  seasonIndex: SeasonIndex;
  dayOfMonth: number;
  weather: Weather;
  forecast: Weather[];
}

/** Capture the weather/date of the day currently described by `world`. */
export function snapshotOf(world: WorldState): OpenDaySnapshot {
  return {
    dayCount: world.dayCount,
    year: world.calendar.year,
    seasonIndex: world.calendar.seasonIndex,
    dayOfMonth: world.calendar.dayOfMonth,
    weather: world.weather,
    forecast: [...world.forecast],
  };
}

export interface FarmingExt {
  shippingBox: ItemStack[];
  /** world.dayCount of the last applied crop/tilled day rollover. */
  lastRolloverDay: number;
  /** Snapshot of the day currently open; closed + replaced on each rollover. */
  openDay: OpenDaySnapshot;
}

export interface WeatherExt {
  /** world.dayCount of the last applied weather roll. */
  lastRolledDay: number;
}

export function readFarmingExt(state: GameState): FarmingExt {
  const raw: Record<string, unknown> | undefined = state.extensions[FARMING_EXT_ID];
  if (raw && Array.isArray(raw.shippingBox) && typeof raw.lastRolloverDay === 'number') {
    const openDay = raw.openDay;
    if (openDay && typeof openDay === 'object' && typeof (openDay as { dayCount?: unknown }).dayCount === 'number') {
      return raw as unknown as FarmingExt;
    }
    return {
      shippingBox: raw.shippingBox as ItemStack[],
      lastRolloverDay: raw.lastRolloverDay as number,
      openDay: snapshotOf(state.world),
    };
  }
  return { shippingBox: [], lastRolloverDay: state.world.dayCount, openDay: snapshotOf(state.world) };
}

export function writeFarmingExt(state: GameState, next: FarmingExt): GameState {
  return {
    ...state,
    extensions: { ...state.extensions, [FARMING_EXT_ID]: { ...next } },
  };
}

/** Guarantee the farming extension exists, bound to the current day count. */
export function ensureFarmingExt(state: GameState): GameState {
  const raw: Record<string, unknown> | undefined = state.extensions[FARMING_EXT_ID];
  if (raw && Array.isArray(raw.shippingBox) && typeof raw.lastRolloverDay === 'number') {
    const openDay = raw.openDay;
    if (openDay && typeof openDay === 'object' && typeof (openDay as { dayCount?: unknown }).dayCount === 'number') {
      return state;
    }
    return writeFarmingExt(state, {
      shippingBox: raw.shippingBox as ItemStack[],
      lastRolloverDay: raw.lastRolloverDay as number,
      openDay: snapshotOf(state.world),
    });
  }
  return writeFarmingExt(state, {
    shippingBox: [],
    lastRolloverDay: state.world.dayCount,
    openDay: snapshotOf(state.world),
  });
}

export function readWeatherExt(state: GameState): WeatherExt {
  const raw: Record<string, unknown> | undefined = state.extensions[WEATHER_EXT_ID];
  if (raw && typeof raw.lastRolledDay === 'number') {
    return raw as unknown as WeatherExt;
  }
  return { lastRolledDay: state.world.dayCount };
}

export function writeWeatherExt(state: GameState, next: WeatherExt): GameState {
  return {
    ...state,
    extensions: { ...state.extensions, [WEATHER_EXT_ID]: { ...next } },
  };
}

/** Guarantee the weather extension exists, bound to the current day count. */
export function ensureWeatherExt(state: GameState): GameState {
  const raw: Record<string, unknown> | undefined = state.extensions[WEATHER_EXT_ID];
  if (raw && typeof raw.lastRolledDay === 'number') return state;
  return writeWeatherExt(state, { lastRolledDay: state.world.dayCount });
}
