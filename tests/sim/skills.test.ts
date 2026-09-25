/**
 * T-0401 — skills:sim. Levels 0..10 with a linear XP curve, one-time
 * professions, data-driven recipe unlocks, and automatic harvest of the daily
 * `day:xp:*` counters through `day:summary`.
 */
import { describe, expect, it } from 'vitest';
import { createSim } from './harness';
import { skillsSim } from '@game/features/skills';
import {
  ensureSkillsExt,
  grantSkillXp,
  MAX_SKILL_LEVEL,
  readSkillsExt,
  recipesUnlockedFor,
  skillLevelOf,
  skillXpOf,
  SKILL_KEYS,
  xpNeededFor,
} from '@game/features/skills';
import type { ContentDb } from '@game/core/content';

interface LevelUp {
  skill: string;
  level: number;
}

function fakeContent(): ContentDb {
  const recipes = new Map<string, unknown>();
  recipes.set('basic-fertilizer', {
    id: 'basic-fertilizer',
    name: 'Basic Fertilizer',
    kind: 'crafting',
    output: { itemId: 'basic-fertilizer-item', qty: 1 },
    ingredients: [{ itemId: 'fiber', qty: 2 }],
    unlock: { skill: 'farming', level: 1 },
  });
  recipes.set('perfect-crop-jam', {
    id: 'perfect-crop-jam',
    name: 'Perfect Crop Jam',
    kind: 'crafting',
    output: { itemId: 'crop-jam', qty: 1 },
    ingredients: [{ itemId: 'parsnip', qty: 2 }],
    unlock: { skill: 'farming', level: 2 },
  });
  return {
    items: new Map(),
    crops: new Map(),
    npcs: new Map(),
    maps: new Map(),
    shops: new Map(),
    schedules: new Map(),
    dialogue: new Map(),
    quests: new Map(),
    skills: new Map(),
    fish: new Map(),
    animals: new Map(),
    machines: new Map(),
    recipes: recipes as unknown as ContentDb['recipes'],
    byId: () => undefined,
  };
}

describe('skills:sim extension state', () => {
  it('seeds all five skills at level 0 with no XP', async () => {
    const sim = await createSim({ modules: [skillsSim] });
    const ext = readSkillsExt(sim.state);
    for (const key of SKILL_KEYS) {
      expect(ext.levels[key]).toEqual({ level: 0, xp: 0 });
    }
    expect(ext.professions.farming).toBeUndefined();
  });

  it('repairs a malformed extension onto defaults', async () => {
    const sim = await createSim({ modules: [skillsSim] });
    sim.state.extensions['skills'] = { levels: { farming: { level: 3, xp: 5 } } };
    const repaired = ensureSkillsExt(sim.state);
    const ext = readSkillsExt(repaired);
    expect(ext.levels.farming).toEqual({ level: 3, xp: 5 });
    expect(ext.levels.fishing).toEqual({ level: 0, xp: 0 });
  });
});

describe('skills:sim XP leveling', () => {
  it('uses a linear 100*(level+1) curve up to a hard cap of 10', () => {
    expect(xpNeededFor(0)).toBe(100);
    expect(xpNeededFor(4)).toBe(500);
    expect(MAX_SKILL_LEVEL).toBe(10);
  });

  it('ignores unknown skills, non-numbers, and non-positive amounts', async () => {
    const sim = await createSim({ modules: [skillsSim] });
    const before = readSkillsExt(sim.state);

    sim.dispatch('skills:grant-xp', { skill: 'alchemy', amount: 999 });
    sim.dispatch('skills:grant-xp', { skill: 'farming', amount: -10 });
    sim.dispatch('skills:grant-xp', { skill: 'farming', amount: 'lots' });

    expect(readSkillsExt(sim.state)).toEqual(before);
  });

  it('banks XP below a threshold without leveling', async () => {
    const sim = await createSim({ modules: [skillsSim] });
    sim.dispatch('skills:grant-xp', { skill: 'farming', amount: 99 });
    expect(skillLevelOf(sim.state, 'farming')).toBe(0);
    expect(skillXpOf(sim.state, 'farming')).toBe(99);
  });

  it('levels up at 100 XP and emits player:levelup', async () => {
    const sim = await createSim({ modules: [skillsSim] });
    const levels = sim.capture<LevelUp>('player:levelup');

    sim.dispatch('skills:grant-xp', { skill: 'farming', amount: 250 });

    expect(skillLevelOf(sim.state, 'farming')).toBe(1);
    expect(skillXpOf(sim.state, 'farming')).toBe(150);
    expect(levels).toEqual([{ skill: 'farming', level: 1 }]);
  });

  it('chains multiple level-ups from a big grant', async () => {
    const sim = await createSim({ modules: [skillsSim] });
    const levels = sim.capture<LevelUp>('player:levelup');

    sim.dispatch('skills:grant-xp', { skill: 'mining', amount: 750 });

    expect(skillLevelOf(sim.state, 'mining')).toBe(3);
    expect(skillXpOf(sim.state, 'mining')).toBe(150);
    expect(levels).toEqual([
      { skill: 'mining', level: 1 },
      { skill: 'mining', level: 2 },
      { skill: 'mining', level: 3 },
    ]);
  });

  it('caps at level 10 and drops overflow', async () => {
    const sim = await createSim({ modules: [skillsSim] });
    sim.dispatch('skills:grant-xp', { skill: 'combat', amount: 10000 });

    expect(skillLevelOf(sim.state, 'combat')).toBe(10);
    expect(skillXpOf(sim.state, 'combat')).toBe(0);

    sim.dispatch('skills:grant-xp', { skill: 'combat', amount: 1 });
    expect(skillLevelOf(sim.state, 'combat')).toBe(10);
    expect(skillXpOf(sim.state, 'combat')).toBe(0);
  });

  it('harvests the day:xp counters fed by day:summary', async () => {
    const sim = await createSim({ modules: [skillsSim] });
    const levels = sim.capture<LevelUp>('player:levelup');

    sim.bus.emit('day:summary', {
      dayCount: 2,
      xpEarned: [
        { skill: 'farming', amount: 3 },
        { skill: 'foraging', amount: 105 },
        { skill: 'unknown', amount: 999 },
      ],
    });

    expect(skillLevelOf(sim.state, 'foraging')).toBe(1);
    expect(skillXpOf(sim.state, 'foraging')).toBe(5);
    expect(skillLevelOf(sim.state, 'farming')).toBe(0);
    expect(levels).toEqual([{ skill: 'foraging', level: 1 }]);
  });
});

describe('skills:sim recipe unlocks', () => {
  it('derives unlocked recipes from level + skill against content', () => {
    const content = fakeContent();
    expect(recipesUnlockedFor('farming', 0, content)).toEqual([]);
    expect(recipesUnlockedFor('farming', 1, content)).toEqual(['basic-fertilizer']);
    expect(recipesUnlockedFor('farming', 2, content)).toEqual(['basic-fertilizer', 'perfect-crop-jam']);
    expect(recipesUnlockedFor('fishing', 2, content)).toEqual([]);
  });

  it('emits skills:recipes-unlocked for recipes that just became visible', () => {
    const content = fakeContent();
    const seen: unknown[] = [];
    const emit = (type: string, payload: unknown): void => {
      if (type === 'skills:recipes-unlocked') seen.push(payload);
    };
    const state = ensureSkillsExt({ extensions: {} } as unknown as Parameters<typeof grantSkillXp>[0]);

    grantSkillXp(state, 'farming', 350, { content, emit });

    expect(seen).toEqual([{ skill: 'farming', recipes: ['basic-fertilizer', 'perfect-crop-jam'] }]);
  });
});

describe('skills:sim professions', () => {
  async function leveledSim(skill: 'farming', amount: number): Promise<Awaited<ReturnType<typeof createSim>>> {
    const sim = await createSim({ modules: [skillsSim] });
    sim.dispatch('skills:grant-xp', { skill, amount });
    return sim;
  }

  it('rejects picking a profession below its required level', async () => {
    const sim = await createSim({ modules: [skillsSim] });
    const profs = sim.capture<{ skill: string; profession: string }>('player:profession');

    sim.dispatch('skills:choose-profession', { skill: 'farming', professionId: 'tiller' });

    expect(readSkillsExt(sim.state).professions.farming).toBeUndefined();
    expect(profs).toHaveLength(0);
  });

  it('accepts one profession per skill at its authored level, once', async () => {
    const sim = await leveledSim('farming', 1600); // level 5+, well past the 100/200/... threshold chain
    const profs = sim.capture<{ skill: string; profession: string }>('player:profession');

    sim.dispatch('skills:choose-profession', { skill: 'farming', professionId: 'tiller' });
    expect(skillLevelOf(sim.state, 'farming')).toBeGreaterThanOrEqual(5);

    expect(readSkillsExt(sim.state).professions.farming).toBe('tiller');
    expect(profs).toEqual([{ skill: 'farming', profession: 'tiller' }]);

    // Second pick (even a valid level-10 one) is locked after the first.
    sim.dispatch('skills:choose-profession', { skill: 'farming', professionId: 'rancher' });
    expect(readSkillsExt(sim.state).professions.farming).toBe('tiller');
    expect(profs).toHaveLength(1);
  });

  it('ignores unknown professions', async () => {
    const sim = await leveledSim('farming', 1000);
    sim.dispatch('skills:grant-xp', { skill: 'farming', amount: 1000 });
    sim.dispatch('skills:choose-profession', { skill: 'farming', professionId: 'sheep-wrangler' });
    expect(readSkillsExt(sim.state).professions.farming).toBeUndefined();
  });
});