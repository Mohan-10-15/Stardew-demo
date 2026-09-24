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
import type { MapLegend } from '../../../core/schemas';

export const WALK_ENERGY_COST = 0.02;

export interface MovePayload {
  dx: number;
  dy: number;
}

export interface PlayerMovedEvent {
  from: TilePos;
  to: TilePos;
  mapId: string;
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
  switch (facing) {
    case 'up':
      return { x: pos.x, y: pos.y - 1 };
    case 'down':
      return { x: pos.x, y: pos.y + 1 };
    case 'left':
      return { x: pos.x - 1, y: pos.y };
    case 'right':
      return { x: pos.x + 1, y: pos.y };
  }
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

export function registerEngineSim({ store, bus, content }: EngineSimDeps): void {
  store.registerReducer('player:move', (state: GameState, action: SimAction<string, unknown>, _rng: unknown): GameState => {
    const from = state.player.position;
    const next = playerMoveReducer(state, action, content);
    const to = next.player.position;
    if (to.x !== from.x || to.y !== from.y || to.mapId !== from.mapId) {
      bus.emit<PlayerMovedEvent>('player:moved', { from: { x: from.x, y: from.y }, to: { x: to.x, y: to.y }, mapId: to.mapId });
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