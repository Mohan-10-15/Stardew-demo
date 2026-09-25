import { describe, expect, it } from 'vitest';
import { clockToGameMinutes, dayIndex, dayOfWeek, dayOfWeekName } from '../../src/core/time';
import type { Clock, TimeCalendar } from '../../src/core/types';

function clock(hour: number, minute: number): Clock {
  return { hour, minute };
}

describe('clockToGameMinutes', () => {
  it('maps 6:00 AM to 600 and keeps daytime monotonic', () => {
    expect(clockToGameMinutes(clock(6, 0))).toBe(600);
    expect(clockToGameMinutes(clock(12, 30))).toBe(1230);
    expect(clockToGameMinutes(clock(23, 0))).toBe(2300);
  });
  it('maps post-midnight hours into the 2400+ night range', () => {
    expect(clockToGameMinutes(clock(0, 0))).toBe(2400);
    expect(clockToGameMinutes(clock(2, 0))).toBe(2600);
    expect(clockToGameMinutes(clock(1, 10))).toBe(2510);
  });
});

describe('day week math', () => {
  const cal: TimeCalendar = { year: 1, seasonIndex: 0, dayOfMonth: 1 };
  it('day 1 year 1 is day 0 / sunday', () => {
    expect(dayIndex(cal)).toBe(0);
    expect(dayOfWeek(cal)).toBe(0);
    expect(dayOfWeekName(cal)).toBe('sunday');
  });
  it('advances predictably across seasons', () => {
    expect(dayIndex({ year: 1, seasonIndex: 0, dayOfMonth: 28 })).toBe(27);
    expect(dayIndex({ year: 1, seasonIndex: 1, dayOfMonth: 1 })).toBe(28);
    expect(dayOfWeek({ year: 1, seasonIndex: 1, dayOfMonth: 1 })).toBe(0);
    expect(dayIndex({ year: 2, seasonIndex: 0, dayOfMonth: 1 })).toBe(112);
  });
});