/**
 * Day-rollover effects (contract m2-contracts.md sections 3 & 4): rain/storm
 * soil watering, storm crop loss, the daily `forage:roll`, and the combined
 * night pass shared by the `player:sleep` and `time:tick` reducers.
 *
 * Order inside one night (matches the contract: weather effects run in the
 * same time:tick pass BEFORE crop growth):
 *   1. roll the new day's weather (weather.ts),
 *   2. apply its effects (water everything when rain/storm; storm ~10% crop
 *      loss on the farm),
 *   3. run crop/soil growth + wither (growth.ts, season mismatch -> wither),
 *   4. refresh the farm's forage batch (clear old, spawn 3..7).
 *
 * applyFarmRollover is idempotent per world day (gated on
 * farming.lastRolloverDay), so both paths can invoke it without double-firing.
 * Events (crop:lost, crop:withered, weather:changed) are emitted here so the
 * sleep and tick paths emit them identically.
 */
import type { ContentDb } from '@game/core/content';
import type { EventBus } from '@game/core/events';
import type { Rng } from '@game/core/rng';
import type { GameState, MapState, PlacedObject, WorldPos } from '@game/core/types';
import { readFarmingExt } from './ext';
import { applyCropRollover, type CropDefs } from './growth';
import { applyWeatherRoll } from './weather';
import { cropIdOf, FORAGE_PREFIX, tileKey, type WitheredCrop } from './utils';

export interface LostCrop {
  x: number;
  y: number;
  cropId: string;
  cause: 'storm';
}

export interface FarmRolloverResult {
  state: GameState;
  rolled: boolean;
  withered: WitheredCrop[];
  lost: LostCrop[];
}

/** Contract §4: share of crops a storm destroys each morning. */
export const STORM_LOSS_CHANCE = 0.1;

/** Forage spawn count per morning: floor(3 + rng.next() * 5), capped by room. */
export function forageCountOf(rng: Rng): number {
  return Math.floor(3 + rng.next() * 5);
}

/** Item ids eligible as forage today: forage category, season tag matches or none. */
export function forageItemIds(content: ContentDb, seasonIndex: number): string[] {
  const out: string[] = [];
  for (const [id, item] of content.items) {
    if (item.category !== 'forage') continue;
    const hasSeasonTag = item.tags.some((tag) => tag.startsWith('season:'));
    if (!hasSeasonTag || item.tags.includes(`season:${seasonIndex}`)) out.push(id);
  }
  return out;
}

/**
 * rain/storm: water every tilled + crop on the farm. storm: each crop is
 * destroyed with STORM_LOSS_CHANCE. Pure (no bus); returns the lost list for
 * the caller to emit `crop:lost`.
 */
export function applyWeatherEffects(
  state: GameState,
  rng: Rng,
): { state: GameState; lost: LostCrop[] } {
  const weather = state.world.weather;
  if (weather !== 'rain' && weather !== 'storm') return { state, lost: [] };
  const mapId = state.farm.mapId;
  const farm = state.maps[mapId];
  if (!farm) return { state, lost: [] };

  const placed: Record<string, PlacedObject> = { ...farm.placed };
  let wateredDiff = false;
  for (const [key, obj] of Object.entries(placed)) {
    const isTilled = obj.id === 'tilled';
    const isCrop = cropIdOf(obj.id) !== null;
    if (!isTilled && !isCrop) continue;
    if (obj.data?.watered === true) continue;
    placed[key] = { ...obj, data: { ...(obj.data ?? {}), watered: true } };
    wateredDiff = true;
  }

  const lost: LostCrop[] = [];
  if (weather === 'storm') {
    for (const [key, obj] of Object.entries(placed)) {
      const cropId = cropIdOf(obj.id);
      if (cropId === null) continue;
      if (rng.fork('storm').next() < STORM_LOSS_CHANCE) {
        delete placed[key];
        lost.push({ x: obj.x, y: obj.y, cropId, cause: 'storm' });
      }
    }
  }

  if (!wateredDiff && lost.length === 0) return { state, lost };
  return { state: { ...state, maps: { ...state.maps, [mapId]: { ...farm, placed } } }, lost };
}

/** Empty, walkable + legend-tillable tiles of a map with no placed object. */
export function forageCandidates(map: MapState, content: ContentDb): WorldPos[] {
  const mapDef = content.maps.get(map.id);
  if (!mapDef) return [];
  const out: WorldPos[] = [];
  for (let y = 0; y < map.grid.height; y++) {
    for (let x = 0; x < map.grid.width; x++) {
      const code = map.grid.tiles[y * map.grid.width + x];
      if (code === undefined) continue;
      const legend = mapDef.legend[code];
      if (!legend || !legend.walkable || !legend.tillable) continue;
      if (map.placed[tileKey(x, y)]) continue;
      out.push({ mapId: map.id, x, y });
    }
  }
  return out;
}

function clearForage(maps: Record<string, MapState>): {
  maps: Record<string, MapState>;
  changed: boolean;
} {
  const next: Record<string, MapState> = {};
  let changed = false;
  for (const [mapId, map] of Object.entries(maps)) {
    let placed = map.placed;
    let clearedOnMap = false;
    for (const [key, obj] of Object.entries(placed)) {
      if (!obj.id.startsWith(FORAGE_PREFIX)) continue;
      if (!clearedOnMap) {
        placed = { ...placed };
        clearedOnMap = true;
      }
      delete placed[key];
      changed = true;
    }
    next[mapId] = clearedOnMap ? { ...map, placed } : map;
  }
  return { maps: next, changed };
}

/**
 * Contract §3 `forage:roll`: clear old `forage:*` objects from every map, then
 * spawn 3..7 fresh ones on empty legend-tillable grass of the farm map.
 */
export function applyForageRoll(state: GameState, rng: Rng, content: ContentDb): GameState {
  const cleared = clearForage(state.maps);
  const st = cleared.changed ? { ...state, maps: cleared.maps } : state;

  const seasonIndex = st.world.calendar.seasonIndex;
  const pool = forageItemIds(content, seasonIndex);
  if (pool.length === 0) return st;
  const farmMap = st.maps[st.farm.mapId];
  if (!farmMap) return st;
  const candidates = forageCandidates(farmMap, content);
  if (candidates.length === 0) return st;

  const f = rng.fork('forage');
  const count = Math.min(forageCountOf(f), candidates.length);
  const picks = f.shuffle([...candidates]).slice(0, count);
  const placed = { ...farmMap.placed };
  for (const pos of picks) {
    const itemId = f.pick(pool);
    placed[tileKey(pos.x, pos.y)] = { id: `${FORAGE_PREFIX}${itemId}`, x: pos.x, y: pos.y, data: {} };
  }
  return { ...st, maps: { ...st.maps, [farmMap.id]: { ...farmMap, placed } } };
}

/**
 * Run the whole night for a day that has just advanced: weather roll, its
 * effects, crop/soil growth, then forage. Emits crop:lost / crop:withered and
 * returns them. No-op when farming.lastRolloverDay is current.
 */
export function applyFarmRollover(
  state: GameState,
  cropDefs: CropDefs,
  rng: Rng,
  bus: EventBus,
  content: ContentDb,
): FarmRolloverResult {
  const ext = readFarmingExt(state);
  if (ext.lastRolloverDay === state.world.dayCount) {
    return { state, rolled: false, withered: [], lost: [] };
  }

  let st = state;
  st = applyWeatherRoll(st, rng, bus);
  const effects = applyWeatherEffects(st, rng);
  st = effects.state;
  const roll = applyCropRollover(st, cropDefs);
  st = roll.state;
  st = applyForageRoll(st, rng, content);

  for (const lost of effects.lost) bus.emit('crop:lost', lost);
  for (const withered of roll.withered) bus.emit('crop:withered', withered);
  return { state: st, rolled: true, withered: roll.withered, lost: effects.lost };
}
