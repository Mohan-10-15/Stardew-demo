/**
 * Pure end-of-day summary formatting helpers (WORKER-3 lane). No DOM access —
 * safe to import and unit-test in Node. Item/crop names and gold strings are
 * resolved here so the dialog renders a pre-built display model.
 */
import { SEASON_NAMES, type SeasonIndex } from '../../core/types';
import { formatDate, formatMoney, replaceTokens } from '../hud/format';
import { MESSAGES, type Messages } from '../ui-kit/i18n/en';

/** Reuse the HUD gold formatter so the summary money reads identically. */
export { formatMoney as formatGold };

export interface SoldRow {
  itemId: string;
  qty: number;
  gold: number;
}

export interface CountRow {
  itemId: string;
  qty: number;
}

export interface HarvestRow {
  cropId: string;
  qty: number;
}

export interface XpRow {
  skill: string;
  amount: number;
}

/** Sold rows grouped by item id; qty and gold summed per item. */
export function groupSoldByItem(rows: readonly SoldRow[]): SoldRow[] {
  const byId = new Map<string, SoldRow>();
  for (const row of rows) {
    const cur = byId.get(row.itemId);
    if (cur) {
      cur.qty += row.qty;
      cur.gold += row.gold;
    } else {
      byId.set(row.itemId, { itemId: row.itemId, qty: row.qty, gold: row.gold });
    }
  }
  return [...byId.values()];
}

/** Count rows grouped by item id; qty summed per item. */
export function groupCountsByIdentifier(rows: readonly CountRow[]): CountRow[] {
  const byId = new Map<string, CountRow>();
  for (const row of rows) {
    const cur = byId.get(row.itemId);
    if (cur) {
      cur.qty += row.qty;
    } else {
      byId.set(row.itemId, { itemId: row.itemId, qty: row.qty });
    }
  }
  return [...byId.values()];
}

/** Shape of the `day:summary` bus payload (m2-contracts §5). */
export interface DaySummaryPayload {
  dayCount: number;
  date: { year: number; seasonIndex: SeasonIndex; dayOfMonth: number };
  weather: string;
  forecast: readonly string[];
  goldEarned: number;
  itemsSold: readonly SoldRow[];
  cropsHarvested: readonly HarvestRow[];
  collectedForage: readonly CountRow[];
  xpEarned: readonly XpRow[];
}

export interface NamedDef {
  name: string;
}

/** i18n fallback label for an unknown item/crop id, e.g. "Unknown item (ghost-stone)". */
export function unknownItemLabel(id: string, messages: Messages = MESSAGES): string {
  return `${replaceTokens(messages.summary.unknownItem, {})} (${id})`;
}

/** Resolve a display name from items, then crops, then the i18n fallback. */
export function resolveDisplayName(
  id: string,
  items: ReadonlyMap<string, NamedDef> | null | undefined,
  crops: ReadonlyMap<string, NamedDef> | null | undefined,
  messages: Messages = MESSAGES,
): string {
  const item = items?.get(id);
  if (item?.name) return item.name;
  const crop = crops?.get(id);
  if (crop?.name) return crop.name;
  return unknownItemLabel(id, messages);
}

/** Localized weather label, falling back to the raw key when unknown. */
export function weatherLabel(weather: string, messages: Messages = MESSAGES): string {
  const labels = messages.hud.weather.label as Record<string, string>;
  return labels[weather] ?? weather;
}

/** Localized skill name, falling back to the raw id when unknown. */
export function skillLabel(skill: string, messages: Messages = MESSAGES): string {
  const labels = messages.summary.skills as Record<string, string>;
  return labels[skill] ?? skill;
}

export interface SummaryRow {
  label: string;
  qty: number;
  gold?: string;
}

/** Fully-resolved, display-ready summary model. */
export interface SummaryModel {
  dayCount: number;
  date: string;
  weather: string;
  goldEarned: string;
  shipping: SummaryRow[];
  harvest: SummaryRow[];
  forage: SummaryRow[];
  experience: SummaryRow[];
  isEmpty: boolean;
}

export function buildSummaryModel(
  payload: DaySummaryPayload,
  items: ReadonlyMap<string, NamedDef>,
  crops: ReadonlyMap<string, NamedDef>,
  messages: Messages = MESSAGES,
): SummaryModel {
  const shipping = groupSoldByItem(payload.itemsSold).map((row) => ({
    label: resolveDisplayName(row.itemId, items, crops, messages),
    qty: row.qty,
    gold: formatMoney(row.gold, messages),
  }));
  const harvest = groupCountsByIdentifier(
    payload.cropsHarvested.map((r) => ({ itemId: r.cropId, qty: r.qty })),
  ).map((row) => ({
    label: resolveDisplayName(row.itemId, items, crops, messages),
    qty: row.qty,
  }));
  const forage = groupCountsByIdentifier(payload.collectedForage).map((row) => ({
    label: resolveDisplayName(row.itemId, items, crops, messages),
    qty: row.qty,
  }));
  const experience = payload.xpEarned.map((row) => ({
    label: skillLabel(row.skill, messages),
    qty: row.amount,
  }));
  const isEmpty =
    shipping.length === 0 && harvest.length === 0 && forage.length === 0 && experience.length === 0;
  return {
    dayCount: payload.dayCount,
    date: formatDate(payload.date, SEASON_NAMES, messages),
    weather: weatherLabel(payload.weather, messages),
    goldEarned: formatMoney(payload.goldEarned, messages),
    shipping,
    harvest,
    forage,
    experience,
    isEmpty,
  };
}