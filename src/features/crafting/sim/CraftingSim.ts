/**
 * crafting:sim — learnable recipes, cooking, and timed food buffs (WORKER-2).
 *
 * Two recipe kinds, both dispatched through `crafting:craft`:
 *   - crafting: one output item (machines, furniture) from ingredient stacks.
 *     The output must already fit the bag — the craft is atomic: on a full
 *     inventory nothing is consumed.
 *   - cooking: the recipe's `food` stats are recorded against its output item,
 *     and `player:eat` applies them.
 * Recipes are gated by `unlock {skill, level}` (any skill at or above the
 * level); recipes without an unlock are always known.
 *
 * Eating adds instant energy/health (capped at the player's maxima) and
 * begins time-boxed buffs in `extensions.crafting.buffs`, each guarded by an
 * absolute-minute expiry that the `time:tick` pass prunes.
 */
import { defineFeature, type FeatureContext, type FeatureModule } from '@game/core/feature';
import type { Rng } from '@game/core/rng';
import type { ContentDb } from '@game/core/content';
import type { GameState } from '@game/core/types';
import { addStackToInventory } from '../../inventory/sim/InventorySim';
import { removeStackFromInventory } from '../../inventory/sim/InventorySim';
import { skillLevelOf, type SkillKey } from '../../skills/sim/SkillsSim';

export const CRAFTING_EXT_ID = 'crafting';

export interface ActiveBuff {
  stat: string;
  amount: number;
  /** Absolute minute at which the buff stops applying. */
  expiresAt: number;
}

export interface CraftingExt {
  buffs: ActiveBuff[];
}

export function absoluteMinutes(state: GameState): number {
  const { dayCount } = state.world;
  const { hour, minute } = state.world.clock;
  return dayCount * 1440 + hour * 60 + minute;
}

export function readCraftingExt(state: GameState): CraftingExt {
  const raw = state.extensions[CRAFTING_EXT_ID];
  if (raw && typeof raw === 'object' && Array.isArray((raw as { buffs?: unknown }).buffs)) {
    return raw as unknown as CraftingExt;
  }
  return { buffs: [] };
}

export function writeCraftingExt(state: GameState, ext: CraftingExt): GameState {
  return { ...state, extensions: { ...state.extensions, [CRAFTING_EXT_ID]: { ...ext } } };
}

export function ensureCraftingExt(state: GameState): GameState {
  if (state.extensions[CRAFTING_EXT_ID] !== undefined) return state;
  return writeCraftingExt(state, { buffs: [] });
}

/** Buffs still inside their time window, in application order. */
export function activeBuffs(state: GameState): ActiveBuff[] {
  const now = absoluteMinutes(state);
  return readCraftingExt(state).buffs.filter((b) => b.expiresAt > now);
}

/** Is the recipe learned at the player's current skill levels? */
export function recipeUnlocked(state: GameState, recipeId: string, content: ContentDb): boolean {
  const recipe = content.recipes.get(recipeId);
  if (!recipe) return false;
  if (!recipe.unlock) return true;
  return skillLevelOf(state, recipe.unlock.skill as SkillKey) >= recipe.unlock.level;
}

/** The food stats of a cooked item, or null when it is not cookable. */
export function foodFor(content: ContentDb, itemId: string) {
  for (const recipe of content.recipes.values()) {
    if (recipe.kind === 'cooking' && recipe.output.itemId === itemId) return recipe.food ?? null;
  }
  return null;
}

export function countOf(state: GameState, itemId: string): number {
  let total = 0;
  for (const slot of state.player.inventory.slots) if (slot && slot.id === itemId) total += slot.qty;
  return total;
}

export interface CraftResult {
  state: GameState;
  ok: boolean;
  reason?: string;
}

export function denyCraft(state: GameState, reason: string, emit: (type: string, payload: unknown) => void, extra?: Record<string, unknown>): CraftResult {
  emit('crafting:denied', { reason, ...extra });
  return { state, ok: false, reason };
}

export function craftRecipe(state: GameState, recipeId: string, content: ContentDb, emit: (type: string, payload: unknown) => void): CraftResult {
  const recipe = content.recipes.get(recipeId);
  if (!recipe) return denyCraft(state, 'unknown-recipe', emit, { recipeId });
  if (!recipeUnlocked(state, recipeId, content)) return denyCraft(state, 'locked', emit, { recipeId });
  const probe = addStackToInventory(state, { id: recipe.output.itemId, qty: recipe.output.qty, quality: 0 });
  if (!probe.added) return denyCraft(state, 'inventory-full', emit, { recipeId });
  for (const ing of recipe.ingredients) {
    if (countOf(state, ing.itemId) < ing.qty) return denyCraft(state, 'missing-ingredients', emit, { recipeId });
  }
  let st = state;
  for (const ing of recipe.ingredients) {
    const removed = removeStackFromInventory(st, ing.itemId, ing.qty);
    if (removed.removed < ing.qty) return denyCraft(state, 'missing-ingredients', emit, { recipeId });
    st = removed.state;
  }
  st = addStackToInventory(st, { id: recipe.output.itemId, qty: recipe.output.qty, quality: 0 }).state;
  emit('crafting:crafted', { recipeId, itemId: recipe.output.itemId, qty: recipe.output.qty });
  return { state: st, ok: true };
}

export interface EatResult {
  state: GameState;
  ok: boolean;
  reason?: string;
  energy?: number;
  health?: number;
  buffs?: ActiveBuff[];
}

export function eatItem(state: GameState, slot: number, content: ContentDb, emit: (type: string, payload: unknown) => void): EatResult {
  const stack = state.player.inventory.slots[slot];
  if (!stack) {
    emit('crafting:denied', { reason: 'no-slot', slot });
    return { state, ok: false, reason: 'no-slot' };
  }
  const food = foodFor(content, stack.id);
  if (!food) {
    emit('crafting:denied', { reason: 'not-food', slot });
    return { state, ok: false, reason: 'not-food' };
  }
  const removed = removeStackFromInventory(state, stack.id, 1);
  if (removed.removed < 1) {
    emit('crafting:denied', { reason: 'not-food', slot });
    return { state, ok: false, reason: 'not-food' };
  }
  const player = removed.state.player;
  const energy = Math.min(player.energyMax, player.energy + food.energy);
  const health = Math.min(player.healthMax, player.health + food.health);
  const now = absoluteMinutes(removed.state);
  const buffs = food.buffs.map((b) => ({ stat: b.stat, amount: b.amount, expiresAt: now + b.hours * 60 }));
  const fixed = { ...removed.state, player: { ...player, energy, health } };
  const ext = readCraftingExt(fixed);
  const next = writeCraftingExt(fixed, { buffs: [...ext.buffs, ...buffs] });
  emit('food:eaten', { itemId: stack.id, energy: food.energy, health: food.health, buffs });
  return { state: next, ok: true, energy, health, buffs };
}

/** Drop buffs whose expiry has passed (called from the time tick). */
export function pruneBuffs(state: GameState): GameState {
  const now = absoluteMinutes(state);
  const ext = readCraftingExt(state);
  const sorted = ext.buffs.filter((b) => b.expiresAt > now);
  if (sorted.length === ext.buffs.length) return state;
  return writeCraftingExt(state, { buffs: sorted });
}

export const craftingSim: FeatureModule = defineFeature({
  id: 'crafting:sim',
  lane: 'sim',
  setup(ctx: FeatureContext) {
    ctx.store.replaceState(ensureCraftingExt(ctx.store.state));
    const emit = (type: string, payload: unknown) => ctx.bus.emit(type, payload);

    ctx.store.registerReducer('crafting:craft', (st: GameState, action, _rng: Rng) => {
      const p = action.payload as { recipeId?: unknown } | null;
      if (!p || typeof p.recipeId !== 'string') return st;
      return craftRecipe(st, p.recipeId, ctx.content, emit).state;
    });
    ctx.store.registerReducer('player:eat', (st, action, _rng) => {
      const p = action.payload as { slot?: unknown } | null;
      if (!p || typeof p.slot !== 'number') return st;
      return eatItem(st, p.slot, ctx.content, emit).state;
    });
    // Core advances time first; prune buffs against the new absolute minute.
    ctx.store.registerReducer('time:tick', (st, _action, _rng) => pruneBuffs(st));
  },
});