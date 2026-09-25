/**
 * crafting:sim specs (WORKER-2 lane). Covers learnable recipes with skill-level
 * unlock gating, atomic ingredient consumption (nothing consumed on a full bag
 * or short supplies), cooking, and eating — instant energy/health plus
 * time-boxed buffs that `time:tick` prunes at their absolute-minute expiry.
 */
import { describe, expect, it } from 'vitest';
import { craftingSim, activeBuffs, foodFor, recipeUnlocked } from '@game/features/crafting';
import { skillsSim } from '@game/features/skills/sim/SkillsSim';
import { createSim, DEFAULT_MODULES, type SimFixture } from './harness';

async function makeFixture(withSkills = false): Promise<SimFixture> {
  const modules = withSkills ? [...DEFAULT_MODULES, craftingSim, skillsSim] : [...DEFAULT_MODULES, craftingSim];
  const fx = await createSim({ modules });
  fx.giveItem('egg', 3);
  return fx;
}

/** Raise `skill` to the given level via bulk XP (linear 100/200/300/... curve). */
function levelUp(fx: SimFixture, skill: string, level: number): void {
  let total = 0;
  for (let i = 0; i < level; i++) total += 100 * (i + 1);
  fx.dispatch('skills:grant-xp', { skill, amount: total });
}

describe('crafting:craft — always-known recipe', () => {
  it('consumes ingredients and adds the output at level 0', async () => {
    const fx = await makeFixture();
    const crafted = fx.capture<any>('crafting:crafted');
    fx.dispatch('crafting:craft', { recipeId: 'fried-egg' });
    expect(crafted).toEqual([{ recipeId: 'fried-egg', itemId: 'fried-egg', qty: 1 }]);
    expect(fx.state.player.inventory.slots.some((s) => s?.id === 'fried-egg')).toBe(true);
    const eggs = fx.state.player.inventory.slots.filter((s) => s?.id === 'egg').reduce((n, s) => n + (s?.qty ?? 0), 0);
    expect(eggs).toBe(2);
  });

  it('denies with missing ingredients and consumes nothing', async () => {
    const fx = await makeFixture();
    fx.giveItem('fiber', 10);
    const denied = fx.capture<any>('crafting:denied');
    fx.dispatch('crafting:craft', { recipeId: 'ember-bloom-tea' });
    expect(denied[0]?.reason).toBe('missing-ingredients');
    expect(fx.state.player.inventory.slots.some((s) => s?.id === 'ember-bloom-tea')).toBe(false);

    fx.giveItem('ember-bloom', 5);
    fx.dispatch('crafting:craft', { recipeId: 'ember-bloom-tea' });
    expect(fx.state.player.inventory.slots.some((s) => s?.id === 'ember-bloom-tea')).toBe(true);
    const fiber = fx.state.player.inventory.slots.filter((s) => s?.id === 'fiber').reduce((n, s) => n + (s?.qty ?? 0), 0);
    expect(fiber).toBe(7);
  });

  it('denies a full bag without consuming ingredients', async () => {
    const fx = await makeFixture();
    fx.giveItem('ember-bloom', 5);
    fx.giveItem('fiber', 10);
    const denied = fx.capture<any>('crafting:denied');
    for (let i = 0; i < 12; i++) {
      if (fx.state.player.inventory.slots[i] === null) fx.setSlot(i, { id: 'rock', qty: 1, quality: 0 });
    }
    fx.dispatch('crafting:craft', { recipeId: 'ember-bloom-tea' });
    expect(denied[0]?.reason).toBe('inventory-full');
    expect(fx.state.player.inventory.slots.some((s) => s?.id === 'ember-bloom-tea')).toBe(false);
    const bloom = fx.state.player.inventory.slots.filter((s) => s?.id === 'ember-bloom').reduce((n, s) => n + (s?.qty ?? 0), 0);
    const fiber = fx.state.player.inventory.slots.filter((s) => s?.id === 'fiber').reduce((n, s) => n + (s?.qty ?? 0), 0);
    expect(bloom).toBe(5);
    expect(fiber).toBe(10);
  });

  it('rejects unknown recipe ids', async () => {
    const fx = await makeFixture();
    const denied = fx.capture<any>('crafting:denied');
    fx.dispatch('crafting:craft', { recipeId: 'made-up-recipe' });
    expect(denied[0]?.reason).toBe('unknown-recipe');
  });
});

describe('crafting unlock gating', () => {
  it('locks recipes until the unlock skill level is reached', async () => {
    const fx = await makeFixture(true);
    fx.giveItem('wood', 30);
    fx.giveItem('fiber', 20);
    const denied = fx.capture<any>('crafting:denied');
    fx.dispatch('crafting:craft', { recipeId: 'mayonnaise-machine' });
    expect(denied[0]?.reason).toBe('locked');
    expect(fx.state.player.inventory.slots.some((s) => s?.id === 'mayonnaise-machine')).toBe(false);

    levelUp(fx, 'foraging', 2);
    fx.dispatch('crafting:craft', { recipeId: 'mayonnaise-machine' });
    const crafted = fx.state.player.inventory.slots.some((s) => s?.id === 'mayonnaise-machine');
    expect(crafted).toBe(true);
    expect(fx.state.player.inventory.slots.filter((s) => s?.id === 'wood').reduce((n, s) => n + (s?.qty ?? 0), 0)).toBe(10);
  });

  it('recipeUnlocked reflects the player skill level', async () => {
    const fx = await makeFixture(true);
    expect(recipeUnlocked(fx.state, 'loom', fx.content)).toBe(false);
    levelUp(fx, 'foraging', 4);
    expect(recipeUnlocked(fx.state, 'loom', fx.content)).toBe(true);
  });
});

describe('cooking and eating', () => {
  it('eats a non-food item fails cleanly', async () => {
    const fx = await makeFixture();
    const denied = fx.capture<any>('crafting:denied');
    const woodSlot = fx.giveItem('wood', 1);
    fx.dispatch('player:eat', { slot: woodSlot });
    expect(denied[0]?.reason).toBe('not-food');
  });

  it('eats an empty or invalid slot fails cleanly', async () => {
    const fx = await makeFixture();
    const denied = fx.capture<any>('crafting:denied');
    fx.dispatch('player:eat', { slot: 99 });
    expect(denied[0]?.reason).toBe('no-slot');
  });

  it('adds instant energy/health and reports food:eaten', async () => {
    const fx = await makeFixture();
    fx.dispatch('crafting:craft', { recipeId: 'fried-egg' });
    fx.store.state.player.energy = 200;
    fx.store.state.player.health = 40;
    const eaten = fx.capture<any>('food:eaten');
    const slot = fx.state.player.inventory.slots.findIndex((s) => s?.id === 'fried-egg');
    fx.dispatch('player:eat', { slot });
    expect(eaten).toEqual([{ itemId: 'fried-egg', energy: 20, health: 8, buffs: [] }]);
    expect(fx.state.player.energy).toBe(220);
    expect(fx.state.player.health).toBe(48);
  });

  it('starts time-boxed buffs and prunes them after their expiry', async () => {
    const fx = await makeFixture(true);
    levelUp(fx, 'farming', 4);
    fx.giveItem('milk', 1);
    fx.giveItem('cheese', 1);
    fx.dispatch('crafting:craft', { recipeId: 'cheese-omelette' });
    fx.store.state.player.energy = 200;
    fx.store.state.player.health = 40;
    const slot = fx.state.player.inventory.slots.findIndex((s) => s?.id === 'cheese-omelette');
    fx.dispatch('player:eat', { slot });
    expect(activeBuffs(fx.state)).toEqual([{ stat: 'farming', amount: 1, expiresAt: 1800 + 120 }]);

    fx.tickMinutes(110);
    expect(activeBuffs(fx.state)).toHaveLength(1);
    fx.tickMinutes(10);
    expect(activeBuffs(fx.state)).toHaveLength(0);
    expect(fx.state.player.energy).toBe(240);
  });

  it('foodFor resolves cookable items and ignores everything else', async () => {
    const fx = await makeFixture();
    expect(foodFor(fx.content, 'ember-bloom-tea')?.buffs).toEqual([{ stat: 'luck', amount: 1, hours: 3 }]);
    expect(foodFor(fx.content, 'rock')).toBeNull();
  });
});

describe('crafting persistence', () => {
  it('persists active buffs with the save', async () => {
    const fx = await makeFixture(true);
    levelUp(fx, 'farming', 4);
    fx.giveItem('milk', 1);
    fx.giveItem('cheese', 1);
    fx.dispatch('crafting:craft', { recipeId: 'cheese-omelette' });
    const slot = fx.state.player.inventory.slots.findIndex((s) => s?.id === 'cheese-omelette');
    fx.dispatch('player:eat', { slot });
    fx.dispatch('player:sleep', null);
    const saved = await fx.flushPersist();
    expect(saved).not.toBeNull();
    const buffs = (saved?.state.extensions['crafting'] as { buffs: unknown[] } | undefined)?.buffs;
    expect(buffs).toEqual([{ stat: 'farming', amount: 1, expiresAt: 1800 + 120 }]);
  });
});