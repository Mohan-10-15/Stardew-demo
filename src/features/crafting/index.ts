import { registerFeature } from '../../core/registry';
import { craftingSim } from './sim/CraftingSim';

registerFeature(craftingSim);

export {
  absoluteMinutes,
  activeBuffs,
  countOf,
  craftRecipe,
  craftingSim,
  CRAFTING_EXT_ID,
  eatItem,
  ensureCraftingExt,
  foodFor,
  pruneBuffs,
  readCraftingExt,
  recipeUnlocked,
  writeCraftingExt,
} from './sim/CraftingSim';
export type { ActiveBuff, CraftingExt, CraftResult, EatResult } from './sim/CraftingSim';