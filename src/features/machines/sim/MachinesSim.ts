/**
 * machines:sim — craftable processing machines (WORKER-2 lane).
 *
 * A machine is placed as a `machine:<machineId>` placed object (from a
 * `machine`-category item with the same id, obtained via the crafting menu).
 * Place it on any free walkable tile, insert one input bundle, wait `hours`
 * of in-game time (6 × 10-minute ticks per hour), then collect the output.
 * The bag stays open while a product is ready: a collect to a full inventory
 * is refused and the machine keeps its product. Unplaced machines from older
 * saves are ignored; a machine persists the same way any placed object does.
 *
 * All machine state lives in the placed object's `data`:
 *   { machineId, loaded: 0|1, remainingTicks }
 *
 * Reducers: `machines:place`, `machines:insert`, `machines:collect`, plus a
 * `time:tick` pass that counts machines down (and emits `machines:finished`
 * the tick a product completes). Denials emit `machines:denied`.
 */
import { defineFeature, type FeatureContext, type FeatureModule } from '@game/core/feature';
import type { EventBus } from '@game/core/events';
import type { ContentDb } from '@game/core/content';
import type { GameState, MapState, PlacedObject, WorldPos } from '@game/core/types';
import { TICK_MINUTES } from '@game/core/types';
import { addStackToInventory } from '../../inventory/sim/InventorySim';
import { removeStackFromInventory } from '../../inventory/sim/InventorySim';

export const MACHINE_PREFIX = 'machine:';
const TICKS_PER_HOUR = 60 / TICK_MINUTES;

export function machineIdOf(objId: string): string | null {
  return objId.startsWith(MACHINE_PREFIX) ? objId.slice(MACHINE_PREFIX.length) : null;
}

/** The machine definition a placed object belongs to, or null. */
export function machineDefOf(content: ContentDb, obj: PlacedObject | undefined): { machineId: string; data: Record<string, unknown> } | null {
  if (!obj) return null;
  const id = machineIdOf(obj.id);
  if (!id) return null;
  return { machineId: id, data: obj.data ?? {} };
}

/** The machine placed at `tile`, or null when the tile holds no machine. */
export function machineAtTile(state: GameState, tile: WorldPos): { obj: PlacedObject; machineId: string } | null {
  const map = mapAt(state, tile);
  if (!map) return null;
  const obj = map.placed[`${tile.x},${tile.y}`];
  const id = machineIdOf(obj?.id ?? '');
  if (!id || !obj) return null;
  return { obj, machineId: id };
}

export function mapAt(state: GameState, tile: WorldPos): MapState | undefined {
  return state.maps[tile.mapId];
}

/** Tile walkable per the authored map legend, ignoring placed objects. */
export function isTileWalkable(content: ContentDb, tile: WorldPos): boolean {
  const map = content.maps.get(tile.mapId);
  if (!map) return false;
  const idx = tile.y * map.width + tile.x;
  const code = map.layers.ground.replace(/\s+/g, '')[idx];
  if (code === undefined) return false;
  return map.legend[code]?.walkable === true;
}

export interface MachineDeps {
  bus: EventBus;
  content: ContentDb;
}

export interface MachineResult {
  state: GameState;
  ok: boolean;
  reason?: string;
}

function denyState(state: GameState, deps: MachineDeps, reason: string, extra?: Record<string, unknown>): MachineResult {
  deps.bus.emit('machines:denied', { reason, ...extra });
  return { state, ok: false, reason };
}

/** Place `itemId` (a machine item) on a free walkable tile. */
export function placeMachine(state: GameState, tile: WorldPos, itemId: string, deps: MachineDeps): MachineResult {
  const def = deps.content.machines.get(itemId);
  if (!def) return denyState(state, deps, 'unknown-machine', { tile, itemId });
  const map = mapAt(state, tile);
  if (!map) return denyState(state, deps, 'no-map', { tile });
  const key = `${tile.x},${tile.y}`;
  if (map.placed[key]) return denyState(state, deps, 'occupied', { tile });
  if (!isTileWalkable(deps.content, tile)) return denyState(state, deps, 'blocked', { tile });
  const res = removeStackFromInventory(state, itemId, 1);
  if (res.removed < 1) return denyState(state, deps, 'no-item', { itemId });
  const placed: Record<string, PlacedObject> = { ...map.placed };
  placed[key] = { id: `${MACHINE_PREFIX}${itemId}`, x: tile.x, y: tile.y, data: { machineId: itemId, loaded: 0, remainingTicks: 0 } };
  deps.bus.emit('machines:placed', { tile, machineId: itemId });
  return { state: { ...res.state, maps: { ...state.maps, [tile.mapId]: { ...map, placed } } }, ok: true };
}

/** Load `slot`'s matching input bundle into a machine. */
export function insertMachine(state: GameState, tile: WorldPos, slot: number, deps: MachineDeps): MachineResult {
  const map = mapAt(state, tile);
  if (!map) return denyState(state, deps, 'no-map', { tile });
  const obj = map.placed[`${tile.x},${tile.y}`];
  const found = machineDefOf(deps.content, obj);
  if (!found || !obj) return denyState(state, deps, 'no-machine', { tile });
  const def = deps.content.machines.get(found.machineId);
  if (!def) return denyState(state, deps, 'no-machine', { tile });
  const stack = state.player.inventory.slots[slot];
  if (!stack) return denyState(state, deps, 'no-slot', { tile, slot });
  const ingredient = def.input.find((ing) => ing.itemId === stack.id);
  if (!ingredient) return denyState(state, deps, 'not-needed', { tile, machineId: found.machineId, itemId: stack.id });
  if (found.data.loaded === 1) return denyState(state, deps, 'busy', { tile, machineId: found.machineId });
  const res = removeStackFromInventory(state, ingredient.itemId, ingredient.qty);
  if (res.removed < ingredient.qty) return denyState(state, deps, 'no-ingredient', { itemId: ingredient.itemId });
  const placed: Record<string, PlacedObject> = { ...map.placed };
  placed[`${tile.x},${tile.y}`] = { ...obj, data: { machineId: found.machineId, loaded: 1, remainingTicks: def.hours * TICKS_PER_HOUR } };
  deps.bus.emit('machines:loaded', { tile, machineId: found.machineId, itemId: ingredient.itemId, qty: ingredient.qty });
  return { state: { ...res.state, maps: { ...state.maps, [tile.mapId]: { ...map, placed } } }, ok: true };
}

/** Collect the finished product of a machine into the bag. */
export function collectMachine(state: GameState, tile: WorldPos, deps: MachineDeps): MachineResult {
  const map = mapAt(state, tile);
  if (!map) return denyState(state, deps, 'no-map', { tile });
  const obj = map.placed[`${tile.x},${tile.y}`];
  const found = machineDefOf(deps.content, obj);
  if (!found || !obj) return denyState(state, deps, 'no-machine', { tile });
  const def = deps.content.machines.get(found.machineId);
  if (!def) return denyState(state, deps, 'no-machine', { tile });
  if (found.data.loaded !== 1) return denyState(state, deps, 'not-loaded', { tile });
  if ((found.data.remainingTicks as number) > 0) return denyState(state, deps, 'not-ready', { tile });
  let st = state;
  for (const out of def.output) {
    const added = addStackToInventory(st, { id: out.itemId, qty: out.qty, quality: 0 });
    if (!added.added) {
      deps.bus.emit('inventory:full', { tile, machineId: found.machineId, itemId: out.itemId });
      return denyState(state, deps, 'inventory-full', { tile, machineId: found.machineId, itemId: out.itemId });
    }
    st = added.state;
  }
  const placed: Record<string, PlacedObject> = { ...map.placed };
  placed[`${tile.x},${tile.y}`] = { ...obj, data: { machineId: found.machineId, loaded: 0, remainingTicks: 0 } };
  deps.bus.emit('machines:collected', { tile, machineId: found.machineId, items: def.output.map((o) => ({ itemId: o.itemId, qty: o.qty })) });
  return { state: { ...st, maps: { ...st.maps, [tile.mapId]: { ...map, placed } } }, ok: true };
}

/**
 * Context-aware interact (T-0405): a working machine stays busy, a finished
 * one is collected into the bag, and an idle one is loaded from the selected
 * hotbar slot (the normal-play path — walking up and pressing Space).
 */
export function interactMachine(state: GameState, tile: WorldPos, deps: MachineDeps): MachineResult {
  const at = machineAtTile(state, tile);
  if (!at) return denyState(state, deps, 'no-machine', { tile });
  const loaded = at.obj.data?.loaded;
  const remaining = (at.obj.data?.remainingTicks as number | undefined) ?? 0;
  if (loaded === 1) {
    if (remaining > 0) return denyState(state, deps, 'busy', { tile, machineId: at.machineId });
    return collectMachine(state, tile, deps);
  }
  return insertMachine(state, tile, state.player.inventory.selected, deps);
}

/** Advance every loaded machine by one 10-minute tick. */
export function tickMachines(state: GameState, content: ContentDb, bus: EventBus): GameState {
  let changed = false;
  const maps: Record<string, MapState> = { ...state.maps };
  for (const [mapId, map] of Object.entries(state.maps)) {
    const placed: Record<string, PlacedObject> = {};
    let mapChanged = false;
    for (const [key, obj] of Object.entries(map.placed)) {
      const id = machineIdOf(obj.id);
      if (!id) {
        placed[key] = obj;
        continue;
      }
      const remaining = (obj.data?.remainingTicks as number | undefined) ?? 0;
      if (remaining > 0) {
        const next = remaining - 1;
        placed[key] = { ...obj, data: { ...obj.data, remainingTicks: next } };
        mapChanged = true;
        if (next === 0) bus.emit('machines:finished', { mapId, tile: { mapId, x: obj.x, y: obj.y }, machineId: id });
      } else {
        placed[key] = obj;
      }
    }
    if (mapChanged) {
      maps[mapId] = { ...map, placed };
      changed = true;
    }
  }
  return changed ? { ...state, maps } : state;
}

export const machinesSim: FeatureModule = defineFeature({
  id: 'machines:sim',
  lane: 'sim',
  setup(ctx: FeatureContext) {
    const deps: MachineDeps = { bus: ctx.bus, content: ctx.content };

    ctx.store.registerReducer('machines:place', (st, action, _rng) => {
      const p = action.payload as { tile?: WorldPos; itemId?: unknown } | null;
      if (!p || typeof p.itemId !== 'string' || !p.tile) return st;
      return placeMachine(st, p.tile, p.itemId, deps).state;
    });
    ctx.store.registerReducer('machines:insert', (st, action, _rng) => {
      const p = action.payload as { tile?: WorldPos; slot?: number } | null;
      if (!p || !p.tile || typeof p.slot !== 'number') return st;
      return insertMachine(st, p.tile, p.slot, deps).state;
    });
    ctx.store.registerReducer('machines:collect', (st, action, _rng) => {
      const p = action.payload as { tile?: WorldPos } | null;
      if (!p || !p.tile) return st;
      return collectMachine(st, p.tile, deps).state;
    });
    ctx.store.registerReducer('machines:interact', (st, action, _rng) => {
      const p = action.payload as { tile?: WorldPos } | null;
      if (!p || !p.tile) return st;
      return interactMachine(st, p.tile, deps).state;
    });
    // T-0405: route the shared interact bus here when the front tile is a
    // machine (farming:sim defers on machine tiles, mirroring rod handling).
    // T-0502: the same bus carries placement. Without it `machines:place` had
    // no caller anywhere in the product, so a crafted machine could never be
    // set down and the whole machine loop was unreachable from a new game.
    // The bus is loosely typed, so nothing here may be assumed present.
    ctx.bus.on('tool:use-requested', (payload: { tile?: WorldPos; toolId?: string | null } | null) => {
      const tile = payload?.tile;
      if (!tile || typeof tile.mapId !== 'string') return;
      if (machineAtTile(ctx.store.state, tile)) {
        ctx.store.dispatch({ type: 'machines:interact', payload: { tile } });
        return;
      }
      const inv = ctx.store.state.player.inventory;
      const held = inv.slots[inv.selected];
      if (!held || !ctx.content.machines.has(held.id)) return;
      ctx.store.dispatch({ type: 'machines:place', payload: { tile, itemId: held.id } });
    });
    // Count machines down on the same tick the core clock advances.
    ctx.store.registerReducer('time:tick', (st, _action, _rng) => tickMachines(st, ctx.content, ctx.bus));
  },
});