/**
 * Regression: the REAL interact path, end to end.
 *
 * This test exists because of a bug that every other test missed. Pressing
 * Space in the actual game dispatches `player:interact`, which emits
 * `tool:use-requested` with a tile. farming:sim and machines:sim both resolve
 * the map via `state.maps[tile.mapId]`. The event used to carry a bare
 * `{x, y}`, so `tile.mapId` was undefined and EVERY tool swing in the running
 * game failed with reason 'no-map' - while 300+ unit tests stayed green
 * because they dispatched `farming:tool-use` directly with a hand-built
 * WorldPos and never went near the input layer.
 *
 * So: stand the player on a real tile, face a real direction, dispatch
 * `player:interact`, and assert the world changed. No shortcuts.
 */
import { describe, expect, it } from 'vitest';
import { Store } from '@game/core/store';
import { Rng } from '@game/core/rng';
import { EventBus } from '@game/core/events';
import { createInitialState } from '@game/core/state';
import { loadContent } from '@game/core/content';
import { registerEngineSim } from '@game/features/engine/sim/PlayerPosition';
import { farmingSim, type ToolFailedEvent, type ToolUsedEvent } from '@game/features/farming/sim/FarmingSim';
import type { FeatureContext } from '@game/core/feature';
import type { GameState, MapState } from '@game/core/types';

const ROWS = [
  'gggggggg',
  'gggggggg',
  'gggggggg',
  'gggggggg',
  'gggggggg',
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

interface Fx {
  store: Store;
  bus: EventBus;
  used: ToolUsedEvent[];
  failed: ToolFailedEvent[];
}

/** Wire engine:sim and farming:sim exactly like the real runtime does. */
async function makeFx(setup?: (state: GameState, map: MapState) => void): Promise<Fx> {
  const content = await loadContent();
  const state = createInitialState(7, 'interact');
  const map = mapFromRows(ROWS);
  setup?.(state, map);
  state.maps = { farm: map };
  state.player.position = { mapId: 'farm', x: 3, y: 3 };
  state.player.facing = 'up';
  state.player.energy = 100;
  state.player.inventory.slots[0] = { id: 'hoe-t0', qty: 1, quality: 0 };
  state.player.inventory.selected = 0;

  const bus = new EventBus();
  const store = new Store(state, new Rng(11), bus);
  const used: ToolUsedEvent[] = [];
  const failed: ToolFailedEvent[] = [];
  bus.on<ToolUsedEvent>('tool:used', (e) => used.push(e));
  bus.on<ToolFailedEvent>('tool:failed', (e) => failed.push(e));
  registerEngineSim({ store, bus, content });
  const ctx: FeatureContext = {
    store,
    bus,
    rng: new Rng(11),
    content,
    headless: true,
    getRenderer: () => undefined,
    getConfig: () => ({}),
    persist: async () => {},
  };
  farmingSim.setup?.(ctx);
  return { store, bus, used, failed };
}

describe('player:interact reaches the tool handlers (regression)', () => {
  it('tills the tile in front when the hoe is swung through the real input path', async () => {
    const { store, used, failed } = await makeFx();

    expect(store.state.maps['farm']!.placed['3,2']).toBeUndefined();

    store.dispatch({ type: 'player:interact', payload: {} });

    expect(failed, `unexpected failure: ${JSON.stringify(failed)}`).toHaveLength(0);
    expect(used).toHaveLength(1);
    expect(used[0]!.effect).toBe('tilled');
    // The world actually changed - not just an event.
    expect(store.state.maps['farm']!.placed['3,2']?.id).toBe('tilled');
  });

  it('names the map on the request, so consumers can resolve it', async () => {
    const content = await loadContent();
    const state = createInitialState(7, 'interact-mapid');
    const map = mapFromRows(ROWS);
    state.maps = { farm: map };
    state.player.position = { mapId: 'farm', x: 3, y: 3 };
    state.player.facing = 'up';
    const bus = new EventBus();
    const store = new Store(state, new Rng(3), bus);
    registerEngineSim({ store, bus, content });
    const seen: Array<{ tile: { mapId?: string; x: number; y: number }; toolId: string }> = [];
    bus.on<{ tile: { mapId?: string; x: number; y: number }; toolId: string }>('tool:use-requested', (p) =>
      seen.push(p),
    );

    store.dispatch({ type: 'player:interact', payload: {} });

    expect(seen).toHaveLength(1);
    expect(seen[0]!.tile.mapId, 'tool:use-requested must carry mapId').toBe('farm');
    expect(seen[0]!.tile.x).toBe(3);
    expect(seen[0]!.tile.y).toBe(2);
  });

  it('still fails cleanly - with a real reason - on a blocked tile', async () => {
    const { store, used, failed } = await makeFx((_state, map) => {
      map.grid.tiles = map.grid.tiles.map(() => 'w');
    });

    store.dispatch({ type: 'player:interact', payload: {} });

    expect(used).toHaveLength(0);
    expect(failed).toHaveLength(1);
    // Not 'no-map': a real, specific reason for a real blocked tile.
    expect(failed[0]!.reason).not.toBe('no-map');
    expect(failed[0]!.reason).toBe('not-tillable');
  });

  it('spends energy and reports success for an axe on a weed through the same path', async () => {
    const { store, used, failed } = await makeFx((_state, map) => {
      map.placed['3,2'] = { id: 'weed', x: 3, y: 2, data: {} };
    });
    store.state.player.inventory.slots[0] = { id: 'axe-t0', qty: 1, quality: 0 };
    const before = store.state.player.energy;

    store.dispatch({ type: 'player:interact', payload: {} });

    expect(failed).toHaveLength(0);
    expect(used).toHaveLength(1);
    expect(used[0]!.effect).toBe('cleared');
    expect(store.state.maps['farm']!.placed['3,2']).toBeUndefined();
    expect(store.state.player.energy).toBeLessThan(before);
  });
});
