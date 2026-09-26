/**
 * T-0107 WORKER-1: engine sim reducers (walk/collision). Pure Node tests.
 * Instantiates a Store directly and registers only the engine reducers.
 * T-0201 adds warp resolution (resolveWarp) + a walk-across-the-warp test.
 */
import { describe, expect, it } from 'vitest';
import { Store } from '@game/core/store';
import { Rng } from '@game/core/rng';
import { EventBus } from '@game/core/events';
import { createInitialState, buildInitialMaps } from '@game/core/state';
import { loadContent } from '@game/core/content';
import { createGameRuntime } from '@game/core/game';
import { registerEngineSim, resolveWarp, WALK_ENERGY_COST } from '@game/features/engine/sim/PlayerPosition';
import type { GameState, MapState } from '@game/core/types';

const GROUND = [
  'gggggggg',
  'gggggggg',
  'gggwwggg',
  'gggggggg',
  'ggsssggg',
  'gggggggg',
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

async function makeFixture(): Promise<{ store: Store; bus: EventBus }> {
  const content = await loadContent();
  const state: GameState = createInitialState(7, 'walk');
  const map = mapFromRows(GROUND);
  map.placed['5,3'] = { id: 'rock', x: 5, y: 3 };
  state.maps = { farm: map };
  state.player.position = { mapId: 'farm', x: 3, y: 3 };
  state.player.energy = 10;
  const bus = new EventBus();
  const store = new Store(state, new Rng(11), bus);
  registerEngineSim({ store, bus, content });
  return { store, bus };
}

describe('engine:sim player:move', () => {
  it('allows walking onto grass and drains energy, updating facing', async () => {
    const { store } = await makeFixture();
    const moved: unknown[] = [];
    store.bus.on('player:moved', (e: unknown) => moved.push(e));

    store.dispatch({ type: 'player:move', payload: { dx: 1, dy: 0 } });

    expect(store.state.player.position).toEqual({ mapId: 'farm', x: 4, y: 3 });
    expect(store.state.player.facing).toBe('right');
    expect(store.state.player.energy).toBeCloseTo(10 - WALK_ENERGY_COST, 5);
    expect(moved).toHaveLength(1);
    expect(moved[0]).toEqual({ from: { x: 3, y: 3 }, to: { x: 4, y: 3 }, mapId: 'farm' });
  });

  it('blocks walking onto water but still turns to face it', async () => {
    const { store } = await makeFixture();
    const moved: unknown[] = [];
    store.bus.on('player:moved', (e: unknown) => moved.push(e));

    store.dispatch({ type: 'player:move', payload: { dx: 0, dy: -1 } });

    expect(store.state.player.position).toEqual({ mapId: 'farm', x: 3, y: 3 });
    expect(store.state.player.facing).toBe('up');
    expect(store.state.player.energy).toBe(10);
    expect(moved).toHaveLength(0);
  });

  it('blocks walking onto debris (placed rock)', async () => {
    const { store } = await makeFixture();
    store.dispatch({ type: 'player:move', payload: { dx: 1, dy: 0 } });
    const energyAfterFirst = store.state.player.energy;

    store.dispatch({ type: 'player:move', payload: { dx: 1, dy: 0 } });

    expect(store.state.player.position).toEqual({ mapId: 'farm', x: 4, y: 3 });
    expect(store.state.player.facing).toBe('right');
    expect(store.state.player.energy).toBe(energyAfterFirst);
  });

  it('allows walking onto tilled soil and planted crops (non-blocking ids)', async () => {
    const { store } = await makeFixture();
    const map = store.state.maps.farm!;
    map.placed['5,5'] = { id: 'tilled', x: 5, y: 5, data: { watered: true } };
    map.placed['4,5'] = { id: 'crop:parsnip', x: 4, y: 5, data: { stage: 1 } };
    store.state.player.position = { mapId: 'farm', x: 4, y: 4 };

    store.dispatch({ type: 'player:move', payload: { dx: 0, dy: 1 } });
    expect(store.state.player.position).toEqual({ mapId: 'farm', x: 4, y: 5 });
    expect(store.state.player.facing).toBe('down');

    store.dispatch({ type: 'player:move', payload: { dx: 1, dy: 0 } });
    expect(store.state.player.position).toEqual({ mapId: 'farm', x: 5, y: 5 });
  });

  it('rejects diagonal moves entirely', async () => {
    const { store } = await makeFixture();
    const before = JSON.stringify(store.state.player.position);

    store.dispatch({ type: 'player:move', payload: { dx: 1, dy: 1 } });

    expect(JSON.stringify(store.state.player.position)).toBe(before);
    expect(store.state.player.facing).toBe('down');
    expect(store.state.player.energy).toBe(10);
  });

  it('clamps energy at zero while moves still resolve', async () => {
    const { store } = await makeFixture();
    store.state.player.energy = 0.005;
    store.dispatch({ type: 'player:move', payload: { dx: 0, dy: 1 } });
    expect(store.state.player.position).toEqual({ mapId: 'farm', x: 3, y: 4 });
    expect(store.state.player.energy).toBe(0);
  });

  it('treats unknown tile codes (placeholder grids) as walkable', async () => {
    const content = await loadContent();
    const state = createInitialState(3, 'walk-fallback');
    const map = mapFromRows(['ggqg', 'gggg']);
    state.maps = { farm: map };
    state.player.position = { mapId: 'farm', x: 1, y: 0 };
    const store = new Store(state, new Rng(3));
    registerEngineSim({ store, bus: store.bus, content });

    store.dispatch({ type: 'player:move', payload: { dx: 1, dy: 0 } });

    expect(store.state.player.position).toEqual({ mapId: 'farm', x: 2, y: 0 });
  });
});

describe('resolveWarp (pure, real content)', () => {
  it('resolves the farm east-road warp into the village and the village west warp back', async () => {
    const content = await loadContent();
    const farmDef = content.maps.get('farm')!;
    const villageDef = content.maps.get('village')!;

    const farmWarp = farmDef.warps.find((w) => w.to.map === 'village');
    expect(farmWarp).toBeDefined();
    expect(farmWarp!.x).toBe(farmDef.width - 1); // east road edge

    expect(resolveWarp(farmDef, farmWarp!.x, farmWarp!.y)).toEqual({
      map: 'village',
      x: farmWarp!.to.x,
      y: farmWarp!.to.y,
    });
    expect(resolveWarp(farmDef, farmWarp!.x - 1, farmWarp!.y)).toBeNull();

    const villageWarp = villageDef.warps.find((w) => w.to.map === 'farm');
    expect(villageWarp).toBeDefined();
    expect(villageWarp!.x).toBe(0); // west road edge

    expect(resolveWarp(villageDef, villageWarp!.x, villageWarp!.y)).toEqual({
      map: 'farm',
      x: villageWarp!.to.x,
      y: villageWarp!.to.y,
    });
    expect(resolveWarp(villageDef, villageWarp!.x, villageWarp!.y + 1)).toBeNull();
  });
});

describe('engine:sim warp stepping (T-0201)', () => {
  it('walks east onto the farm warp, warps into the village, and returns via the village warp', async () => {
    const content = await loadContent();
    (globalThis as unknown as { __EH_CONTENT?: unknown }).__EH_CONTENT = content;
    const runtime = createGameRuntime({ newGame: true, seed: 23, mountDom: false });
    const farmDef = content.maps.get('farm')!;
    const warp = farmDef.warps.find((w) => w.to.map === 'village')!;

    expect(runtime.store.state.maps[farmDef.id]).toBeDefined();
    expect(runtime.store.state.maps[warp.to.map]).toBeDefined();

    runtime.store.state.player.position = { mapId: 'farm', x: warp.x - 1, y: warp.y };
    const energyBefore = runtime.store.state.player.energy;
    const warped: unknown[] = [];
    runtime.bus.on('player:warped', (e: unknown) => warped.push(e));
    const moved: unknown[] = [];
    runtime.bus.on('player:moved', (e: unknown) => moved.push(e));

    runtime.store.dispatch({ type: 'player:move', payload: { dx: 1, dy: 0 } });

    expect(runtime.store.state.player.position).toEqual({ mapId: 'village', x: warp.to.x, y: warp.to.y });
    expect(runtime.store.state.player.energy).toBeLessThan(energyBefore);
    expect(warped).toEqual([{ from: 'farm', to: 'village' }]);
    expect(moved).toHaveLength(0);

    const villageDef = content.maps.get('village')!;
    const returnWarp = villageDef.warps.find((w) => w.to.map === 'farm')!;
    runtime.store.state.player.position = { mapId: 'village', x: warp.to.x, y: warp.to.y };
    runtime.store.dispatch({ type: 'player:move', payload: { dx: -1, dy: 0 } });

    expect(runtime.store.state.player.position).toEqual({
      mapId: 'farm',
      x: returnWarp.to.x,
      y: returnWarp.to.y,
    });
    expect(warped).toEqual([
      { from: 'farm', to: 'village' },
      { from: 'village', to: 'farm' },
    ]);
  });

  it('keeps a no-op (facing only) when the warp destination map is absent from state.maps', async () => {
    const content = await loadContent();
    const farmDef = content.maps.get('farm')!;
    const warp = farmDef.warps.find((w) => w.to.map === 'village')!;

    const state = createInitialState(9, 'warp-fallback');
    state.maps = buildInitialMaps(new Map([[farmDef.id, farmDef]])); // village omitted
    state.player.position = { mapId: 'farm', x: warp.x - 1, y: warp.y };
    const energyBefore = state.player.energy;
    const store = new Store(state, new Rng(9));
    registerEngineSim({ store, bus: store.bus, content });
    const warped: unknown[] = [];
    store.bus.on('player:warped', (e: unknown) => warped.push(e));

    store.dispatch({ type: 'player:move', payload: { dx: 1, dy: 0 } });

    expect(store.state.player.position).toEqual({ mapId: 'farm', x: warp.x - 1, y: warp.y });
    expect(store.state.player.facing).toBe('right');
    expect(store.state.player.energy).toBe(energyBefore);
    expect(warped).toHaveLength(0);
  });
});

describe('engine:sim player:interact', () => {
  it('emits tool:use-requested for the tile ahead using the selected slot', async () => {
    const { store } = await makeFixture();
    const seen: unknown[] = [];
    store.bus.on('tool:use-requested', (e: unknown) => seen.push(e));

    store.dispatch({ type: 'player:interact', payload: {} });

    expect(seen).toEqual([{ tile: { mapId: 'farm', x: 3, y: 4 }, toolId: 'hoe-t0' }]);
  });

  it('emits hand when the selected slot is empty', async () => {
    const { store } = await makeFixture();
    store.state.player.inventory.selected = 8;
    const seen: unknown[] = [];
    store.bus.on('tool:use-requested', (e: unknown) => seen.push(e));

    store.dispatch({ type: 'player:interact', payload: {} });

    expect(seen).toEqual([{ tile: { mapId: 'farm', x: 3, y: 4 }, toolId: 'hand' }]);
  });
});