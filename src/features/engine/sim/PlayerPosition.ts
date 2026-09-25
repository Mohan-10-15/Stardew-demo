/**
 * engine:sim — player position + collision (WORKER-1, lane 'sim').
 *
 * Small, pure, deterministic reducers that own where the player stands.
 * Collision follows m1-contracts §2: a tile is walkable iff the legend
 * entry says walkable AND no blocking placed object sits on it. Fabric
 * harmony: 'tilled' and 'crop:*' never block. Unknown tile codes (state
 * placeholder grids) default to walkable so the engine stays playable
 * before content grids are seeded; water/trees from a validated legend
 * still block exactly as authored.
 */
import { defineFeature, type FeatureContext } from '../../../core/feature';
import type { Store } from '../../../core/store';
import type { EventBus } from '../../../core/events';
import type { ContentDb } from '../../../core/content';
import type { GameState, Facing, MapState, SimAction, TilePos, WorldPos } from '../../../core/types';
import type { MapDef, MapLegend } from '../../../core/schemas';

export const WALK_ENERGY_COST = 0.02;

/** Default jog speed (tiles per second) when no modifier key is held. */
export const JOG_UNITS_PER_SEC = 4;
/** Shift-to-walk multiplier applied to the jog speed. */
export const WALK_SPEED_MULT = 0.6;

export interface MovePayload {
  dx: number;
  dy: number;
}

/** Continuous per-frame movement payload (ADDENDUM B). Coordinates and
 *  distances are in tile units; `speed` is units per second and `dt` the
 *  elapsed seconds since the last dispatch. Dir may combine axes for 8-way. */
export interface WalkPayload {
  dx: number;
  dy: number;
  dt: number;
  speed: number;
}

export interface PlayerMovedEvent {
  from: TilePos;
  to: TilePos;
  mapId: string;
}

export interface PlayerWarpedEvent {
  from: string;
  to: string;
}

export interface ToolUseRequest {
  tile: TilePos;
  toolId: string;
}

export interface EngineSimDeps {
  store: Store;
  bus: EventBus;
  content: ContentDb;
}

export function tileAt(map: MapState, x: number, y: number): string | undefined {
  if (x < 0 || y < 0 || x >= map.grid.width || y >= map.grid.height) return undefined;
  return map.grid.tiles[y * map.grid.width + x];
}

export function placedAt(map: MapState, x: number, y: number): MapState['placed'][string] | undefined {
  return map.placed[`${x},${y}`];
}

export function isWalkable(map: MapState, legend: MapLegend, x: number, y: number): boolean {
  const code = tileAt(map, x, y);
  if (code === undefined) return false;
  const entry = legend[code];
  if (entry !== undefined && entry.walkable !== true) return false;
  const object = placedAt(map, x, y);
  if (object !== undefined && object.id !== 'tilled' && !object.id.startsWith('crop:')) return false;
  return true;
}

export function facingFromDelta(dx: number, dy: number): Facing {
  if (dy < 0) return 'up';
  if (dy > 0) return 'down';
  if (dx > 0) return 'right';
  return 'left';
}

export function tileInFront(pos: WorldPos, facing: Facing): TilePos {
  const x = Math.floor(pos.x);
  const y = Math.floor(pos.y);
  switch (facing) {
    case 'up':
      return { x, y: y - 1 };
    case 'down':
      return { x, y: y + 1 };
    case 'left':
      return { x: x - 1, y };
    case 'right':
      return { x: x + 1, y };
  }
}

/** Pure warp lookup: returns the destination when (x, y) is a warp tile, else null. */
export function resolveWarp(mapDef: MapDef, x: number, y: number): { map: string; x: number; y: number } | null {
  for (const warp of mapDef.warps) {
    if (warp.x === x && warp.y === y) return { map: warp.to.map, x: warp.to.x, y: warp.to.y };
  }
  return null;
}

export function playerMoveReducer(state: GameState, action: SimAction<string, unknown>, content: ContentDb): GameState {
  const payload = action.payload;
  if (typeof payload !== 'object' || payload === null) return state;
  const { dx, dy } = payload as MovePayload;
  if (!Number.isInteger(dx) || !Number.isInteger(dy)) return state;
  if (dx !== 0 && dy !== 0) return state;
  if (dx < -1 || dx > 1 || dy < -1 || dy > 1) return state;
  if (dx === 0 && dy === 0) return state;

  const position = state.player.position;
  const map = state.maps[position.mapId];
  if (!map) return state;
  const mapDef = content.maps.get(position.mapId);
  if (!mapDef) return state;

  const facing = facingFromDelta(dx, dy);
  const targetX = position.x + dx;
  const targetY = position.y + dy;

  if (!isWalkable(map, mapDef.legend, targetX, targetY)) {
    return { ...state, player: { ...state.player, facing } };
  }

  const energy = Math.max(0, state.player.energy - WALK_ENERGY_COST);
  const warpTarget = resolveWarp(mapDef, targetX, targetY);
  if (warpTarget) {
    if (!state.maps[warpTarget.map]) {
      return { ...state, player: { ...state.player, facing } };
    }
    return {
      ...state,
      player: {
        ...state.player,
        facing,
        energy,
        position: { mapId: warpTarget.map, x: warpTarget.x, y: warpTarget.y },
      },
    };
  }
  return {
    ...state,
    player: {
      ...state.player,
      facing,
      energy,
      position: { ...position, x: targetX, y: targetY },
    },
  };
}

export function playerWalkReducer(state: GameState, action: SimAction<string, unknown>, content: ContentDb): GameState {
  const payload = action.payload;
  if (typeof payload !== 'object' || payload === null) return state;
  const { dx, dy, dt, speed } = payload as WalkPayload;
  if (typeof dt !== 'number' || !Number.isFinite(dt) || dt <= 0) return state;
  if (typeof speed !== 'number' || !Number.isFinite(speed) || speed <= 0) return state;
  if (dx === 0 && dy === 0) return state;

  const position = state.player.position;
  const map = state.maps[position.mapId];
  if (!map) return state;
  const mapDef = content.maps.get(position.mapId);
  if (!mapDef) return state;

  const facing = facingFromDelta(dx, dy);
  const length = Math.hypot(dx, dy);
  const ux = dx / length;
  const uy = dy / length;
  const dist = speed * dt;

  // Axis-separated movement with continuous collision sampling: each axis is
  // stepped in sub-tile increments so a big dt can never tunnel a one-tile
  // wall, and the check uses the destination tile of the moving axis only (the
  // other axis keeps its current floor) so walls stop just the axis they block
  // and the player slides cleanly along them.
  const MAX_STEP = 0.25;
  type WarpTarget = { map: string; x: number; y: number };

  const stepAxis = (
    value: number,
    delta: number,
    check: (after: number) => { cx: number; cy: number },
  ): { value: number; warp: WarpTarget | null } => {
    if (delta === 0) return { value, warp: null };
    let cursor = value;
    let remaining = Math.abs(delta);
    const sign = Math.sign(delta);
    while (remaining > 0) {
      const step = Math.min(remaining, MAX_STEP);
      const after = cursor + sign * step;
      const tile = check(after);
      if (!isWalkable(map, mapDef.legend, tile.cx, tile.cy)) break;
      const hit = resolveWarp(mapDef, tile.cx, tile.cy);
      if (hit && state.maps[hit.map]) return { value: after, warp: hit };
      cursor = after;
      remaining -= step;
    }
    return { value: cursor, warp: null };
  };

  const xDelta = ux * dist;
  let x = position.x;
  let y = position.y;
  const yDelta = uy * dist;
  const xAxis = stepAxis(x, xDelta, (after) => ({ cx: Math.floor(after), cy: Math.floor(y) }));
  const yAxis = xAxis.warp
    ? null
    : stepAxis(y, yDelta, (after) => ({ cx: Math.floor(x), cy: Math.floor(after) }));

  x = xAxis.value;
  y = xAxis.warp ? y : yAxis!.value;
  const warpTarget = xAxis.warp ?? yAxis?.warp ?? null;

  const moved = Math.hypot(x - position.x, y - position.y);
  const energy = Math.max(0, state.player.energy - WALK_ENERGY_COST * moved);

  if (warpTarget) {
    return {
      ...state,
      player: { ...state.player, facing, energy, position: { mapId: warpTarget.map, x: warpTarget.x, y: warpTarget.y } },
    };
  }
  return {
    ...state,
    player: { ...state.player, facing, energy, position: { mapId: position.mapId, x, y } },
  };
}

export function registerEngineSim({ store, bus, content }: EngineSimDeps): void {
  store.registerReducer('player:move', (state: GameState, action: SimAction<string, unknown>, _rng: unknown): GameState => {
    const from = state.player.position;
    const next = playerMoveReducer(state, action, content);
    const to = next.player.position;
    if (to.mapId !== from.mapId) {
      bus.emit<PlayerWarpedEvent>('player:warped', { from: from.mapId, to: to.mapId });
    } else if (to.x !== from.x || to.y !== from.y) {
      bus.emit<PlayerMovedEvent>('player:moved', { from: { x: from.x, y: from.y }, to: { x: to.x, y: to.y }, mapId: to.mapId });
    }
    return next;
  });

  store.registerReducer('player:walk', (state: GameState, action: SimAction<string, unknown>, _rng: unknown): GameState => {
    const from = state.player.position;
    const next = playerWalkReducer(state, action, content);
    const to = next.player.position;
    if (to.mapId !== from.mapId) {
      bus.emit<PlayerWarpedEvent>('player:warped', { from: from.mapId, to: to.mapId });
    } else {
      const fromTile = { x: Math.floor(from.x), y: Math.floor(from.y) };
      const toTile = { x: Math.floor(to.x), y: Math.floor(to.y) };
      if (toTile.x !== fromTile.x || toTile.y !== fromTile.y) {
        bus.emit<PlayerMovedEvent>('player:moved', { from: fromTile, to: toTile, mapId: to.mapId });
      }
    }
    return next;
  });

  store.registerReducer('player:interact', (state: GameState, _action: SimAction<string, unknown>, _rng: unknown): GameState => {
    const player = state.player;
    const tile = tileInFront(player.position, player.facing);
    const stack = player.inventory.slots[player.inventory.selected];
    const toolId = stack ? stack.id : 'hand';
    bus.emit<ToolUseRequest>('tool:use-requested', { tile, toolId });
    return state;
  });
}

export const engineSim = defineFeature({
  id: 'engine:sim',
  lane: 'sim',
  setup(ctx: FeatureContext): void {
    registerEngineSim({ store: ctx.store, bus: ctx.bus, content: ctx.content });
  },
});