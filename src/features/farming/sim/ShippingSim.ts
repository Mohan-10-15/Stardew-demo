/**
 * Shipping box + sleep (WORKER-2 lane, contract m1-contracts.md sections 3 & 6).
 *
 * The shipping box lives in state.extensions.farming.shippingBox (ItemStack[]).
 * On `player:sleep` the world advances to the next day 06:00, crops/soil run
 * their day rollover, weather rolls, every stack is paid out (base price x
 * quality multiplier), energy is restored to max, then `shipping:report` +
 * `day:started` are emitted and ctx.persist() is kicked off (autosave).
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
import { applyCropRollover, type CropDefs } from './growth';
import { applyWeatherRoll } from './weather';
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

/** Pay out every stack in the box, empty it and emit `shipping:report`. */
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
  const report: ShippingReport = { sold, total };
  const next = writeFarmingExt(
    { ...state, player: { ...state.player, money: state.player.money + total } },
    { ...ext, shippingBox: [] },
  );
  bus.emit('shipping:report', report);
  return next;
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

/** One full sleep: next morning + day rollover + payout + energy restore. */
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

  const roll = applyCropRollover(st, cropDefs);
  st = roll.state;
  st = applyWeatherRoll(st, rng, bus);

  bus.emit('day:rollover', st.world);
  for (const w of roll.withered) bus.emit('crop:withered', w);

  st = payoutShipping(st, bus, content);
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
  },
});
