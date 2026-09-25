/**
 * skills:sim — five life skills (farming, foraging, fishing, mining, combat),
 * leveled 0..10 with XP. (WORKER-2 lane.)
 *
 * XP accumulates through the daily `day:xp:<skill>` counters that FarmingSim
 * already bumps (crop harvest, forage). At each day close the `day:summary`
 * payload feeds `skills:grant-xp`, so levels climb in normal play with zero
 * new XP plumbing. Level-ups emit `player:levelup`; recipes whose
 * `unlock.level` was just reached emit `skills:recipes-unlocked`. Professions
 * (content skills.json) are a one-time pick offered at the authored levels.
 *
 * Contracts:
 *   extensions.skills = { levels: { <skill>: { level, xp } }, professions: { <skill>: id } }
 *   `skills:grant-xp`        { skill, amount }
 *   `skills:choose-profession` { skill, professionId }
 */
import { defineFeature, type FeatureContext, type FeatureModule } from '@game/core/feature';
import type { GameState, SimAction } from '@game/core/types';
import type { ContentDb } from '@game/core/content';
import type { Rng } from '@game/core/rng';
import type { SkillDef } from '@game/core/schemas';

export const SKILL_EXT_ID = 'skills';

export const SKILL_KEYS = ['farming', 'foraging', 'fishing', 'mining', 'combat'] as const;
export type SkillKey = (typeof SKILL_KEYS)[number];

/** Max level per skill; professions unlock at 5 and 10 (content-authorable). */
export const MAX_SKILL_LEVEL = 10;

/** XP required to advance FROM `level`. Linear curve: 100, 200, 300, ... */
export function xpNeededFor(level: number): number {
  return 100 * (level + 1);
}

export interface SkillLevel {
  level: number;
  xp: number;
}

export interface SkillsExt {
  levels: Record<SkillKey, SkillLevel>;
  professions: Partial<Record<SkillKey, string>>;
}

export function defaultSkillLevels(): Record<SkillKey, SkillLevel> {
  const levels = {} as Record<SkillKey, SkillLevel>;
  for (const key of SKILL_KEYS) levels[key] = { level: 0, xp: 0 };
  return levels;
}

/** Best-effort read of the extension, always returning all five skills. */
export function readSkillsExt(state: GameState): SkillsExt {
  const raw: Record<string, unknown> | undefined = state.extensions[SKILL_EXT_ID];
  const levels = defaultSkillLevels();
  const professions: Partial<Record<SkillKey, string>> = {};
  if (raw && typeof raw === 'object') {
    const rawLevels = raw.levels as Record<string, unknown> | undefined;
    if (rawLevels && typeof rawLevels === 'object') {
      for (const key of SKILL_KEYS) {
        const entry = rawLevels[key] as Partial<SkillLevel> | undefined;
        if (entry && typeof entry.level === 'number' && typeof entry.xp === 'number') {
          levels[key] = { level: entry.level, xp: entry.xp };
        }
      }
    }
    const rawProf = raw.professions as Record<string, unknown> | undefined;
    if (rawProf && typeof rawProf === 'object') {
      for (const key of SKILL_KEYS) {
        const pick = rawProf[key];
        if (typeof pick === 'string') professions[key] = pick;
      }
    }
  }
  return { levels, professions };
}

export function writeSkillsExt(state: GameState, next: SkillsExt): GameState {
  return {
    ...state,
    extensions: { ...state.extensions, [SKILL_EXT_ID]: { ...next } },
  };
}

export function ensureSkillsExt(state: GameState): GameState {
  const existing = readSkillsExt(state);
  const raw: Record<string, unknown> | undefined = state.extensions[SKILL_EXT_ID];
  const alreadyWellFormed =
    raw &&
    typeof raw.levels === 'object' &&
    SKILL_KEYS.every((k) => {
      const e = (raw.levels as Record<string, unknown>)[k] as Partial<SkillLevel> | undefined;
      return e !== undefined && typeof e.level === 'number' && typeof e.xp === 'number';
    });
  if (alreadyWellFormed) return state;
  return writeSkillsExt(state, existing);
}

export function skillLevelOf(state: GameState, skill: SkillKey): number {
  return readSkillsExt(state).levels[skill].level;
}

export function skillXpOf(state: GameState, skill: SkillKey): number {
  return readSkillsExt(state).levels[skill].xp;
}

/** Recipes currently unlocked for `skill` (data-driven, used by crafting UI). */
export function recipesUnlockedFor(
  skill: SkillKey,
  level: number,
  content: ContentDb,
): string[] {
  const out: string[] = [];
  for (const [id, recipe] of content.recipes) {
    if (!recipe.unlock) continue;
    if (recipe.unlock.skill === skill && recipe.unlock.level <= level) out.push(id);
  }
  return out.sort();
}

/** The profession definitions offered to `skill` at or below `level`. */
export function professionsAvailable(skill: SkillKey, level: number, content: ContentDb): SkillDef['professions'] {
  const def = content.skills.get(skill);
  if (!def) return [];
  return def.professions.filter((p) => p.level <= level);
}

export function hasProfession(state: GameState, skill: SkillKey): boolean {
  return readSkillsExt(state).professions[skill] !== undefined;
}

export interface SkillLeveledUpEvent {
  skill: SkillKey;
  level: number;
}

export interface SkillRecipesUnlockedEvent {
  skill: SkillKey;
  recipes: string[];
}

export interface SkillProfessionEvent {
  skill: SkillKey;
  profession: string;
}

export interface SkillDeps {
  content: ContentDb;
  emit: (type: string, payload: unknown) => void;
}

/** Pure XP application: returns the mutated extension plus any crossed levels. */
export function applySkillXp(ext: SkillsExt, skill: SkillKey, amount: number): {
  ext: SkillsExt;
  leveledThrough: number[];
} {
  if (!SKILL_KEYS.includes(skill)) return { ext, leveledThrough: [] };
  if (!Number.isFinite(amount) || amount <= 0) return { ext, leveledThrough: [] };
  const entry = ext.levels[skill];
  let level = entry.level;
  let xp = entry.xp + amount;
  const leveledThrough: number[] = [];
  while (level < MAX_SKILL_LEVEL && xp >= xpNeededFor(level)) {
    xp -= xpNeededFor(level);
    level += 1;
    leveledThrough.push(level);
  }
  if (level >= MAX_SKILL_LEVEL) xp = 0;
  if (level === entry.level && xp === entry.xp) return { ext, leveledThrough: [] };
  return {
    ext: { ...ext, levels: { ...ext.levels, [skill]: { level, xp } } },
    leveledThrough,
  };
}

export function grantSkillXp(state: GameState, skill: SkillKey, amount: number, deps: SkillDeps): GameState {
  if (!SKILL_KEYS.includes(skill) || !Number.isFinite(amount) || amount <= 0) return state;
  const ext = readSkillsExt(state);
  const { ext: nextExt, leveledThrough } = applySkillXp(ext, skill, amount);
  const before = ext.levels[skill];
  const after = nextExt.levels[skill];
  if (before.level === after.level && before.xp === after.xp) return state;
  for (const level of leveledThrough) {
    deps.emit('player:levelup', { skill, level });
  }
  if (leveledThrough.length > 0) {
    const lastLevel = leveledThrough[leveledThrough.length - 1]!;
    const fromLevel = lastLevel - leveledThrough.length;
    const availableNow = new Set(recipesUnlockedFor(skill, lastLevel, deps.content));
    const availableBefore = new Set(recipesUnlockedFor(skill, fromLevel, deps.content));
    const fresh = [...availableNow].filter((id) => !availableBefore.has(id)).sort();
    if (fresh.length > 0) {
      deps.emit('skills:recipes-unlocked', { skill, recipes: fresh });
    }
  }
  return writeSkillsExt(state, nextExt);
}

export function chooseProfession(
  state: GameState,
  skill: SkillKey,
  professionId: string,
  deps: SkillDeps,
): GameState {
  const ext = readSkillsExt(state);
  if (ext.professions[skill] !== undefined) return state;
  const level = ext.levels[skill].level;
  const def = deps.content.skills.get(skill);
  const pick = def?.professions.find((p) => p.id === professionId && p.level <= level);
  if (!pick) return state;
  deps.emit('player:profession', { skill, profession: pick.id });
  return writeSkillsExt(state, {
    ...ext,
    professions: { ...ext.professions, [skill]: pick.id },
  });
}

export const skillsSim: FeatureModule = defineFeature({
  id: 'skills:sim',
  lane: 'sim',
  setup(ctx: FeatureContext) {
    ctx.store.replaceState(ensureSkillsExt(ctx.store.state));
    const deps: SkillDeps = {
      content: ctx.content,
      emit: (type, payload) => ctx.bus.emit(type, payload),
    };
    ctx.store.registerReducer('skills:grant-xp', (st: GameState, action: SimAction<string, unknown>, _rng: Rng) => {
      const payload = action.payload as { skill?: unknown; amount?: unknown };
      if (typeof payload.skill !== 'string') return st;
      if (typeof payload.amount !== 'number') return st;
      return grantSkillXp(st, payload.skill as SkillKey, payload.amount, deps);
    });
    ctx.store.registerReducer('skills:choose-profession', (st: GameState, action: SimAction<string, unknown>, _rng: Rng) => {
      const payload = action.payload as { skill?: unknown; professionId?: unknown };
      if (typeof payload.skill !== 'string' || typeof payload.professionId !== 'string') return st;
      return chooseProfession(st, payload.skill as SkillKey, payload.professionId, deps);
    });
    // Farm the accumulated day:xp:* counters into skill XP each day close.
    ctx.bus.on('day:summary', (payload: { xpEarned?: Array<{ skill: string; amount: number }> }) => {
      for (const row of payload.xpEarned ?? []) {
        if (!SKILL_KEYS.includes(row.skill as SkillKey)) continue;
        if (row.amount <= 0) continue;
        ctx.store.dispatch({ type: 'skills:grant-xp', payload: { skill: row.skill, amount: row.amount } });
      }
    });
  },
});