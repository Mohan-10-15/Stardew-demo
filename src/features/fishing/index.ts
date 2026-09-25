import { registerFeature } from '../../core/registry';
import { fishingSim } from './sim/FishingSim';

registerFeature(fishingSim);

export {
  absoluteMinutes,
  availableFish,
  castFishing,
  ensureFishingExt,
  FISHING_EXT_ID,
  isRod,
  pickFish,
  readFishingExt,
  reelFishing,
  rollCatchQuality,
  tickFishing,
  writeFishingExt,
} from './sim/FishingSim';
export type { FishingExt, FishingPhase, FishingSession } from './sim/FishingSim';