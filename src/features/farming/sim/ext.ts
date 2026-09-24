/**
 * Feature-owned extension state for the sim lane. Everything here is
 * JSON-safe (extensions ride along in saves untouched).
 */
import type { GameState, ItemStack } from '@game/core/types';

export const FARMING_EXT_ID = 'farming';
export const WEATHER_EXT_ID = 'weather';

export interface FarmingExt {
  shippingBox: ItemStack[];
  /** world.dayCount of the last applied crop/tilled day rollover. */
  lastRolloverDay: number;
}

export interface WeatherExt {
  /** world.dayCount of the last applied weather roll. */
  lastRolledDay: number;
}

export function readFarmingExt(state: GameState): FarmingExt {
  const raw: Record<string, unknown> | undefined = state.extensions[FARMING_EXT_ID];
  if (raw && Array.isArray(raw.shippingBox) && typeof raw.lastRolloverDay === 'number') {
    return raw as unknown as FarmingExt;
  }
  return { shippingBox: [], lastRolloverDay: state.world.dayCount };
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
  if (raw && Array.isArray(raw.shippingBox) && typeof raw.lastRolloverDay === 'number')
    return state;
  return writeFarmingExt(state, { shippingBox: [], lastRolloverDay: state.world.dayCount });
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
