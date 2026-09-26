/**
 * Skills panel (WORKER-2 lane, T-0405): pure view-model builder backing the
 * journal's Skills tab. Reads the skills extension (levels + xp + profession
 * picks) and answers each skill's current profession and the recipes its
 * level has unlocked — all headless-safe so the panel logic is unit-tested
 * against a sim fixture without a DOM.
 */
import type { ContentDb } from '@game/core/content';
import type { GameState } from '@game/core/types';
import {
  MAX_SKILL_LEVEL,
  readSkillsExt,
  recipesUnlockedFor,
  SKILL_KEYS,
  xpNeededFor,
  type SkillKey,
} from '../../skills/sim/SkillsSim';

export interface SkillPanelRow {
  skillId: SkillKey;
  label: string;
  level: number;
  xp: number;
  xpMax: number;
  professionId: string | null;
  professionName: string | null;
  professionDescription: string | null;
  /** Recipe ids currently unlocked for this skill (data order, sorted). */
  recipeIds: string[];
}

export function skillLabelOf(skillId: SkillKey, content: ContentDb): string {
  return content.skills.get(skillId)?.name || skillId;
}

/** View rows for every skill, in canonical order (farming → combat). */
export function buildSkillRows(state: GameState, content: ContentDb): SkillPanelRow[] {
  const ext = readSkillsExt(state);
  return SKILL_KEYS.map((skillId) => {
    const entry = ext.levels[skillId];
    const def = content.skills.get(skillId);
    const pick = ext.professions[skillId] ?? null;
    const profession = pick ? def?.professions.find((p) => p.id === pick) ?? null : null;
    return {
      skillId,
      label: skillLabelOf(skillId, content),
      level: entry.level,
      xp: entry.xp,
      xpMax: entry.level >= MAX_SKILL_LEVEL ? 0 : xpNeededFor(entry.level),
      professionId: pick,
      professionName: profession?.name ?? null,
      professionDescription: profession?.description ?? null,
      recipeIds: recipesUnlockedFor(skillId, entry.level, content),
    };
  });
}