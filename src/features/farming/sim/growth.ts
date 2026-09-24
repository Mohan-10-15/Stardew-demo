/**
 * Crop + tilled-soil day rollover (contract m1-contracts.md section 4).
 *
 * Runs for EVERY map. Idempotent per world day: it only fires when
 * world.dayCount advanced past farming.lastRolloverDay, so it can be invoked
 * from both the core time:tick path and the player:sleep path safely.
 *
 * Rules:
 *  - tilled soil keeps its watered flag for the rest of the day, then resets.
 *  - a watered crop advances one growth stage (capped at maturity).
 *  - a growing crop missed 2 consecutive waterings withers (removed + event).
 *  - a crop whose season is no longer current withers.
 *  - mature crops wait quietly (they neither grow nor wither).
 */
import type { CropDef } from '@game/core/schemas';
import type { GameState, MapState, PlacedObject, SeasonIndex } from '@game/core/types';
import { readFarmingExt, writeFarmingExt } from './ext';
import { cropIdOf, type WitheredCrop } from './utils';

export type CropDefs = (cropId: string) => CropDef | undefined;

export interface CropRolloverResult {
  state: GameState;
  rolled: boolean;
  withered: WitheredCrop[];
}

interface MapRollover {
  map: MapState;
  changed: boolean;
}

function rolloverMap(
  map: MapState,
  seasonIndex: SeasonIndex,
  cropDefs: CropDefs,
  withered: WitheredCrop[],
): MapRollover {
  const placed: Record<string, PlacedObject> = {};
  let changed = false;

  for (const [key, obj] of Object.entries(map.placed)) {
    if (obj.id === 'tilled') {
      if (obj.data?.watered === true) {
        placed[key] = { ...obj, data: { ...obj.data, watered: false } };
        changed = true;
      } else {
        placed[key] = obj;
      }
      continue;
    }

    const cropId = cropIdOf(obj.id);
    if (cropId === null) {
      placed[key] = obj;
      continue;
    }

    const data = obj.data ?? {};
    const stage = typeof data.stage === 'number' ? data.stage : 0;
    const def = cropDefs(cropId);
    if (!def || !def.seasons.includes(seasonIndex)) {
      withered.push({ mapId: map.id, x: obj.x, y: obj.y, cropId, cause: 'season' });
      changed = true;
      continue;
    }

    if (stage >= def.days.length) {
      if (data.watered === true) {
        placed[key] = { ...obj, data: { ...data, watered: false } };
        changed = true;
      } else {
        placed[key] = obj;
      }
      continue;
    }

    if (data.watered === true) {
      const nextStage = Math.min(stage + 1, def.days.length);
      placed[key] = {
        ...obj,
        data: { ...data, stage: nextStage, grownDays: nextStage, watered: false, missedWater: 0 },
      };
      changed = true;
      continue;
    }

    const missedWater = (typeof data.missedWater === 'number' ? data.missedWater : 0) + 1;
    if (missedWater >= 2) {
      withered.push({ mapId: map.id, x: obj.x, y: obj.y, cropId, cause: 'thirst' });
      changed = true;
      continue;
    }
    placed[key] = { ...obj, data: { ...data, watered: false, missedWater } };
    changed = true;
  }

  if (!changed) return { map, changed: false };
  return { map: { ...map, placed }, changed: true };
}

export function applyCropRollover(state: GameState, cropDefs: CropDefs): CropRolloverResult {
  const ext = readFarmingExt(state);
  if (ext.lastRolloverDay === state.world.dayCount) {
    return { state, rolled: false, withered: [] };
  }

  const withered: WitheredCrop[] = [];
  const seasonIndex = state.world.calendar.seasonIndex;
  let maps = state.maps;
  let mapsChanged = false;
  for (const [mapId, map] of Object.entries(maps)) {
    const next = rolloverMap(map, seasonIndex, cropDefs, withered);
    if (next.changed) {
      maps = { ...maps, [mapId]: next.map };
      mapsChanged = true;
    }
  }

  const nextState = writeFarmingExt(mapsChanged ? { ...state, maps } : state, {
    ...ext,
    lastRolloverDay: state.world.dayCount,
  });
  return { state: nextState, rolled: true, withered };
}
