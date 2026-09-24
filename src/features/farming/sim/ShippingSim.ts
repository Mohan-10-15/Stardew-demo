/**
 * Shipping box + sleep (WORKER-2 lane, contract m1-contracts.md sections 3 & 6,
 * m2-contracts.md section 5).
 *
 * The shipping box lives in state.extensions.farming.shippingBox (ItemStack[]).
 * On `player:sleep` the world advances to the next day 06:00, the full rollover
 * runs (weather + effects + crops + forage), every stack is paid out (base
 * price x quality multiplier), the ended day's `day:summary` is emitted, energy
 * is restored to max, then `shipping:report` + `day:started` are emitted and
 * ctx.persist() is kicked off (autosave). On a forced pass-out (2:00 AM via
 * time:tick) the rollover, payout and day:summary run too, but no energy
 * restore and no `day:started` (WORKER-3 owns the morning hand-off).
 *
 * All of this runs inside the reducer, synchronously; persist() is deferred to
 * a microtask (after the Store commits the new state) so the save always
 * captures the post-sleep world, and tests can flush it with a macrotask turn.
 */
import type { EventBus } from '@game/core/events';
import type { ContentDb } from '@game/core/content';
import type { FeatureContext, FeatureModule } from '@game/core/feature';
import { defineFeature } from '@game/core/feature';
import type { Rng } from '@game/core/rng';
import type { GameState, ItemStack } from '@game/core/types';
import { ensureFarmingExt, ensureWeatherExt, readFarmingExt, writeFarmingExt } from './ext';
import type { CropDefs } from './growth';
import { applyFarmRollover } from './rollover';
import { bumpStat, closeDay, openDayNeedsClosing } from './summary';
import { clampInt, nextDayMorning } from './utils';

/** Quality multipliers: 0 normal x1, 1 silver x1.25, 2 gold x1.5. */
export const QUALITY_MULT: readonly number[] = [1, 1.25, 1.5];

export interface ShippingReportSold {
  itemId: string;
  qty: number;
  gold: number;
}

export interface ShippingReport {
  sold: ShippingReportSold[];
  total: number;
}

/** Resolve an item's base selling price (item def first, crop def fallback). */
export function shipmentPrice(itemId: string, content: ContentDb): number {
  const item = content.items.get(itemId);
  if (item) return item.price.base;
  const crop = content.crops.get(itemId);
  if (crop) return crop.sell.base;
  return 0;
}

/** Pay out every stack in the box, empty it, emit `shipping:report` and bump
 * the day's summary counters (day:sold, day:sold-gold, day:gold). */
export function payoutShipping(state: GameState, bus: EventBus, content: ContentDb): GameState {
  const ext = readFarmingExt(state);
  const sold: ShippingReportSold[] = [];
  let total = 0;
  for (const stack of ext.shippingBox) {
    const base = shipmentPrice(stack.id, content);
    const gold = Math.round(base * stack.qty * (QUALITY_MULT[stack.quality] ?? 1));
    sold.push({ itemId: stack.id, qty: stack.qty, gold });
    total += gold;
  }
  let st: GameState = writeFarmingExt(
    { ...state, player: { ...state.player, money: state.player.money + total } },
    { ...ext, shippingBox: [] },
  );
  for (const row of sold) {
    st = bumpStat(st, `day:sold:${row.itemId}`, row.qty);
    st = bumpStat(st, `day:sold-gold:${row.itemId}`, row.gold);
  }
  st = bumpStat(st, 'day:gold', total);
  bus.emit('shipping:report', { sold, total });
  return st;
}

/** Move a whole hotbar stack into the shipping box. */
export function shippingInsert(state: GameState, slot: number, bus: EventBus): GameState {
  const inv = state.player.inventory;
  const idx = clampInt(slot, 0, Math.max(0, inv.capacity - 1));
  const stack = inv.slots[idx];
  if (!stack) return state;
  const ext = readFarmingExt(state);
  const slots = [...inv.slots];
  slots[idx] = null;
  const mergeIdx = ext.shippingBox.findIndex(
    (b) => b.id === stack.id && b.quality === stack.quality,
  );
  const box: ItemStack[] =
    mergeIdx >= 0
      ? ext.shippingBox.map((b, i) => (i === mergeIdx ? { ...b, qty: b.qty + stack.qty } : b))
      : [...ext.shippingBox, stack];
  const next = writeFarmingExt(
    { ...state, player: { ...state.player, inventory: { ...inv, slots } } },
    { ...ext, shippingBox: box },
  );
  bus.emit('shipping:inserted', { slot: idx, itemId: stack.id, qty: stack.qty });
  return next;
}

/** Pay out the night's shipping + close the day that just ended (forced
 * pass-out path, contract §5). Runs AFTER the farming room's time:tick so the
 * rollover is already applied; idempotent once per night. */
export function passOutDayReducer(
  state: GameState,
  bus: EventBus,
  content: ContentDb,
): GameState {
  if (!state.world.passedOut) return state;
  if (!openDayNeedsClosing(state)) return state;
  state = payoutShipping(state, bus, content);
  return closeDay(state, bus);
}

/** One full sleep: next morning + full rollover + payout + summary + energy. */
export function sleepReducer(
  state: GameState,
  cropDefs: CropDefs,
  rng: Rng,
  bus: EventBus,
  content: ContentDb,
  persist: () => Promise<void>,
): GameState {
  let st = ensureFarmingExt(state);
  st = ensureWeatherExt(st);
  const world = nextDayMorning(st.world);
  st = { ...st, world };

  const roll = applyFarmRollover(st, cropDefs, rng, bus, content);
  st = roll.state;

  bus.emit('day:rollover', st.world);

  st = payoutShipping(st, bus, content);
  st = closeDay(st, bus);
  st = { ...st, player: { ...st.player, energy: st.player.energyMax } };

  bus.emit('day:started', st.world);
  queueMicrotask(() => void persist());
  return st;
}

export const shippingSim: FeatureModule = defineFeature({
  id: 'farming:shipping',
  lane: 'sim',
  setup(ctx: FeatureContext) {
    ctx.store.replaceState(ensureFarmingExt(ctx.store.state));
    ctx.store.replaceState(ensureWeatherExt(ctx.store.state));
    const bus = ctx.bus;
    const content = ctx.content;
    const cropDefs: CropDefs = (id) => content.crops.get(id);
    const persist = ctx.persist;

    ctx.store.registerReducer('shipping:insert', (st, action) => {
      const payload = action.payload as { slot: number };
      return shippingInsert(st, payload.slot, bus);
    });
    ctx.store.registerReducer('player:sleep', (st, _action, rng) =>
      sleepReducer(st, cropDefs, rng, bus, content, persist),
    );
    ctx.store.registerReducer('time:tick', (st) => passOutDayReducer(st, bus, content));
  },
});
