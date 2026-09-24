/**
 * Pure HUD formatting helpers (WORKER-3 lane). No DOM access — safe to import
 * and unit-test in Node. Every template string is read from the i18n table.
 */
import { SEASON_NAMES, type Clock, type ItemStack, type TimeCalendar } from '../../core/types';
import { MESSAGES, type Messages } from '../ui-kit/i18n/en';
import { replaceTokens } from '../ui-kit/template';

export { replaceTokens };

export interface ClockFormat {
  hour12: boolean;
  padHour: boolean;
  am: string;
  pm: string;
}

export interface TooltipItemInfo {
  name: string;
  description?: string;
}

/** Zero-pad a number to two digits. */
export function pad2(value: number): string {
  return value < 10 ? `0${value}` : `${value}`;
}

/** Render an in-game clock, e.g. "06:00" (24h) or "6:00 AM" (12h). */
export function formatClock(clock: Clock, format: ClockFormat = MESSAGES.hud.clock): string {
  const minute = pad2(clock.minute);
  if (format.hour12) {
    const period = clock.hour < 12 ? format.am : format.pm;
    const hour = clock.hour % 12 === 0 ? 12 : clock.hour % 12;
    return `${hour}:${minute} ${period}`;
  }
  const hour = format.padHour ? pad2(clock.hour) : String(clock.hour);
  return `${hour}:${minute}`;
}

/** Render the calendar line, e.g. "Spring 1, Year 1". */
export function formatDate(
  calendar: Pick<TimeCalendar, 'year' | 'seasonIndex' | 'dayOfMonth'>,
  seasons: readonly string[] = SEASON_NAMES,
  messages: Messages = MESSAGES,
): string {
  const season = seasons[calendar.seasonIndex] ?? String(calendar.seasonIndex);
  return replaceTokens(messages.hud.date.format, {
    season,
    day: String(calendar.dayOfMonth),
    year: String(calendar.year),
  });
}

/** Render money in gold units, e.g. "500g". */
export function formatMoney(gold: number, messages: Messages = MESSAGES): string {
  return replaceTokens(messages.hud.money.format, {
    amount: String(Math.max(0, Math.round(gold))),
  });
}

/** Render a hotbar quantity badge, e.g. "15". */
export function formatHotbarSlotQty(qty: number, messages: Messages = MESSAGES): string {
  return replaceTokens(messages.hud.hotbar.qtyBadge, { qty: String(qty) });
}

/** Render a bar's numeric readout, e.g. "270/270". */
export function formatBarAmount(current: number, max: number, messages: Messages = MESSAGES): string {
  return replaceTokens(messages.hud.bar.amount, {
    current: String(Math.round(current)),
    max: String(Math.round(max)),
  });
}

/** Clamp a value to 0..100 as a rounded percent. */
export function barPercent(current: number, max: number): number {
  if (!Number.isFinite(max) || max <= 0) return 0;
  const pct = (current / max) * 100;
  return Math.min(100, Math.max(0, Math.round(pct)));
}

/**
 * Sum the quantities in the shipping box. Accepts `unknown` so it degrades
 * gracefully when the farming extension is missing or malformed in tests.
 */
export function shippingBoxCount(box: unknown): number {
  if (!Array.isArray(box)) return 0;
  let total = 0;
  for (const entry of box) {
    if (typeof entry !== 'object' || entry === null) continue;
    const qty = (entry as Partial<ItemStack>).qty;
    if (typeof qty === 'number' && Number.isFinite(qty)) total += qty;
  }
  return total;
}

/** Build the tooltip text lines for a hotbar stack (name / description / qty). */
export function itemTooltipLines(
  stack: ItemStack,
  item: TooltipItemInfo | null | undefined,
  messages: Messages = MESSAGES,
): string[] {
  const name = item?.name ?? `${replaceTokens(messages.hud.tooltip.unknownItem, {})} (${stack.id})`;
  const lines = [replaceTokens(messages.hud.tooltip.nameLine, { name })];
  if (item?.description) {
    lines.push(replaceTokens(messages.hud.tooltip.descLine, { description: item.description }));
  }
  lines.push(replaceTokens(messages.hud.tooltip.qtyLine, { qty: String(stack.qty) }));
  return lines;
}