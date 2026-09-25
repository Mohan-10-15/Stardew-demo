/**
 * Farming sim (WORKER-2 lane): tools, till/plant/water/harvest, energy costs,
 * and the crop/tilled day rollover.
 *
 * Integration contract: WORKER-1's `player:interact` reducer emits
 * `tool:use-requested { tile, toolId }` on the bus; this module subscribes and
 * resolves the outcome (farming:tool-use). Seeds are resolved as plant actions,
 * bare hands (any non-tool id) harvest mature crops. All randomness goes
 * through the store Rng passed to reducers.
 */
import type { EventBus } from '@game/core/events';
import type { ContentDb } from '@game/core/content';
import type { FeatureContext, FeatureModule } from '@game/core/feature';
import { defineFeature } from '@game/core/feature';
import type { Rng } from '@game/core/rng';
import type { CropDef } from '@game/core/schemas';
import type {
  GameState,
  ItemStack,
  PlacedObject,
  QualityTier,
  SimAction,
  WorldPos,
} from '@game/core/types';
import { addStackToInventory } from '../../inventory/sim/InventorySim';
import { ensureFarmingExt, ensureWeatherExt } from './ext';
import type { CropDefs } from './growth';
import { applyFarmRollover, applyForageRoll } from './rollover';
import { bumpStat, FORAGE_XP, HARVEST_XP } from './summary';
import { cropIdOf, FORAGE_PREFIX, tileKey } from './utils';

export type ToolKind = 'hoe' | 'watering' | 'axe' | 'pickaxe' | 'scythe' | 'hands';

/** Energy cost per successful-or-wasted swing (contract section 5). */
export const TOOL_COST: Record<Exclude<ToolKind, 'hands'>, number> = {
  hoe: 6,
  watering: 4,
  axe: 8,
  pickaxe: 8,
  scythe: 2,
};

const DEBRIS_DROP: Record<string, { id: string; qty: number }> = {
  weed: { id: 'fiber', qty: 1 },
  branch: { id: 'wood', qty: 1 },
  stump: { id: 'wood', qty: 2 },
  rock: { id: 'stone', qty: 1 },
};

export function toolKindOf(toolId: string): ToolKind {
  if (toolId.startsWith('hoe-')) return 'hoe';
  if (toolId.startsWith('watering-can-')) return 'watering';
  if (toolId.startsWith('axe-')) return 'axe';
  if (toolId.startsWith('pickaxe-')) return 'pickaxe';
  if (toolId.startsWith('scythe-')) return 'scythe';
  return 'hands';
}

/** Quality roll on harvest: ~94% normal / ~5% silver / ~1% gold (contract section 4). */
export function rollQuality(rng: Rng): QualityTier {
  const r = rng.fork('crop:quality').next();
  if (r < 0.94) return 0;
  if (r < 0.99) return 1;
  return 2;
}

export interface ToolUsePayload {
  tile: WorldPos;
  toolId?: string | null;
}

export interface ToolFailedEvent {
  tile: WorldPos;
  toolId: string | null;
  reason: string;
}

export interface ToolUsedEvent {
  tile: WorldPos;
  toolId: string;
  effect: 'tilled' | 'watered' | 'cleared' | 'planted' | 'harvested';
}

interface ToolResult {
  state: GameState;
  effect: 'tilled' | 'watered' | 'cleared' | 'planted' | 'harvested' | 'none';
  reason?: string;
}

export interface ToolRow {
  bus: EventBus;
  content: ContentDb;
}

function seedIdToCrop(seedId: string, content: ContentDb): CropDef | undefined {
  if (!seedId) return undefined;
  for (const crop of content.crops.values()) {
    if (crop.seedId === seedId) return crop;
  }
  return undefined;
}

function findSeedSlot(state: GameState, seedId: string): number {
  const inv = state.player.inventory;
  const selected = inv.slots[inv.selected];
  if (selected && selected.id === seedId && selected.qty > 0) return inv.selected;
  return inv.slots.findIndex((s) => s !== null && s.id === seedId && s.qty > 0);
}

function isMature(obj: { data?: Record<string, unknown> }, def: CropDef): boolean {
  const stage = typeof obj.data?.stage === 'number' ? obj.data.stage : 0;
  return stage >= def.days.length;
}

function mapWithPlaced(
  state: GameState,
  mapId: string,
  placed: Record<string, PlacedObject>,
): GameState {
  const map = state.maps[mapId];
  if (!map) return state;
  return { ...state, maps: { ...state.maps, [mapId]: { ...map, placed } } };
}

function applyPlant(state: GameState, tile: WorldPos, seedId: string, row: ToolRow): ToolResult {
  const crop = seedIdToCrop(seedId, row.content);
  if (!crop) return { state, effect: 'none', reason: 'no-crop' };
  const map = state.maps[tile.mapId];
  if (!map) return { state, effect: 'none', reason: 'no-map' };
  const key = tileKey(tile.x, tile.y);
  const soil = map.placed[key];
  if (!soil || soil.id !== 'tilled') return { state, effect: 'none', reason: 'not-tilled' };
  if (!crop.seasons.includes(state.world.calendar.seasonIndex)) {
    row.bus.emit('crop:plant-rejected', { tile, seedId, reason: 'wrong-season' });
    return { state, effect: 'none', reason: 'wrong-season' };
  }
  const seedSlot = findSeedSlot(state, seedId);
  if (seedSlot === -1) {
    row.bus.emit('inventory:full', { tile, itemId: seedId });
    return { state, effect: 'none', reason: 'no-seed' };
  }
  const inv = state.player.inventory;
  const slots = [...inv.slots];
  const stack = slots[seedSlot];
  slots[seedSlot] = stack && stack.qty > 1 ? { ...stack, qty: stack.qty - 1 } : null;
  const placed = {
    ...map.placed,
    [key]: {
      id: `crop:${crop.id}`,
      x: tile.x,
      y: tile.y,
      data: { stage: 0, watered: false, grownDays: 0, missedWater: 0 },
    },
  };
  const next = mapWithPlaced(
    { ...state, player: { ...state.player, inventory: { ...inv, slots } } },
    tile.mapId,
    placed,
  );
  row.bus.emit('crop:planted', { tile, cropId: crop.id, seedId });
  return { state: next, effect: 'planted' };
}

function harvestCrop(
  state: GameState,
  tile: WorldPos,
  obj: PlacedObject,
  cropId: string,
  def: CropDef,
  rng: Rng,
  row: ToolRow,
): ToolResult {
  const quality: QualityTier = rollQuality(rng);
  const stack: ItemStack = { id: cropId, qty: 1, quality };
  const added = addStackToInventory(state, stack);
  if (!added.added) {
    row.bus.emit('inventory:full', { tile, itemId: cropId });
    return { state, effect: 'none', reason: 'inventory-full' };
  }
  const map = added.state.maps[tile.mapId];
  if (!map) return { state, effect: 'none', reason: 'no-map' };
  const key = tileKey(tile.x, tile.y);
  const placed = { ...map.placed };
  if (def.regrow !== null && def.regrow !== undefined) {
    const reset = Math.max(0, def.days.length - def.regrow);
    placed[key] = {
      ...obj,
      data: { ...(obj.data ?? {}), stage: reset, grownDays: reset, watered: false, missedWater: 0 },
    };
  } else {
    placed[key] = { id: 'tilled', x: tile.x, y: tile.y, data: { watered: false } };
  }
  const next = mapWithPlaced(added.state, tile.mapId, placed);
  let st = bumpStat(next, `day:harvest:${cropId}`, 1);
  st = bumpStat(st, 'day:xp:farming', HARVEST_XP);
  row.bus.emit('crop:harvested', { tile, cropId, qty: 1, quality });
  return { state: st, effect: 'harvested' };
}

function applyHands(
  state: GameState,
  tile: WorldPos,
  toolId: string,
  rng: Rng,
  row: ToolRow,
): ToolResult {
  const obj = state.maps[tile.mapId]?.placed[tileKey(tile.x, tile.y)];
  const cropId = obj ? cropIdOf(obj.id) : null;
  if (cropId !== null && obj) {
    const def = row.content.crops.get(cropId);
    if (def && isMature(obj, def)) {
      return harvestCrop(state, tile, obj, cropId, def, rng, row);
    }
    return { state, effect: 'none', reason: 'not-mature' };
  }
  if (obj && obj.id.startsWith(FORAGE_PREFIX)) {
    return pickForage(state, tile, obj, row);
  }
  if (toolId && seedIdToCrop(toolId, row.content)) {
    return applyPlant(state, tile, toolId, row);
  }
  return { state, effect: 'none', reason: 'nothing' };
}

function clearDebris(
  state: GameState,
  tile: WorldPos,
  allowed: readonly string[],
  row: ToolRow,
): ToolResult {
  const map = state.maps[tile.mapId];
  if (!map) return { state, effect: 'none', reason: 'no-map' };
  const key = tileKey(tile.x, tile.y);
  const obj = map.placed[key];
  if (!obj || !allowed.includes(obj.id)) return { state, effect: 'none', reason: 'no-debris' };
  const drop = DEBRIS_DROP[obj.id];
  if (!drop) return { state, effect: 'none', reason: 'no-debris' };
  const added = addStackToInventory(state, { id: drop.id, qty: drop.qty, quality: 0 });
  if (!added.added) {
    row.bus.emit('inventory:full', { tile, itemId: drop.id });
    return { state, effect: 'none', reason: 'inventory-full' };
  }
const placed = { ...map.placed };
  delete placed[key];
  const next = mapWithPlaced(added.state, tile.mapId, placed);
  row.bus.emit('item:picked', { tile, itemId: drop.id, qty: drop.qty });
  return { state: next, effect: 'cleared' };
}

/** Pick up a `forage:<itemId>` placed object (bare hand or scythe), m2 §3. */
function pickForage(state: GameState, tile: WorldPos, obj: PlacedObject, row: ToolRow): ToolResult {
  const map = state.maps[tile.mapId];
  if (!map || map.placed[tileKey(tile.x, tile.y)] !== obj) return { state, effect: 'none', reason: 'no-forage' };
  const itemId = obj.id.slice(FORAGE_PREFIX.length);
  if (!itemId) return { state, effect: 'none', reason: 'no-forage' };
  const added = addStackToInventory(state, { id: itemId, qty: 1, quality: 0 });
  if (!added.added) {
    row.bus.emit('inventory:full', { tile, itemId });
    return { state, effect: 'none', reason: 'inventory-full' };
  }
  const placed = { ...map.placed };
  const key = tileKey(tile.x, tile.y);
  delete placed[key];
  let st = mapWithPlaced(added.state, tile.mapId, placed);
  st = bumpStat(st, `day:forage:${itemId}`, 1);
  st = bumpStat(st, 'day:xp:foraging', FORAGE_XP);
  row.bus.emit('item:picked', { tile, itemId, qty: 1 });
  return { state: st, effect: 'cleared' };
}

function applyToolEffect(
  state: GameState,
  kind: ToolKind,
  tile: WorldPos,
  row: ToolRow,
): ToolResult {
  if (kind === 'hands') return { state, effect: 'none', reason: 'nothing' };
  const map = state.maps[tile.mapId];
  if (!map) return { state, effect: 'none', reason: 'no-map' };
  const idx = tile.y * map.grid.width + tile.x;
  const code = map.grid.tiles[idx];
  if (code === undefined) return { state, effect: 'none', reason: 'no-map' };

  if (kind === 'hoe') {
    const legend = row.content.maps.get(tile.mapId)?.legend[code];
    if (!legend?.tillable) return { state, effect: 'none', reason: 'not-tillable' };
    const key = tileKey(tile.x, tile.y);
    if (map.placed[key]) return { state, effect: 'none', reason: 'occupied' };
    const placed = {
      ...map.placed,
      [key]: { id: 'tilled', x: tile.x, y: tile.y, data: { watered: false } },
    };
    return { state: mapWithPlaced(state, tile.mapId, placed), effect: 'tilled' };
  }

  if (kind === 'watering') {
    const key = tileKey(tile.x, tile.y);
    const obj = map.placed[key];
    if (!obj) return { state, effect: 'none', reason: 'no-soil' };
    const isTilled = obj.id === 'tilled';
    const isCrop = cropIdOf(obj.id) !== null;
    if (!isTilled && !isCrop) return { state, effect: 'none', reason: 'no-soil' };
    const placed = {
      ...map.placed,
      [key]: { ...obj, data: { ...(obj.data ?? {}), watered: true } },
    };
    row.bus.emit('tile:watered', { tile });
    return { state: mapWithPlaced(state, tile.mapId, placed), effect: 'watered' };
  }

  if (kind === 'axe') return clearDebris(state, tile, ['weed', 'branch', 'stump'], row);
  if (kind === 'pickaxe') return clearDebris(state, tile, ['rock'], row);
  if (kind === 'scythe') {
    const obj = map.placed[tileKey(tile.x, tile.y)];
    if (obj && obj.id.startsWith(FORAGE_PREFIX)) return pickForage(state, tile, obj, row);
    return clearDebris(state, tile, ['weed'], row);
  }
  return { state, effect: 'none', reason: 'no-effect' };
}

/** Resolve one tool/hands use requested by the input layer. */
export function applyToolUse(
  state: GameState,
  payload: ToolUsePayload,
  rng: Rng,
  row: ToolRow,
): GameState {
  const tile = payload.tile;
  const toolId = payload.toolId ?? '';
  const kind = toolKindOf(toolId);

  // Winter: the soil is frozen — tilling is rejected, state unchanged (m2 §4).
  if (kind === 'hoe' && state.world.calendar.seasonIndex === 3) {
    row.bus.emit('farming:blocked', { reason: 'frozen', tile });
    row.bus.emit<ToolFailedEvent>('tool:failed', { tile, toolId, reason: 'frozen' });
    return state;
  }

  if (kind === 'hands') {
    const { state: st, effect, reason } = applyHands(state, tile, toolId, rng, row);
    if (effect === 'none') {
      row.bus.emit<ToolFailedEvent>('tool:failed', { tile, toolId, reason: reason ?? 'nothing' });
    } else {
      row.bus.emit<ToolUsedEvent>('tool:used', { tile, toolId, effect });
    }
    return st;
  }

  const cost = TOOL_COST[kind];
  if (state.player.energy < cost) {
    row.bus.emit('player:exhausted', { tile, toolId, energy: state.player.energy });
    row.bus.emit<ToolFailedEvent>('tool:failed', { tile, toolId, reason: 'exhausted' });
    return state;
  }
  const energy = state.player.energy - cost;
  const drained = { ...state, player: { ...state.player, energy } };
  const { state: st, effect, reason } = applyToolEffect(drained, kind, tile, row);
  if (effect === 'none') {
    row.bus.emit<ToolFailedEvent>('tool:failed', { tile, toolId, reason: reason ?? 'no-effect' });
  } else {
    row.bus.emit<ToolUsedEvent>('tool:used', { tile, toolId, effect });
  }
  return st;
}

export const farmingSim: FeatureModule = defineFeature({
  id: 'farming:sim',
  lane: 'sim',
  setup(ctx: FeatureContext) {
    ctx.store.replaceState(ensureFarmingExt(ctx.store.state));
    ctx.store.replaceState(ensureWeatherExt(ctx.store.state));
    const row: ToolRow = { bus: ctx.bus, content: ctx.content };
    const cropDefs: CropDefs = (id) => ctx.content.crops.get(id);

    ctx.store.registerReducer('farming:tool-use', (st, action, rng) =>
      applyToolUse(st, action.payload as ToolUsePayload, rng, row),
    );
    ctx.store.registerReducer('farming:till', (st, action, rng) => {
      const payload = action.payload as { tile: WorldPos; toolId?: string | null };
      return applyToolUse(st, { tile: payload.tile, toolId: payload.toolId ?? 'hoe-t0' }, rng, row);
    });
    ctx.store.registerReducer('farming:plant', (st, action) => {
      const payload = action.payload as { tile: WorldPos; seedId: string };
      return applyPlant(st, payload.tile, payload.seedId, row).state;
    });
    ctx.store.registerReducer('time:tick', (st, _action: SimAction, rng) => {
      const roll = applyFarmRollover(st, cropDefs, rng, ctx.bus, ctx.content);
      return roll.state;
    });
    ctx.store.registerReducer('forage:roll', (st, _action: SimAction, rng) =>
      applyForageRoll(st, rng, ctx.content),
    );
    ctx.bus.on('tool:use-requested', (payload: ToolUsePayload) => {
      ctx.store.dispatch({ type: 'farming:tool-use', payload });
    });
  },
});
