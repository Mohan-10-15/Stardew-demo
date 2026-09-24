/**
 * Pure shop dialog formatting helpers (WORKER-3 lane). No DOM access — safe to
 * import and unit-test in Node. All display strings come from the i18n table;
 * the runtime stock access is defensive because state.extensions.shop is
 * lazily initialized by WORKER-2's shop sim.
 */
import type { ItemStack } from '../../core/types';
import { MESSAGES, type Messages } from '../ui-kit/i18n/en';
import { replaceTokens } from '../ui-kit/template';

export interface StockEntryLike {
  itemId: string;
  price?: number;
  qty?: number;
}

export interface ItemPriceLike {
  name?: string;
  price: { base: number; buy?: number };
}

/** A sellable inventory group: total qty across stacks plus per-unit price. */
export interface SellRow {
  itemId: string;
  name: string;
  qty: number;
  price: number;
}

/** Buy price for a stock entry: entry override wins, else the item buy price. */
export function resolveBuyPrice(entry: StockEntryLike, item: ItemPriceLike | undefined): number {
  if (entry.price !== undefined && Number.isFinite(entry.price)) {
    return Math.max(0, Math.floor(entry.price));
  }
  const buy = item?.price.buy;
  return typeof buy === 'number' && Number.isFinite(buy) ? Math.max(0, Math.floor(buy)) : 0;
}

/** Read the tracked remaining qty, or null when the shop sim never tracked it. */
export function trackedRemaining(shopId: string, itemId: string, ext: unknown): number | null {
  if (typeof ext !== 'object' || ext === null) return null;
  const stock = (ext as { stock?: unknown }).stock;
  if (typeof stock !== 'object' || stock === null) return null;
  const shop = (stock as Record<string, unknown>)[shopId];
  if (typeof shop !== 'object' || shop === null) return null;
  const raw = (shop as Record<string, unknown>)[itemId];
  return typeof raw === 'number' && Number.isFinite(raw) ? Math.max(0, Math.floor(raw)) : null;
}

/** Remaining daily qty to show: tracked stock, else content qty, else infinite (null). */
export function remainingDisplayQty(
  shopId: string,
  itemId: string,
  contentQty: number | undefined,
  ext: unknown,
): number | null {
  const tracked = trackedRemaining(shopId, itemId, ext);
  if (tracked !== null) return tracked;
  return typeof contentQty === 'number' && contentQty > 0 ? Math.floor(contentQty) : null;
}

/** Localized stock label: "Left: {count}" or "Unlimited" when infinite. */
export function stockLabel(remaining: number | null, messages: Messages = MESSAGES): string {
  if (remaining === null) return messages.shop.stockUnlimited;
  return replaceTokens(messages.shop.stockLeft, { count: String(remaining) });
}

/** i18n fallback label for an unknown item id, e.g. "Unknown item (ghost-stone)". */
export function unknownItemLabel(id: string, messages: Messages = MESSAGES): string {
  return `${replaceTokens(messages.shop.unknownItem, {})} (${id})`;
}

/** Sellable inventory grouped by item id (base price > 0), sorted by name. */
export function sellableInventory(
  slots: readonly (ItemStack | null)[],
  items: ReadonlyMap<string, ItemPriceLike>,
  messages: Messages = MESSAGES,
): SellRow[] {
  const byId = new Map<string, SellRow>();
  for (const stack of slots) {
    if (!stack) continue;
    const item = items.get(stack.id);
    const base = item?.price.base;
    if (typeof base !== 'number' || !Number.isFinite(base) || base <= 0) continue;
    const cur = byId.get(stack.id);
    if (cur) {
      cur.qty += stack.qty;
    } else {
      byId.set(stack.id, {
        itemId: stack.id,
        name: item?.name && item.name.length > 0 ? item.name : unknownItemLabel(stack.id, messages),
        qty: stack.qty,
        price: Math.floor(base),
      });
    }
  }
  return [...byId.values()].sort((a, b) => a.name.localeCompare(b.name));
}