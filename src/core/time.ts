/**
 * Deterministic clock + calendar. Pure functions on WorldState so the same
 * inputs always produce the same outputs. Advanced by the fixed-timestep
 * simulation loop; view/UI modules render what they read, never write.
 *
 * Clock model: `clock.hour` is a display hour in 0..23 where 6 = 6:00 AM.
 * Times before 6 AM (0..5) only occur after midnight while the farmer stays
 * awake. Continuous "absolute minutes" are measured from the 6:00 AM day
 * start; the calendar day rolls over at 24:00 (absolute minute 1080) and the
 * farmer passes out at 2:00 AM (absolute minute 1200).
 */
import type { Clock, TimeCalendar, WorldState } from './types';
import { DAYS_PER_SEASON, PASS_OUT_HOUR, SEASONS_PER_YEAR } from './types';

export interface ClockTransition {
  dayRolled: boolean;
  seasonRolled: boolean;
  yearRolled: boolean;
  passedOut: boolean;
  /** Calendar/clock after the advance. */
  world: Readonly<WorldState>;
}

/** Midnight and pass-out in absolute minutes from 6:00 AM day start. */
const DL = 24 * 60;
const MIDNIGHT = 18 * 60;
const PASS_OUT_ABS = (18 + PASS_OUT_HOUR) * 60;

function clockToAbsMinutes(clock: Clock): number {
  const c = clock.hour * 60 + clock.minute;
  return c < 6 * 60 ? c + 18 * 60 : c - 6 * 60;
}

export function addMinutes(clock: Clock, minutes: number): Clock {
  let m = clock.minute + minutes;
  let h = clock.hour;
  while (m >= 60) {
    m -= 60;
    h += 1;
  }
  while (h >= 24) h -= 24;
  return { hour: h, minute: m };
}

export function isAfterPassOut(clock: Clock): boolean {
  return clockToAbsMinutes(clock) >= PASS_OUT_ABS;
}

/** Advance a WorldState by `minutes` (intended multiple of TICK_MINUTES). */
export function advanceClock(world: WorldState, minutes: number): ClockTransition {
  const t: ClockTransition = {
    dayRolled: false,
    seasonRolled: false,
    yearRolled: false,
    passedOut: world.passedOut,
    world,
  };

  let abs = clockToAbsMinutes(world.clock) + minutes;
  if (abs >= PASS_OUT_ABS) {
    abs = PASS_OUT_ABS;
    t.passedOut = true;
  }

  let displayMin: number;
  if (abs >= MIDNIGHT) {
    abs -= MIDNIGHT;
    displayMin = abs;
    t.dayRolled = true;
    // Roll the calendar one full day at a time (safe loop; inputs are bounded).
    let { year, seasonIndex, dayOfMonth } = world.calendar;
    let crossing = abs;
    let days = 1;
    while (crossing >= DL) {
      crossing -= DL;
      days += 1;
    }
    for (let i = 0; i < days; i++) {
      dayOfMonth += 1;
      if (dayOfMonth > DAYS_PER_SEASON) {
        dayOfMonth = 1;
        seasonIndex += 1;
        t.seasonRolled = true;
        if (seasonIndex >= SEASONS_PER_YEAR) {
          seasonIndex = 0;
          year += 1;
          t.yearRolled = true;
        }
      }
    }
    t.world = {
      ...world,
      clock: { hour: Math.floor(displayMin / 60), minute: displayMin % 60 },
      calendar: { year, seasonIndex, dayOfMonth },
      dayCount: world.dayCount + days,
      passedOut: t.passedOut,
    };
    return t;
  }

  displayMin = abs + 6 * 60;
  t.world = {
    ...world,
    clock: { hour: Math.floor(displayMin / 60), minute: displayMin % 60 },
    passedOut: t.passedOut,
  };
  return t;
}

/** Start a new in-game day at DAY_START_HOUR, keeping weather/forecast. */
export function startNewDay(world: WorldState): WorldState {
  return {
    ...world,
    clock: { hour: 6, minute: 0 },
    passedOut: false,
  };
}

export function weekOf(dayOfMonth: number): number {
  return Math.floor((dayOfMonth - 1) / 7);
}

export function daysUntil(calendar: TimeCalendar, target: TimeCalendar): number {
  const a = calendar.year * (DAYS_PER_SEASON * SEASONS_PER_YEAR) + calendar.seasonIndex * DAYS_PER_SEASON + calendar.dayOfMonth;
  const b = target.year * (DAYS_PER_SEASON * SEASONS_PER_YEAR) + target.seasonIndex * DAYS_PER_SEASON + target.dayOfMonth;
  return b - a;
}

export function seasonWeatherWeights(seasonIndex: number): Record<WorldState['weather'], number> {
  switch (seasonIndex) {
    case 3:
      return { sun: 6, rain: 0, storm: 0, snow: 3, wind: 1 };
    case 1:
      return { sun: 7, rain: 2, storm: 1, snow: 0, wind: 0 };
    default:
      return { sun: 6, rain: 2, storm: 1, snow: 0, wind: 1 };
  }
}

export function describeDate(world: WorldState): string {
  const seasonNames = ['Spring', 'Summer', 'Fall', 'Winter'];
  return `Year ${world.calendar.year} ${seasonNames[world.calendar.seasonIndex]} ${world.calendar.dayOfMonth}`;
}