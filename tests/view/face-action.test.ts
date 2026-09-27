/**
 * T-0504 (WORKER-1): the turn-only `player:face` action.
 *
 * Free mouse look has to change what the player is aiming at WITHOUT moving
 * them and without spending energy, and the sim has to stay the single owner of
 * `player.facing` (that is what `tileInFront()` and every tool read). A turn is
 * not a move: `player:move`/`player:walk` reject a zero delta, so the action
 * below is the only way a camera drag can retarget — and it is the same
 * reducer path, not a view-local side channel.
 */
import { describe, expect, it } from 'vitest';
import { Store } from '@game/core/store';
import { Rng } from '@game/core/rng';
import { EventBus } from '@game/core/events';
import { createInitialState } from '@game/core/state';
import { loadContent } from '@game/core/content';
import {
  isFacing,
  registerEngineSim,
  tileInFront,
} from '@game/features/engine/sim/PlayerPosition';
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

async function makeFixture(): Promise<Store> {
  const content = await loadContent();
  const state: GameState = createInitialState(7, 'face');
  state.maps = { farm: mapFromRows(GROUND) };
  state.player.position = { mapId: 'farm', x: 3, y: 3 };
  state.player.energy = 10;
  const bus = new EventBus();
  const store = new Store(state, new Rng(11), bus);
  registerEngineSim({ store, bus, content });
  return store;
}

describe('engine:sim player:face', () => {
  it('turns without moving, and without spending energy', async () => {
    const store = await makeFixture();
    const before = store.state.player.position;

    store.dispatch({ type: 'player:face', payload: { facing: 'left' } });

    expect(store.state.player.facing).toBe('left');
    expect(store.state.player.position).toEqual(before);
    expect(store.state.player.energy).toBe(10);
  });

  it('moves the target tile, which is what the tool will hit', async () => {
    const store = await makeFixture();
    const pos = store.state.player.position;
    expect(tileInFront(pos, store.state.player.facing)).toEqual({ x: 3, y: 4 });
    store.dispatch({ type: 'player:face', payload: { facing: 'up' } });
    expect(tileInFront(store.state.player.position, store.state.player.facing)).toEqual({ x: 3, y: 2 });
    store.dispatch({ type: 'player:face', payload: { facing: 'left' } });
    expect(tileInFront(store.state.player.position, store.state.player.facing)).toEqual({ x: 2, y: 3 });
  });

  it('accepts every cardinal and survives a pointless re-dispatch', async () => {
    const store = await makeFixture();
    for (const facing of ['up', 'right', 'down', 'left'] as const) {
      store.dispatch({ type: 'player:face', payload: { facing } });
      expect(store.state.player.facing).toBe(facing);
    }
    // re-dispatching the same facing is a no-op, not an error
    store.dispatch({ type: 'player:face', payload: { facing: 'left' } });
    expect(store.state.player.facing).toBe('left');
  });

  it('leaves the facing alone when the payload is not a cardinal', async () => {
    const store = await makeFixture();
    store.dispatch({ type: 'player:face', payload: { facing: 'down' } });
    store.dispatch({
      type: 'player:face',
      payload: { facing: 'north-west' as unknown as 'down' },
    });
    expect(store.state.player.facing).toBe('down');
  });

  it('validates facings with isFacing', () => {
    expect(isFacing('up')).toBe(true);
    expect(isFacing('right')).toBe(true);
    expect(isFacing('north')).toBe(false);
    expect(isFacing(undefined)).toBe(false);
  });

  it('is overridden by a move, so the sim still owns the facing', async () => {
    // Moving sets the facing from the direction travelled; the last writer wins
    // and that is fine, because the view re-syncs from the sim every frame.
    const store = await makeFixture();
    store.dispatch({ type: 'player:face', payload: { facing: 'left' } });
    store.dispatch({ type: 'player:move', payload: { dx: 0, dy: -1 } });
    expect(store.state.player.facing).toBe('up');
  });
});
