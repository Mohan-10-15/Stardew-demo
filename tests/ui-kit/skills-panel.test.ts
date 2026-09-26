/**
 * skills panel (T-0405, WORKER-2 lane) — the journal's Skills tab view-model.
 * Pure `buildSkillRows` backed by a live sim fixture: default five-skill rows,
 * XP bookkeeping against the linear curve, profession picks, and the recipes
 * each level has unlocked. Headless — no DOM involved.
 */
import { describe, expect, it } from 'vitest';
import { skillsSim } from '@game/features/skills';
import { buildSkillRows } from '@game/features/people/ui/skills-panel';
import { createSim, DEFAULT_MODULES } from '../../tests/sim/harness';

async function makeFixture() {
  return createSim({ modules: [...DEFAULT_MODULES, skillsSim] });
}

describe('skills-panel rows', () => {
  it('lists all five skills at level 0 with no profession or recipes', async () => {
    const fx = await makeFixture();
    const rows = buildSkillRows(fx.state, fx.content);
    expect(rows.map((r) => r.skillId)).toEqual(['farming', 'foraging', 'fishing', 'mining', 'combat']);
    for (const row of rows) {
      expect(row.label.length).toBeGreaterThan(0);
      expect(row.level).toBe(0);
      expect(row.xp).toBe(0);
      expect(row.xpMax).toBe(100);
      expect(row.professionId).toBeNull();
      expect(row.professionName).toBeNull();
      expect(row.recipeIds).toEqual([]);
    }
  });

  it('tracks xp toward the next level against the linear curve', async () => {
    const fx = await makeFixture();
    fx.dispatch('skills:grant-xp', { skill: 'farming', amount: 250 });
    const row = buildSkillRows(fx.state, fx.content)[0]!;
    expect(row.skillId).toBe('farming');
    expect(row.level).toBe(1);
    expect(row.xp).toBe(150);
    expect(row.xpMax).toBe(200);
  });

  it('shows the picked profession and recipes unlocked at level 5', async () => {
    const fx = await makeFixture();
    fx.dispatch('skills:grant-xp', { skill: 'farming', amount: 1500 });
    fx.dispatch('skills:choose-profession', { skill: 'farming', professionId: 'tiller' });
    const row = buildSkillRows(fx.state, fx.content)[0]!;
    expect(row.level).toBe(5);
    expect(row.xpMax).toBe(600);
    expect(row.professionId).toBe('tiller');
    expect(row.professionName).toBe('Tiller');
    expect(row.professionDescription).toContain('sell for 10% more');
    expect(row.recipeIds).toEqual(['cheese-omelette', 'cheese-press', 'seed-maker']);
  });

  it('caps xpMax at zero for a maxed skill', async () => {
    const fx = await makeFixture();
    fx.dispatch('skills:grant-xp', { skill: 'mining', amount: 100 * 11 * 5 });
    const row = buildSkillRows(fx.state, fx.content).find((r) => r.skillId === 'mining')!;
    expect(row.level).toBe(10);
    expect(row.xp).toBe(0);
    expect(row.xpMax).toBe(0);
  });

  it('leaves untouched skills as fresh rows', async () => {
    const fx = await makeFixture();
    fx.dispatch('skills:grant-xp', { skill: 'farming', amount: 250 });
    const rows = buildSkillRows(fx.state, fx.content);
    expect(rows[1]!.skillId).toBe('foraging');
    expect(rows[1]!.level).toBe(0);
    expect(rows[1]!.recipeIds).toEqual([]);
  });
});