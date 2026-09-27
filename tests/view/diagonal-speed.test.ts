/**
 * T-0506 WORKER-1: per-axis movement speed.
 *
 * The bug: `player:walk` normalised the held direction by hypot(dx, dy), so
 * the *combined* displacement was capped at speed*dt. A diagonal therefore
 * advanced only 1/sqrt(2) of the walk speed on each axis and felt ~30%
 * sluggish per axis versus a straight walk (measured ratio 0.66-0.71 in the
 * browser). The fix steps each held axis by the full speed*dt.
 *
 * These tests assert the invariant rather than a magic number: for a fixed
 * (dt, speed), a diagonal's x delta must equal the single-axis x delta and its
 * y delta the single-axis y delta. That holds for every dt, so the table is
 * driven rather than hard-coded.
 */
import { describe, expect, it } from 'vitest';
import { Store } from '@game/core/store';
import { Rng } from '@game/core/rng';
import { EventBus } from '@game/core/events';
import { createInitialState } from '@game/core/state';
import { loadContent } from '@game/core/content';
import {
  registerEngineSim,
  playerWalkReducer,
  JOG_UNITS_PER_SEC,
  WALK_SPEED_MULT,
  WALK_ENERGY_COST,
} from '@game/features/engine/sim/PlayerPosition';
import type { ContentDb } from '@game/core/content';
import type { GameState, MapState } from '@game/core/types';

const SIZE = 24;
const OPEN = Array.from({ length: SIZE }, () => 'g'.repeat(SIZE)).join('');

/**
 * Row 11 is a solid water wall across the map, so "into a wall" and "along a
 * wall" are unambiguous: walking north from row 12 is blocked, and the x axis
 * is completely free.
 */
const HALF_WALL = Array.from({ length: SIZE }, (_, y) => (y === 11 ? 'w'.repeat(SIZE) : 'g'.repeat(SIZE))).join(
  '',
);

const CENTRE = Math.floor(SIZE / 2);

function mapFromTiles(tiles: string): MapState {
  return {
    id: 'farm',
    grid: { tiles: tiles.split(''), width: SIZE, height: SIZE },
    placed: {},
    npcs: {},
    version: 1,
  };
}

async function makeFixture(tiles = OPEN, x = CENTRE, y = CENTRE): Promise<{
  store: Store;
  bus: EventBus;
  content: ContentDb;
}> {
  const content = await loadContent();
  const state: GameState = createInitialState(7, 'diagonal-speed');
  state.maps = { farm: mapFromTiles(tiles) };
  state.player.position = { mapId: 'farm', x, y };
  state.player.energy = 100;
  const bus = new EventBus();
  const store = new Store(state, new Rng(11), bus);
  registerEngineSim({ store, bus, content });
  return { store, bus, content };
}

interface Delta {
  dx: number;
  dy: number;
}

/** One dispatch from a clean centre tile; returns the achieved per-axis delta. */
async function stepFromCentre(
  dir: Delta,
  dt: number,
  speed: number,
  tiles = OPEN,
  y = CENTRE,
): Promise<{ dx: number; dy: number; facing: string; energy: number }> {
  const { store } = await makeFixture(tiles, CENTRE, y);
  store.dispatch({ type: 'player:walk', payload: { dx: dir.dx, dy: dir.dy, dt, speed } });
  const pos = store.state.player.position;
  return {
    dx: pos.x - CENTRE,
    dy: pos.y - y,
    facing: store.state.player.facing,
    energy: store.state.player.energy,
  };
}

const SINGLES: ReadonlyArray<[label: string, dir: Delta, facing: string]> = [
  ['W (up)', { dx: 0, dy: -1 }, 'up'],
  ['S (down)', { dx: 0, dy: 1 }, 'down'],
  ['A (left)', { dx: -1, dy: 0 }, 'left'],
  ['D (right)', { dx: 1, dy: 0 }, 'right'],
];

const DIAGONALS: ReadonlyArray<[label: string, dir: Delta]> = [
  ['W+D', { dx: 1, dy: -1 }],
  ['W+A', { dx: -1, dy: -1 }],
  ['S+D', { dx: 1, dy: 1 }],
  ['S+A', { dx: -1, dy: 1 }],
];

const DTS = [0.016, 0.05, 0.1, 0.25, 0.5];

describe('player:walk per-axis speed (T-0506)', () => {
  it('moves each single axis by exactly speed*dt', async () => {
    for (const dt of DTS) {
      for (const [label, dir, facing] of SINGLES) {
        const r = await stepFromCentre(dir, dt, JOG_UNITS_PER_SEC);
        expect(r.dx, `${label} dt=${dt} dx`).toBeCloseTo(dir.dx * JOG_UNITS_PER_SEC * dt, 6);
        expect(r.dy, `${label} dt=${dt} dy`).toBeCloseTo(dir.dy * JOG_UNITS_PER_SEC * dt, 6);
        expect(r.facing, `${label} dt=${dt} facing`).toBe(facing);
      }
    }
  });

  it('gives every diagonal the SAME per-axis delta as the matching singles (the invariant)', async () => {
    for (const dt of DTS) {
      const reference = {
        right: await stepFromCentre({ dx: 1, dy: 0 }, dt, JOG_UNITS_PER_SEC),
        left: await stepFromCentre({ dx: -1, dy: 0 }, dt, JOG_UNITS_PER_SEC),
        up: await stepFromCentre({ dx: 0, dy: -1 }, dt, JOG_UNITS_PER_SEC),
        down: await stepFromCentre({ dx: 0, dy: 1 }, dt, JOG_UNITS_PER_SEC),
      };
      const singleX = reference.right.dx;
      const singleUpY = reference.up.dy;

      for (const [label, dir] of DIAGONALS) {
        const r = await stepFromCentre(dir, dt, JOG_UNITS_PER_SEC);
        // x delta equals the x delta of the single-axis walk for this dt...
        expect(r.dx, `${label} dt=${dt} x vs single-axis x`).toBeCloseTo(
          dir.dx > 0 ? singleX : -singleX,
          6,
        );
        // ...and y delta equals the y delta of the single-axis walk for this dt.
        expect(r.dy, `${label} dt=${dt} y vs single-axis y`).toBeCloseTo(dir.dy > 0 ? -singleUpY : singleUpY, 6);
        expect(r.dx, `${label} dt=${dt} x must not be 1/sqrt(2) of the single`).not.toBeCloseTo(
          dir.dx * singleX / Math.SQRT2,
          3,
        );
      }
    }
  });

  it('a diagonal is exactly sqrt(2)x the path length, not the same path length', async () => {
    const single = await stepFromCentre({ dx: 1, dy: 0 }, 0.5, JOG_UNITS_PER_SEC);
    const diag = await stepFromCentre({ dx: 1, dy: -1 }, 0.5, JOG_UNITS_PER_SEC);

    expect(Math.hypot(single.dx, single.dy)).toBeCloseTo(JOG_UNITS_PER_SEC * 0.5, 6);
    expect(Math.hypot(diag.dx, diag.dy)).toBeCloseTo(JOG_UNITS_PER_SEC * 0.5 * Math.SQRT2, 6);
  });

  it('holds the invariant on the shift-to-walk speed too', async () => {
    const walkSpeed = JOG_UNITS_PER_SEC * WALK_SPEED_MULT;
    const single = await stepFromCentre({ dx: 0, dy: 1 }, 0.5, walkSpeed);
    const diag = await stepFromCentre({ dx: 1, dy: 1 }, 0.5, walkSpeed);

    expect(diag.dy).toBeCloseTo(single.dy, 6);
    expect(diag.dx).toBeCloseTo(walkSpeed * 0.5, 6);
    expect(diag.dx).not.toBeCloseTo(walkSpeed * 0.5 * Math.SQRT2, 3);
  });

  it('charges energy for the distance actually travelled, including both diagonal axes', async () => {
    const diag = await stepFromCentre({ dx: 1, dy: -1 }, 0.5, JOG_UNITS_PER_SEC);
    const dist = Math.hypot(diag.dx, diag.dy);
    expect(diag.energy).toBeCloseTo(100 - WALK_ENERGY_COST * dist, 6);
  });

  it('collapses opposite keys to a standstill without producing NaN', async () => {
    const { store, content } = await makeFixture();
    const before = { ...store.state.player.position };

    // W+S cancel in the input layer's sum, so no walk is dispatched at all;
    // drive the reducer directly to prove the zero vector cannot divide by zero.
    const after = playerWalkReducer(
      store.state,
      { type: 'player:walk', payload: { dx: 0, dy: 0, dt: 0.1, speed: JOG_UNITS_PER_SEC } },
      content,
    );

    expect(after.player.position).toEqual(before);
    expect(Number.isNaN(after.player.position.x)).toBe(false);
    expect(Number.isNaN(after.player.position.y)).toBe(false);

    store.dispatch({ type: 'player:walk', payload: { dx: 0, dy: 0, dt: 0.1, speed: JOG_UNITS_PER_SEC } });
    expect(store.state.player.position).toEqual(before);
  });

  it('treats two keys on the SAME axis as one axis, not double speed', async () => {
    // 'd' and 'arrowright' both bind to dx=+1, so the input layer sums to dx=2.
    const single = await stepFromCentre({ dx: 1, dy: 0 }, 0.5, JOG_UNITS_PER_SEC);
    const doubled = await stepFromCentre({ dx: 2, dy: 0 }, 0.5, JOG_UNITS_PER_SEC);

    expect(doubled.dx).toBeCloseTo(single.dx, 6);
  });

  it('treats a three-key press (one axis cancelled) as the surviving single axis', async () => {
    const up = await stepFromCentre({ dx: 0, dy: -1 }, 0.5, JOG_UNITS_PER_SEC);
    // W + A + D: dx cancels to 0, leaving exactly W.
    const threeKeys = await stepFromCentre({ dx: 0, dy: -1 }, 0.5, JOG_UNITS_PER_SEC);

    expect(threeKeys.dy).toBeCloseTo(up.dy, 6);
    expect(threeKeys.dx).toBe(0);
  });
});

describe('player:wall sliding survives per-axis movement (T-0506)', () => {
  it('a diagonal into a wall slides along it instead of stopping dead', async () => {
    // Standing on row 12, the water wall is row 11: north is blocked, east is free.
    const r = await stepFromCentre({ dx: 1, dy: -1 }, 0.5, JOG_UNITS_PER_SEC, HALF_WALL, 12);

    expect(r.dy).toBe(0);
    expect(r.facing).toBe('up');
    // x keeps the full single-axis speed: sliding must not be slowed either.
    expect(r.dx).toBeCloseTo(JOG_UNITS_PER_SEC * 0.5, 6);
    expect(r.dx).not.toBeCloseTo((JOG_UNITS_PER_SEC * 0.5) / Math.SQRT2, 3);
  });

  it('a diagonal straight into a wall moves nothing on either axis', async () => {
    // Both axes blocked: west edge (x=0) with the water wall to the north.
    const { store } = await makeFixture(HALF_WALL, 0, 12);
    const before = { ...store.state.player.position };

    store.dispatch({ type: 'player:walk', payload: { dx: -1, dy: -1, dt: 0.5, speed: JOG_UNITS_PER_SEC } });

    expect(store.state.player.position).toEqual(before);
    expect(store.state.player.energy).toBe(100);
  });

  it('keeps sliding frame after frame along a continuous wall', async () => {
    const { store } = await makeFixture(HALF_WALL, 4, 12);
    const dt = 0.05;

    for (let i = 0; i < 10; i++) {
      store.dispatch({ type: 'player:walk', payload: { dx: 1, dy: -1, dt, speed: JOG_UNITS_PER_SEC } });
    }

    expect(store.state.player.position.y).toBe(12);
    expect(store.state.player.position.x).toBeCloseTo(4 + 10 * JOG_UNITS_PER_SEC * dt, 6);
  });
});
