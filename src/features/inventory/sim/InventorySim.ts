/**
 * Inventory + hotbar sim (WORKER-2 lane). Renders nothing; the UI reads the
 * inventory from state on `state:changed`.
 */
import type { EventBus } from '@game/core/events';
import { defineFeature, type FeatureContext, type FeatureModule } from '@game/core/feature';
import type { GameState, ItemStack, QualityTier } from '@game/core/types';
import { clampInt } from '../../farming/sim/utils';

export interface InventorySummary {
  id: string;
  qty: number;
  quality: QualityTier;
}

export const MAX_STACK = 999;

/** Merge `stack` into `slots` (same id+quality up to MAX_STACK, else empty slot). */
export function addStackToSlots(
  slots: (ItemStack | null)[],
  stack: ItemStack,
): { slots: (ItemStack | null)[]; added: boolean } {
  let rest = stack;
  const list = [...slots];
  for (let i = 0; i < list.length; i++) {
    const s = list[i];
    if (!s || s.id !== rest.id || s.quality !== rest.quality) continue;
    const room = MAX_STACK - s.qty;
    if (room <= 0) continue;
    const add = Math.min(rest.qty, room);
    list[i] = { ...s, qty: s.qty + add };
    const leftover = rest.qty - add;
    if (leftover <= 0) return { slots: list, added: true };
    rest = { ...rest, qty: leftover };
  }
  const idx = list.findIndex((s) => s === null);
  if (idx === -1) return { slots: list, added: false };
  list[idx] = rest;
  return { slots: list, added: true };
}

/** Add a stack to the player's inventory; returns new state when it fit. */
export function addStackToInventory(
  state: GameState,
  stack: ItemStack,
): { state: GameState; added: boolean } {
  const inv = state.player.inventory;
  const { slots, added } = addStackToSlots(inv.slots, stack);
  if (!added) return { state, added: false };
  return {
    state: { ...state, player: { ...state.player, inventory: { ...inv, slots } } },
    added: true,
  };
}

/**
 * Try to add `qty` units of `itemId` to inventory. Stackable items merge up to
 * MAX_STACK; non-stackable items cost one unit per empty slot. Returns how many
 * units actually fit (<= qty), or -1 when none do.
 */
export function tryAddToSlots(
  state: GameState,
  itemId: string,
  qty: number,
  canStack: boolean,
): { state: GameState; added: number } {
  let st = state;
  let remaining = qty;
  if (canStack) {
    const res = addStackToInventory(st, { id: itemId, qty: remaining, quality: 0 });
    if (!res.added) return { state: st, added: 0 };
    st = res.state;
    return { state: st, added: qty };
  }
  for (let i = 0; i < qty && remaining > 0; i++) {
    const res = addStackToInventory(st, { id: itemId, qty: 1, quality: 0 });
    if (!res.added) break;
    st = res.state;
    remaining -= 1;
  }
  return { state: st, added: qty - remaining };
}

/** Aggregated view of the bag, merged by id+quality, first-appearance order. */
export function summarizeInventory(state: GameState): InventorySummary[] {
  const out: InventorySummary[] = [];
  for (const slot of state.player.inventory.slots) {
    if (!slot) continue;
    const found = out.find((o) => o.id === slot.id && o.quality === slot.quality);
    if (found) {
      found.qty += slot.qty;
    } else {
      out.push({ id: slot.id, qty: slot.qty, quality: slot.quality });
    }
  }
  return out;
}

export function selectSlotReducer(state: GameState, slot: number, bus: EventBus): GameState {
  const inv = state.player.inventory;
  const next = clampInt(slot, 0, inv.capacity - 1);
  bus.emit('inventory:selected', { slot: next });
  if (next === inv.selected) return state;
  return { ...state, player: { ...state.player, inventory: { ...inv, selected: next } } };
}

export function moveSlotsReducer(
  state: GameState,
  from: number,
  to: number,
  bus: EventBus,
): GameState {
  const inv = state.player.inventory;
  const cap = inv.capacity;
  const fi = clampInt(from, 0, cap - 1);
  const ti = clampInt(to, 0, cap - 1);
  if (fi === ti) return state;
  const slots = [...inv.slots];
  const a = slots[fi];
  if (!a) return state;
  const b = slots[ti];
  if (b && b.id === a.id && b.quality === a.quality && b.qty < MAX_STACK) {
    const moved = Math.min(a.qty, MAX_STACK - b.qty);
    slots[ti] = { ...b, qty: b.qty + moved };
    slots[fi] = a.qty - moved > 0 ? { ...a, qty: a.qty - moved } : null;
  } else {
    slots[ti] = a;
    slots[fi] = b ?? null;
  }
  bus.emit('inventory:moved', { from: fi, to: ti });
  return { ...state, player: { ...state.player, inventory: { ...inv, slots } } };
}

export const inventorySim: FeatureModule = defineFeature({
  id: 'inventory:sim',
  lane: 'sim',
  setup(ctx: FeatureContext) {
    const bus = ctx.bus;
    ctx.store.registerReducer('player:select-slot', (st, action) => {
      const payload = action.payload as { slot: number };
      return selectSlotReducer(st, payload.slot, bus);
    });
    ctx.store.registerReducer('inventory:move', (st, action) => {
      const payload = action.payload as { from: number; to: number };
      return moveSlotsReducer(st, payload.from, payload.to, bus);
    });
  },
});
