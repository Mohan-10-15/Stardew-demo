/**
 * Pure crafting-menu formatting helpers (WORKER-3 lane). No DOM access — safe
 * to import and unit-test in Node. All display strings come from the i18n
 * table; recipe knowledge is read from the crafting sim's pure selectors so
 * the dialog never peeks at reducer internals.
 */
import type { ContentDb } from '@game/core/content';
import type { GameState } from '@game/core/types';
import { countOf, recipeUnlocked } from '../crafting';
import { MESSAGES, type Messages } from '../ui-kit/i18n/en';
import { replaceTokens } from '../ui-kit/template';

export interface CraftIngredientRow {
  itemId: string;
  name: string;
  qty: number;
  have: number;
}

export interface CraftBuffRow {
  stat: string;
  amount: number;
  hours: number;
}

export interface RecipeRow {
  recipeId: string;
  /** Recipe display name (the crafted/cooked product name). */
  name: string;
  kind: 'crafting' | 'cooking';
  outputId: string;
  outputQty: number;
  unlocked: boolean;
  /** Craftable right now: known AND every ingredient stack is fully held. */
  canCraft: boolean;
  lockSkill?: string;
  lockLevel?: number;
  ingredients: CraftIngredientRow[];
  energy?: number;
  health?: number;
  buffs: CraftBuffRow[];
}

/** i18n fallback label for an unknown item id, e.g. "Unknown item (ghost-egg)". */
export function unknownRecipeItemLabel(id: string, messages: Messages = MESSAGES): string {
  return `${replaceTokens(messages.crafting.unknownItem, {})} (${id})`;
}

/** Localized skill name, falling back to the raw id when the table lacks it. */
export function skillLabel(skill: string, messages: Messages = MESSAGES): string {
  const table = messages.summary.skills as Record<string, string>;
  return table[skill] ?? skill;
}

/** "Unlocks at Foraging Level 2" (only for a locked recipe). */
export function lockLabel(skill: string | undefined, level: number | undefined, messages: Messages = MESSAGES): string | null {
  if (skill === undefined || level === undefined) return null;
  return replaceTokens(messages.crafting.unlockAt, { skill: skillLabel(skill, messages), level: String(level) });
}

/** Ingredient line: "Wood x20 · Fiber x5" ("· own 8" when lacking a stack). */
export function ingredientLabel(ingredients: readonly CraftIngredientRow[], messages: Messages = MESSAGES): string {
  const parts = ingredients.map((ing) => {
    const base = `${ing.name} ${replaceTokens(messages.crafting.qtyBadge, { qty: String(ing.qty) })}`;
    if (ing.have < ing.qty) {
      return base + replaceTokens(messages.crafting.shortBadge, { have: String(ing.have) });
    }
    return base;
  });
  return replaceTokens(messages.crafting.ingredients, { ingredients: parts.join(' · ') });
}

/** "+40 energy · +18 health" from food stats. */
export function foodLabel(
  energy: number | undefined,
  health: number | undefined,
  messages: Messages = MESSAGES,
): string | null {
  if (energy === undefined && health === undefined) return null;
  return replaceTokens(messages.crafting.foodStats, { energy: String(energy ?? 0), health: String(health ?? 0) });
}

/** "Farming +1 (2h)" for one buff row. */
export function buffLabel(buff: CraftBuffRow, messages: Messages = MESSAGES): string {
  return replaceTokens(messages.crafting.buffLine, {
    stat: skillLabel(buff.stat, messages),
    amount: String(buff.amount),
    hours: String(buff.hours),
  });
}

/** All recipes as dialog rows: known/locked, craftable, with ingredient haves. */
export function buildRecipeRows(content: ContentDb, state: GameState, messages: Messages = MESSAGES): RecipeRow[] {
  const rows: RecipeRow[] = [];
  for (const recipe of content.recipes.values()) {
    const ingredients: CraftIngredientRow[] = recipe.ingredients.map((ing) => ({
      itemId: ing.itemId,
      name: itemName(content, ing.itemId, messages),
      qty: ing.qty,
      have: countOf(state, ing.itemId),
    }));
    const unlocked = recipeUnlocked(state, recipe.id, content);
    let canCraft = unlocked;
    if (canCraft) {
      for (const ing of ingredients) if (ing.have < ing.qty) canCraft = false;
    }
    rows.push({
      recipeId: recipe.id,
      name: recipe.name,
      kind: recipe.kind,
      outputId: recipe.output.itemId,
      outputQty: recipe.output.qty,
      unlocked,
      canCraft,
      lockSkill: recipe.unlock?.skill,
      lockLevel: recipe.unlock?.level,
      ingredients,
      energy: recipe.food?.energy,
      health: recipe.food?.health,
      buffs: (recipe.food?.buffs ?? []).map((b) => ({ stat: b.stat, amount: b.amount, hours: b.hours })),
    });
  }
  return rows;
}

function itemName(content: ContentDb, id: string, messages: Messages): string {
  const item = content.items.get(id);
  return item?.name && item.name.length > 0 ? item.name : unknownRecipeItemLabel(id, messages);
}