/**
 * Shop sim (WORKER-2 lane, contract m2-contracts.md §2).
 *
 * Runtime stock lives in state.extensions.shop as a JSON-safe record:
 *   { stock: Record<shopId, Record<itemId, number>>, lastRestockDay }
 * Counters count the DAY's remaining units (daily stock); an item entry with
 * no qty in content is infinite and never appears in `stock`. `shop:restock`
 * (and the sleep/tick rollover pass) resets counters to content qty each
 * morning. Buy = validate funds + stock + inventory space, deduct money,
 * add to inventory, decrement stock, emit `shop:bought`. Sell (shops with
 * buys=true) = remove stacks of the id, pay item.price.base, emit `shop:sold`
 * and feed the day's summary counters.
 */
import type { ContentDb } from '@game/core/content';
import type { EventBus } from '@game/core/events';
import { defineFeature, type FeatureContext, type FeatureModule } from '@game/core/feature';
import type { GameState, ItemStack } from '@game/core/types';
import { tryAddToSlots } from '../../inventory/sim/InventorySim';
import { bumpStat } from '../../farming/sim/summary';

export const SHOP_EXT_ID = 'shop';

export type ShopDenyReason = 'funds' | 'space' | 'stock';

export interface ShopExt {
  stock: Record<string, Record<string, number>>;
  /** world.dayCount when per-shop daily counters were last restored. */
  lastRestockDay: number;
}

export interface ShopBuyPayload {
  shopId: string;
  itemId: string;
  qty: number;
}

export interface ShopSellPayload {
  shopId: string;
  itemId: string;
  qty: number;
}

export function readShopExt(state: GameState): ShopExt {
  const raw: Record<string, unknown> | undefined = state.extensions[SHOP_EXT_ID];
  if (raw && raw.stock && typeof raw.stock === 'object' && typeof raw.lastRestockDay === 'number') {
    return raw as unknown as ShopExt;
  }
  return { stock: {}, lastRestockDay: state.world.dayCount };
}

export function writeShopExt(state: GameState, next: ShopExt): GameState {
  return {
    ...state,
    extensions: { ...state.extensions, [SHOP_EXT_ID]: { ...next } },
  };
}

/** Initialise the shop extension, seeding finite daily counters from content. */
export function ensureShopExt(state: GameState, content: ContentDb): GameState {
  const raw: Record<string, unknown> | undefined = state.extensions[SHOP_EXT_ID];
  if (raw && raw.stock && typeof raw.stock === 'object' && typeof raw.lastRestockDay === 'number') {
    return state;
  }
  return writeShopExt(state, { stock: freshStock(content), lastRestockDay: state.world.dayCount });
}

function freshStock(content: ContentDb): Record<string, Record<string, number>> {
  const stock: Record<string, Record<string, number>> = {};
  for (const shop of content.shops.values()) {
    const counters: Record<string, number> = {};
    for (const entry of shop.stock) {
      if (entry.qty !== undefined) counters[entry.itemId] = entry.qty;
    }
    if (Object.keys(counters).length > 0) stock[shop.id] = counters;
  }
  return stock;
}

/** Remaining units of itemId at shopId this day (Infinity = infinite). */
function remainingOf(ext: ShopExt, shopId: string, itemId: string, content: ContentDb): number {
  const counter = ext.stock[shopId]?.[itemId];
  if (typeof counter === 'number') return counter;
  const shop = content.shops.get(shopId);
  const entry = shop?.stock.find((e) => e.itemId === itemId);
  if (entry && entry.qty === undefined) return Infinity;
  return 0;
}

function decrementStock(
  st: GameState,
  ext: ShopExt,
  shopId: string,
  itemId: string,
  amount: number,
): GameState {
  const counter = ext.stock[shopId]?.[itemId];
  if (typeof counter !== 'number') return st;
  const shop: Record<string, Record<string, number>> = { ...ext.stock };
  const shopCounters: Record<string, number> = { ...(shop[shopId] ?? {}) };
  shopCounters[itemId] = counter - amount;
  shop[shopId] = shopCounters;
  return writeShopExt(st, { ...ext, stock: shop });
}

export function denyShop(state: GameState, bus: EventBus, reason: ShopDenyReason, payload: ShopBuyPayload): GameState {
  bus.emit('shop:denied', { reason, shopId: payload.shopId, itemId: payload.itemId });
  return state;
}

export function buyReducer(
  state: GameState,
  payload: ShopBuyPayload,
  bus: EventBus,
  content: ContentDb,
): GameState {
  const ext = readShopExt(state);
  const shop = content.shops.get(payload.shopId);
  const entry = shop?.stock.find((e) => e.itemId === payload.itemId);
  const item = content.items.get(payload.itemId);
  if (!shop || !entry || !item) return denyShop(state, bus, 'stock', payload);

  const qty = Math.floor(payload.qty);
  if (qty <= 0) return denyShop(state, bus, 'stock', payload);

  const remaining = remainingOf(ext, payload.shopId, payload.itemId, content);
  if (remaining < qty) return denyShop(state, bus, 'stock', payload);

  const price = entry.price ?? item.price.buy;
  if (price === undefined) return denyShop(state, bus, 'stock', payload);
  const gold = price * qty;
  if (state.player.money < gold) return denyShop(state, bus, 'funds', payload);

  const fit = tryAddToSlots(state, payload.itemId, qty, item.canStack);
  if (fit.added < qty) return denyShop(state, bus, 'space', payload);

  let st = fit.state;
  st = decrementStock(st, ext, payload.shopId, payload.itemId, qty);
  st = { ...st, player: { ...st.player, money: st.player.money - gold } };
  bus.emit('shop:bought', { shopId: payload.shopId, itemId: payload.itemId, qty, gold });
  return st;
}

function totalOwned(state: GameState, itemId: string): number {
  let total = 0;
  for (const stack of state.player.inventory.slots) {
    if (stack && stack.id === itemId) total += stack.qty;
  }
  return total;
}

function removeQty(state: GameState, itemId: string, qty: number): GameState {
  let remaining = qty;
  const slots: (ItemStack | null)[] = [...state.player.inventory.slots];
  for (let i = 0; i < slots.length && remaining > 0; i++) {
    const slot = slots[i];
    if (!slot || slot.id !== itemId) continue;
    const take = Math.min(slot.qty, remaining);
    if (slot.qty - take <= 0) {
      slots[i] = null;
    } else {
      slots[i] = { ...slot, qty: slot.qty - take };
    }
    remaining -= take;
  }
  return {
    ...state,
    player: { ...state.player, inventory: { ...state.player.inventory, slots } },
  };
}

export function sellReducer(
  state: GameState,
  payload: ShopSellPayload,
  bus: EventBus,
  content: ContentDb,
): GameState {
  const shop = content.shops.get(payload.shopId);
  const item = content.items.get(payload.itemId);
  if (!shop || !shop.buys || !item) {
    bus.emit('shop:denied', { reason: 'stock', shopId: payload.shopId, itemId: payload.itemId });
    return state;
  }
  const qty = Math.floor(payload.qty);
  if (qty <= 0) {
    bus.emit('shop:denied', { reason: 'stock', shopId: payload.shopId, itemId: payload.itemId });
    return state;
  }
  if (totalOwned(state, payload.itemId) < qty) {
    bus.emit('shop:denied', { reason: 'stock', shopId: payload.shopId, itemId: payload.itemId });
    return state;
  }

  const gold = item.price.base * qty;
  let st = removeQty(state, payload.itemId, qty);
  st = { ...st, player: { ...st.player, money: st.player.money + gold } };
  st = bumpStat(st, `day:sold:${payload.itemId}`, qty);
  st = bumpStat(st, `day:sold-gold:${payload.itemId}`, gold);
  st = bumpStat(st, 'day:gold', gold);
  bus.emit('shop:sold', { shopId: payload.shopId, itemId: payload.itemId, qty, gold });
  return st;
}

/** Restore per-shop daily counters (one application per world day). */
export function restockReducer(state: GameState, bus: EventBus, content: ContentDb): GameState {
  const ext = readShopExt(state);
  if (ext.lastRestockDay === state.world.dayCount) return state;
  const next = writeShopExt(state, { stock: freshStock(content), lastRestockDay: state.world.dayCount });
  bus.emit('shop:restocked', { dayCount: state.world.dayCount });
  return next;
}

export const shopSim: FeatureModule = defineFeature({
  id: 'shop:sim',
  lane: 'sim',
  setup(ctx: FeatureContext) {
    ctx.store.replaceState(ensureShopExt(ctx.store.state, ctx.content));
    const bus = ctx.bus;
    const content = ctx.content;

    ctx.store.registerReducer('shop:buy', (st, action) =>
      buyReducer(st, action.payload as ShopBuyPayload, bus, content),
    );
    ctx.store.registerReducer('shop:sell', (st, action) =>
      sellReducer(st, action.payload as ShopSellPayload, bus, content),
    );
    ctx.store.registerReducer('shop:restock', (st) => restockReducer(st, bus, content));
    // Morning restock rides the same psleep/tick paths (must run AFTER the
    // farming room's rollover + shipping's day-close, both gated + chained).
    ctx.store.registerReducer('player:sleep', (st) => restockReducer(st, bus, content));
    ctx.store.registerReducer('time:tick', (st) => restockReducer(st, bus, content));
  },
});