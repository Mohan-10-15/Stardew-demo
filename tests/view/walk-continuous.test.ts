/**
 * ADDENDUM B (B) — continuous 8-way movement. `player:walk` advances a
 * fractional position each frame at a given units/sec, samples walkability on
 * the destination tile per axis (walls stop only the axis they block), drains
 * energy proportional to distance, and warps the instant a crossing tile is a
 * warp. `player:move` (tile step) is untouched below and stays the bot/test
 * stepping contract.
 */
import { describe, expect, it } from 'vitest';
import { Store } from '@game/core/store';
import { Rng } from '@game/core/rng';
import { EventBus } from '@game/core/events';
import { createInitialState } from '@game/core/state';
import { loadContent } from '@game/core/content';
import { createGameRuntime } from '@game/core/game';
import {
  registerEngineSim,
  JOG_UNITS_PER_SEC,
  WALK_SPEED_MULT,
  WALK_ENERGY_COST,
} from '@game/features/engine/sim/PlayerPosition';
import type { GameState, MapState } from '@game/core/types';

const OPEN = [
  'gggggggggg',
  'gggggggggg',
  'gggggggggg',
  'gggggggggg',
  'gggggggggg',
  'gggggggggg',
];

/** Row 3 is a solid water wall so slide behavior is unambiguous. */
const WALL = [
  'gggggggggg',
  'gggggggggg',
  'gggggggggg',
  'wwwwwwwwww',
  'gggggggggg',
  'gggggggggg',
];

function mapFromRows(rows: string[]): MapState {
  const tiles: string[] = [];
  for (const row of rows) tiles.push(...row.split(''));
  return {
    id: 'farm',
    grid: { tiles, width: rows[0]!.length, height: rows.length },
    placed: {},
    npcs: {},
    version: 1,
  };
}

async function makeFixture(rows = OPEN, x = 2, y = 3): Promise<{ store: Store; bus: EventBus }> {
  const content = await loadContent();
  const state: GameState = createInitialState(7, 'walk-continuous');
  state.maps = { farm: mapFromRows(rows) };
  state.player.position = { mapId: 'farm', x, y };
  state.player.energy = 100;
  const bus = new EventBus();
  const store = new Store(state, new Rng(11), bus);
  registerEngineSim({ store, bus, content });
  return { store, bus };
}

describe('engine:sim player:walk (continuous)', () => {
  it('moves a fractional distance of speed*dt in one dispatch', async () => {
    const { store } = await makeFixture();

    store.dispatch({ type: 'player:walk', payload: { dx: 1, dy: 0, dt: 1, speed: JOG_UNITS_PER_SEC } });

    expect(store.state.player.position.x).toBeCloseTo(6, 5);
    expect(store.state.player.position.y).toBe(3);
    expect(store.state.player.facing).toBe('right');
    expect(store.state.player.energy).toBeCloseTo(100 - WALK_ENERGY_COST * JOG_UNITS_PER_SEC, 5);
  });

  it('walks ~60% as far when Shift is held (walk vs jog)', async () => {
    const { store } = await makeFixture();
    const walkSpeed = JOG_UNITS_PER_SEC * WALK_SPEED_MULT;

    store.dispatch({ type: 'player:walk', payload: { dx: 1, dy: 0, dt: 1, speed: walkSpeed } });

    expect(store.state.player.position.x).toBeCloseTo(2 + walkSpeed, 4);
  });

  it('moves diagonally at the full single-axis speed on BOTH axes (per-axis, not normalised)', async () => {
    // A wide/tall open field: at dt=1 a full 4-tile step on each axis must not
    // run off the map, or the edge would masquerade as a collision.
    const field = Array.from({ length: 12 }, () => 'g'.repeat(12));
    const { store } = await makeFixture(field, 6, 6);

    store.dispatch({ type: 'player:walk', payload: { dx: 1, dy: -1, dt: 1, speed: JOG_UNITS_PER_SEC } });

    // Each axis gets the whole speed*dt: only the path length is sqrt(2) longer.
    expect(store.state.player.position.x).toBeCloseTo(6 + JOG_UNITS_PER_SEC, 5);
    expect(store.state.player.position.y).toBeCloseTo(6 - JOG_UNITS_PER_SEC, 5);
    expect(store.state.player.facing).toBe('up');
  });

  it('stops flush at a wall without draining energy', async () => {
    const { store } = await makeFixture(WALL, 4, 4);

    store.dispatch({ type: 'player:walk', payload: { dx: 0, dy: -1, dt: 1, speed: JOG_UNITS_PER_SEC } });

    expect(store.state.player.position.y).toBe(4);
    expect(store.state.player.position.x).toBe(4);
    expect(store.state.player.energy).toBe(100);
    expect(store.state.player.facing).toBe('up');
  });

  it('slides along the wall: blocked axis stops, the other keeps moving', async () => {
    const { store } = await makeFixture(WALL, 4, 4);

    store.dispatch({ type: 'player:walk', payload: { dx: 1, dy: -1, dt: 1, speed: JOG_UNITS_PER_SEC } });

    // The wall is on the row above, so only y is blocked; x slides at full speed.
    expect(store.state.player.position.x).toBeCloseTo(4 + JOG_UNITS_PER_SEC, 5);
    expect(store.state.player.position.y).toBe(4);
    expect(store.state.player.energy).toBeCloseTo(100 - WALK_ENERGY_COST * JOG_UNITS_PER_SEC, 5);
  });

  it('warps when a walk crosses into the farm east road warp', async () => {
    const content = await loadContent();
    (globalThis as unknown as { __EH_CONTENT?: unknown }).__EH_CONTENT = content;
    const runtime = createGameRuntime({ newGame: true, seed: 23, mountDom: false });
    const farmDef = content.maps.get('farm')!;
    const warp = farmDef.warps.find((w) => w.to.map === 'village')!;

    runtime.store.state.player.position = { mapId: 'farm', x: warp.x - 1, y: warp.y };
    const warped: unknown[] = [];
    runtime.bus.on('player:warped', (e: unknown) => warped.push(e));

    runtime.store.dispatch({ type: 'player:walk', payload: { dx: 1, dy: 0, dt: 1, speed: JOG_UNITS_PER_SEC } });

    expect(runtime.store.state.player.position).toEqual({
      mapId: 'village',
      x: warp.to.x,
      y: warp.to.y,
    });
    expect(warped).toEqual([{ from: 'farm', to: 'village' }]);
  });

  it('emits player:moved per crossed tile for footstep cadence', async () => {
    const { store } = await makeFixture(OPEN, 2, 3);
    const moved: unknown[] = [];
    store.bus.on('player:moved', (e: unknown) => moved.push(e));

    store.dispatch({ type: 'player:walk', payload: { dx: 1, dy: 0, dt: 1, speed: JOG_UNITS_PER_SEC } });

    expect(moved).toHaveLength(1);
    expect(moved[0]).toEqual({ from: { x: 2, y: 3 }, to: { x: 6, y: 3 }, mapId: 'farm' });
  });
});