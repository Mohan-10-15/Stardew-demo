/**
 * crafting:ui format-layer specs (WORKER-3 lane). The dialog DOM is browser-
 * only, so the headless gate pins the pure layer it renders from: recipe rows
 * (known/locked, craftable, ingredient haves against the live bag), lock and
 * ingredient labels, and the food/buff lines. Real recipes + a real sim state
 * are used so the UI can never drift from the content table.
 */
import { describe, expect, it } from 'vitest';
import '@game/features/crafting-ui';
import { craftingSim } from '@game/features/crafting';
import { skillsSim } from '@game/features/skills/sim/SkillsSim';
import { createSim, DEFAULT_MODULES, type SimFixture } from '../sim/harness';
import {
  buffLabel,
  buildRecipeRows,
  foodLabel,
  ingredientLabel,
  lockLabel,
  skillLabel,
} from '@game/features/crafting-ui';

async function makeFixture(withSkills = false): Promise<SimFixture> {
  const modules = withSkills ? [...DEFAULT_MODULES, craftingSim, skillsSim] : [...DEFAULT_MODULES, craftingSim];
  return createSim({ modules });
}

/** Raise `skill` to the given level via bulk XP (linear 100/200/300/... curve). */
function levelUp(fx: SimFixture, skill: string, level: number): void {
  let total = 0;
  for (let i = 0; i < level; i++) total += 100 * (i + 1);
  fx.dispatch('skills:grant-xp', { skill, amount: total });
}

function rowById(fx: SimFixture, recipeId: string) {
  const rows = buildRecipeRows(fx.content, fx.state);
  const row = rows.find((r) => r.recipeId === recipeId);
  expect(row).toBeDefined();
  return row!;
}

describe('buildRecipeRows — knowledge + craftability', () => {
  it('covers every authored recipe split by kind', async () => {
    const fx = await makeFixture();
    const rows = buildRecipeRows(fx.content, fx.state);
    const authored = [...fx.content.recipes.keys()];
    expect(rows.map((r) => r.recipeId)).toEqual(authored);
    const kindOf = (kind: 'crafting' | 'cooking') =>
      [...fx.content.recipes.values()].filter((r) => r.kind === kind).length;
    expect(rows.filter((r) => r.kind === 'crafting')).toHaveLength(kindOf('crafting'));
    expect(rows.filter((r) => r.kind === 'cooking')).toHaveLength(kindOf('cooking'));
  });

  it('always-known cooking recipes are unlocked and craftable at level 0', async () => {
    const fx = await makeFixture();
    fx.giveItem('egg', 1);
    const fried = rowById(fx, 'fried-egg');
    expect(fried.unlocked).toBe(true);
    expect(fried.canCraft).toBe(true);
    fx.giveItem('ember-bloom', 1);
    fx.giveItem('fiber', 3);
    const tea = rowById(fx, 'ember-bloom-tea');
    expect(tea.unlocked).toBe(true);
    expect(tea.canCraft).toBe(true);
  });

  it('gated recipes stay locked and unmuted only after the skill level', async () => {
    const fx = await makeFixture(true);
    const machine = rowById(fx, 'mayonnaise-machine');
    expect(machine.unlocked).toBe(false);
    expect(machine.canCraft).toBe(false);
    expect(machine.lockSkill).toBe('foraging');
    expect(machine.lockLevel).toBe(2);
    expect(machine.ingredients.length).toBeGreaterThan(0);

    levelUp(fx, 'foraging', 2);
    fx.giveItem('wood', 20);
    fx.giveItem('fiber', 5);
    const now = rowById(fx, 'mayonnaise-machine');
    expect(now.unlocked).toBe(true);
    expect(now.canCraft).toBe(true);
  });

  it('canCraft flips false when any single ingredient runs short', async () => {
    const fx = await makeFixture();
    fx.giveItem('wood', 20);
    const machine = rowById(fx, 'mayonnaise-machine');
    expect(machine.canCraft).toBe(false);
    const fiber = machine.ingredients.find((i) => i.itemId === 'fiber');
    expect(fiber?.have).toBe(0);
  });

  it('ingredient haves track the live bag and drain after a craft', async () => {
    const fx = await makeFixture(true);
    levelUp(fx, 'foraging', 2);
    fx.giveItem('wood', 20);
    fx.giveItem('fiber', 5);
    fx.dispatch('crafting:craft', { recipeId: 'mayonnaise-machine' });
    const aft = rowById(fx, 'mayonnaise-machine');
    expect(aft.canCraft).toBe(false);
    expect(aft.ingredients.find((i) => i.itemId === 'wood')?.have).toBe(0);
    expect(aft.ingredients.find((i) => i.itemId === 'fiber')?.have).toBe(0);
  });

  it('cooking rows carry food stats and buff rows', async () => {
    const fx = await makeFixture();
    const omlette = rowById(fx, 'cheese-omelette');
    expect(omlette.energy).toBe(40);
    expect(omlette.health).toBe(18);
    expect(omlette.buffs).toEqual([{ stat: 'farming', amount: 1, hours: 2 }]);
  });
});

describe('crafting labels', () => {
  it('localizes skill names and falls back to the raw id', () => {
    expect(skillLabel('farming')).toBe('Farming');
    expect(skillLabel('nope')).toBe('nope');
  });

  it('renders a lock requirement only for locked rows', () => {
    expect(lockLabel(undefined, undefined)).toBeNull();
    expect(lockLabel('foraging', 2)).toBe('Unlocks at Foraging Level 2');
  });

  it('renders ingredient lines with owned counts only when short', () => {
    const needBoth = [
      { itemId: 'wood', name: 'Wood', qty: 20, have: 8 },
      { itemId: 'fiber', name: 'Fiber', qty: 5, have: 5 },
    ];
    expect(ingredientLabel(needBoth)).toBe('Wood x20 (have 8) · Fiber x5');
  });

  it('renders food stats and each buff line', () => {
    expect(foodLabel(40, 18)).toBe('+40 energy · +18 health');
    expect(foodLabel(undefined, undefined)).toBeNull();
    expect(buffLabel({ stat: 'farming', amount: 1, hours: 2 })).toBe('Farming +1 (2h)');
    expect(buffLabel({ stat: 'luck', amount: 1, hours: 3 })).toBe('luck +1 (3h)');
  });
});