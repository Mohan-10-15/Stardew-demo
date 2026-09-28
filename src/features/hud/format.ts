/**
 * Pure HUD formatting helpers (WORKER-3 lane). No DOM access — safe to import
 * and unit-test in Node. Every template string is read from the i18n table.
 */
import { SEASON_NAMES, TICK_MINUTES, type Clock, type GameState, type ItemStack, type TimeCalendar } from '../../core/types';
import type { ContentDb } from '../../core/content';
import { MESSAGES, type Messages } from '../ui-kit/i18n/en';
import { replaceTokens } from '../ui-kit/template';
import { absoluteMinutes, activeBuffs } from '../crafting/sim/CraftingSim';
import { machineAtTile, mapAt } from '../machines/sim/MachinesSim';

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

/**
 * Food-buff HUD rows (T-0405): stat label, magnitude and the readable time
 * remaining, oldest first. Deliberately pure so the "draining over time"
 * behaviour is unit-tested without a DOM.
 */
export interface BuffHudRow {
  statLabel: string;
  amount: number;
  remaining: string;
}

/** Whole game-minutes left for a buff, snapped up to the 10-minute tick. */
export function buffMinutesLeft(buff: { expiresAt: number }, now: number): number {
  const left = buff.expiresAt - now;
  return left > 0 ? Math.ceil(left / 10) * 10 : 0;
}

/** Compact duration like "1h 30m", "2h", "45m". */
export function formatBuffDuration(minutes: number): string {
  const h = Math.floor(minutes / 60);
  const m = Math.round(minutes % 60);
  if (h > 0) return m > 0 ? `${h}h ${m}m` : `${h}h`;
  return `${m}m`;
}

export function buffStatLabel(stat: string, messages: Messages = MESSAGES): string {
  const table: Record<string, string> = messages.hud.buffs.stat;
  return table[stat] && table[stat].length > 0 ? table[stat] : stat;
}

/** Active food buffs as render rows (oldest first). */
export function activeBuffRows(state: GameState, messages: Messages = MESSAGES): BuffHudRow[] {
  const now = absoluteMinutes(state);
  return activeBuffs(state)
    .sort((a, b) => a.expiresAt - b.expiresAt)
    .map((b) => ({
      statLabel: buffStatLabel(b.stat, messages),
      amount: b.amount,
      remaining: formatBuffDuration(buffMinutesLeft(b, now)),
    }));
}

/**
 * What the interact key will do to the tile in front of the player (T-0405):
 * machines are described precisely (load / collect / busy); any other placed
 * object is a generic interaction; empty tiles give null (HUD hides the row).
 */
export type HintAction = 'load' | 'collect' | 'busy' | 'interact';

export interface InteractionHint {
  name: string;
  action: HintAction;
  /** Machine work left, already formatted; empty for non-machine tiles. */
  detail: string;
}

export function interactionHint(state: GameState, content: ContentDb, tile: { mapId: string; x: number; y: number } | null): InteractionHint | null {
  if (!tile) return null;
  const machine = machineAtTile(state, tile);
  if (machine) {
    const def = content.machines.get(machine.machineId);
    const name = def?.name && def.name.length > 0 ? def.name : machine.machineId;
    const loaded = machine.obj.data?.loaded;
    const remaining = (machine.obj.data?.remainingTicks as number | undefined) ?? 0;
    const detail =
      loaded === 1 && remaining > 0
        ? formatBuffDuration(remaining * TICK_MINUTES)
        : '';
    if (loaded === 1 && remaining > 0) return { name, action: 'busy', detail };
    if (loaded === 1) return { name, action: 'collect', detail };
    return { name, action: 'load', detail };
  }
  const map = mapAt(state, tile);
  const obj = map?.placed[`${tile.x},${tile.y}`];
  if (!obj) return null;
  const item = content.items.get(obj.id);
  const name = item?.name && item.name.length > 0 ? item.name : obj.id;
  return { name, action: 'interact', detail: '' };
}