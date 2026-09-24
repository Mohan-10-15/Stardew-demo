/**
 * Shared pure helpers for the farming sim lane (WORKER-2).
 */
import {
  DAY_START_HOUR,
  DAYS_PER_SEASON,
  SEASONS_PER_YEAR,
  type SeasonIndex,
  type WorldState,
} from '@game/core/types';

export const CROP_PREFIX = 'crop:';

export function clampInt(n: number, min: number, max: number): number {
  return Math.max(min, Math.min(max, n));
}

export function tileKey(x: number, y: number): string {
  return `${x},${y}`;
}

/** Extract the crop id from a placed-object id, or null when it is not a crop. */
export function cropIdOf(objId: string): string | null {
  return objId.startsWith(CROP_PREFIX) ? objId.slice(CROP_PREFIX.length) : null;
}

export interface WitheredCrop {
  mapId: string;
  x: number;
  y: number;
  cropId: string;
}

/**
 * Advance the world to the next morning at the fixed day-start hour without
 * routing through advanceClock (which clamps at the 2:00 AM pass-out point and
 * would therefore not reach the next 06:00). Mirrors the core calendar-roll
 * rules (DAYS_PER_SEASON / SEASONS_PER_YEAR).
 */
export function nextDayMorning(world: WorldState): WorldState {
  let { year, seasonIndex, dayOfMonth } = world.calendar;
  dayOfMonth += 1;
  if (dayOfMonth > DAYS_PER_SEASON) {
    dayOfMonth = 1;
    seasonIndex += 1;
    if (seasonIndex >= SEASONS_PER_YEAR) {
      seasonIndex = 0;
      year += 1;
    }
  }
  return {
    ...world,
    calendar: { year, seasonIndex: seasonIndex as SeasonIndex, dayOfMonth },
    clock: { hour: DAY_START_HOUR, minute: 0 },
    dayCount: world.dayCount + 1,
    passedOut: false,
  };
}
