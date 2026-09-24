/**
 * End-of-day summary (contract m2-contracts.md section 5). Per-day counters
 * live in state.player.stats under JSON-safe `day:*` keys, reset at every day
 * rollover: `day:sold:<itemId>` (+ `day:sold-gold:<itemId>` for the gold),
 * `day:harvest:<cropId>`, `day:forage:<itemId>`, `day:xp:<skill>` and
 * `day:gold` (the day's total income).
 *
 * closeDay emits exactly one `day:summary` per closed day: it is guarded on
 * farming.openDay (the snapshot of the day being closed) so the sleep and
 * pass-out paths both emit once. Call it AFTER shipping payout so goldEarned
 * includes the night's revenue.
 */
import type { EventBus } from '@game/core/events';
import type { GameState, SeasonIndex, Weather } from '@game/core/types';
import { readFarmingExt, snapshotOf, writeFarmingExt } from './ext';

/** XP granted per manual harvest and per forage pick (summary xpEarned). */
export const HARVEST_XP = 12;
export const FORAGE_XP = 5;

export interface SummarySoldRow {
  itemId: string;
  qty: number;
  gold: number;
}

export interface SummaryHarvestRow {
  cropId: string;
  qty: number;
}

export interface SummaryCountRow {
  itemId: string;
  qty: number;
}

export interface SummaryXpRow {
  skill: string;
  amount: number;
}

export interface DaySummaryPayload {
  dayCount: number;
  date: { year: number; seasonIndex: SeasonIndex; dayOfMonth: number };
  weather: Weather;
  forecast: readonly Weather[];
  goldEarned: number;
  itemsSold: SummarySoldRow[];
  cropsHarvested: SummaryHarvestRow[];
  collectedForage: SummaryCountRow[];
  xpEarned: SummaryXpRow[];
}

/** Add `amount` to a `day:*` (or any) counter in player.stats immutably. */
export function bumpStat(state: GameState, key: string, amount = 1): GameState {
  const stats = { ...state.player.stats, [key]: (state.player.stats[key] ?? 0) + amount };
  return { ...state, player: { ...state.player, stats } };
}

/** Build the summary for the day currently held in farming.openDay. */
export function buildDaySummary(state: GameState): DaySummaryPayload {
  const open = readFarmingExt(state).openDay;
  const stats = state.player.stats;

  const itemsSold: SummarySoldRow[] = [];
  for (const [key, qty] of Object.entries(stats)) {
    if (!key.startsWith('day:sold:') || key.startsWith('day:sold-gold:')) continue;
    const itemId = key.slice('day:sold:'.length);
    itemsSold.push({ itemId, qty, gold: stats[`day:sold-gold:${itemId}`] ?? 0 });
  }
  const cropsHarvested: SummaryHarvestRow[] = [];
  for (const [key, qty] of Object.entries(stats)) {
    if (!key.startsWith('day:harvest:')) continue;
    cropsHarvested.push({ cropId: key.slice('day:harvest:'.length), qty });
  }
  const collectedForage: SummaryCountRow[] = [];
  for (const [key, qty] of Object.entries(stats)) {
    if (!key.startsWith('day:forage:')) continue;
    collectedForage.push({ itemId: key.slice('day:forage:'.length), qty });
  }
  const xpEarned: SummaryXpRow[] = [];
  for (const [key, amount] of Object.entries(stats)) {
    if (!key.startsWith('day:xp:')) continue;
    xpEarned.push({ skill: key.slice('day:xp:'.length), amount });
  }

  return {
    dayCount: open.dayCount,
    date: { year: open.year, seasonIndex: open.seasonIndex, dayOfMonth: open.dayOfMonth },
    weather: open.weather,
    forecast: open.forecast,
    goldEarned: stats['day:gold'] ?? 0,
    itemsSold,
    cropsHarvested,
    collectedForage,
    xpEarned,
  };
}

/** Drop every `day:*` counter, keeping any permanent stats. */
export function resetDailyStats(state: GameState): GameState {
  const stats: Record<string, number> = {};
  for (const [key, value] of Object.entries(state.player.stats)) {
    if (!key.startsWith('day:')) stats[key] = value;
  }
  return { ...state, player: { ...state.player, stats } };
}

/** True when the open day predates world.dayCount (i.e. a night has passed). */
export function openDayNeedsClosing(state: GameState): boolean {
  const ext = readFarmingExt(state);
  return ext.openDay.dayCount < state.world.dayCount;
}

/**
 * Close the currently-open day: emit `day:summary` exactly once, reset the
 * daily counters, and open the current world day. No-op once per day.
 */
export function closeDay(state: GameState, bus: EventBus): GameState {
  const ext = readFarmingExt(state);
  if (ext.openDay.dayCount >= state.world.dayCount) return state;
  const payload = buildDaySummary(state);
  bus.emit('day:summary', payload);
  const afterReset = resetDailyStats(state);
  return writeFarmingExt(afterReset, { ...ext, openDay: snapshotOf(afterReset.world) });
}