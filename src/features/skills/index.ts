import { registerFeature } from '../../core/registry';
import { skillsSim } from './sim/SkillsSim';

registerFeature(skillsSim);

export {
  applySkillXp,
  chooseProfession,
  ensureSkillsExt,
  grantSkillXp,
  hasProfession,
  MAX_SKILL_LEVEL,
  professionsAvailable,
  readSkillsExt,
  recipesUnlockedFor,
  skillLevelOf,
  skillsSim,
  SKILL_EXT_ID,
  SKILL_KEYS,
  skillXpOf,
  writeSkillsExt,
  xpNeededFor,
} from './sim/SkillsSim';
export type { SkillKey, SkillLevel, SkillsExt } from './sim/SkillsSim';