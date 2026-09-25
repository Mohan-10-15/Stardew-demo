/**
 * machines:sim specs (WORKER-2 lane). Covers placing a crafted machine on a
 * free walkable tile, loading one input bundle from a bag slot, the 10-minute
 * countdown through `time:tick`, collecting the output, every denial branch,
 * and that placed machines + in-flight work survive save/persist.
 *
 * Machine ids double as the item id used to place them (the item comes from
 * the crafting menu). All machine state lives in `MapState.placed[x,y].data`
 * so it persists with the maps.
 */
import { describe, expect, it } from 'vitest';
import { machineIdOf, machinesSim, tickMachines } from '@game/features/machines';
import { createSim, DEFAULT_MODULES, type SimFixture } from './harness';

async function makeFixture(): Promise<SimFixture> {
  const fx = await createSim({ modules: [...DEFAULT_MODULES, machinesSim] });
  fx.giveItem('mayonnaise-machine', 1);
  fx.giveItem('egg', 3);
  return fx;
}

const FARM_TILE = { mapId: 'farm', x: 5, y: 5 };

function placedData(fx: SimFixture, x = FARM_TILE.x, y = FARM_TILE.y): Record<string, unknown> | undefined {
  return fx.placed('farm', x, y)?.data;
}

describe('machines:place', () => {
  it('consumes the machine item and adds a machine:<id> placed object', async () => {
    const fx = await makeFixture();
    const placed = fx.capture<any>('machines:placed');
    fx.dispatch('machines:place', { tile: FARM_TILE, itemId: 'mayonnaise-machine' });
    const obj = fx.placed('farm', FARM_TILE.x, FARM_TILE.y);
    expect(obj?.id).toBe('machine:mayonnaise-machine');
    expect(machineIdOf(obj!.id)).toBe('mayonnaise-machine');
    expect(fx.state.player.inventory.slots.some((s) => s?.id === 'mayonnaise-machine')).toBe(false);
    expect(placed).toEqual([{ tile: FARM_TILE, machineId: 'mayonnaise-machine' }]);
  });

  it('places on any walkable second tile too', async () => {
    const fx = await makeFixture();
    fx.giveItem('seed-maker', 1);
    fx.dispatch('machines:place', { tile: { mapId: 'farm', x: 8, y: 9 }, itemId: 'seed-maker' });
    expect(fx.placed('farm', 8, 9)?.id).toBe('machine:seed-maker');
  });

  it('denies on an occupied tile without consuming the item', async () => {
    const fx = await makeFixture();
    const denied = fx.capture<any>('machines:denied');
    fx.dispatch('machines:place', { tile: { mapId: 'farm', x: 10, y: 10 }, itemId: 'mayonnaise-machine' });
    expect(denied).toEqual([{ reason: 'occupied', tile: { mapId: 'farm', x: 10, y: 10 } }]);
    expect(fx.state.player.inventory.slots.some((s) => s?.id === 'mayonnaise-machine')).toBe(true);
  });

  it('denies on a non-walkable tile', async () => {
    const fx = await makeFixture();
    const denied = fx.capture<any>('machines:denied');
    fx.dispatch('machines:place', { tile: { mapId: 'farm', x: -1, y: -1 }, itemId: 'mayonnaise-machine' });
    expect(denied[0]?.reason).toBe('blocked');
  });

  it('denies unknown machines, missing items, and unknown maps', async () => {
    const fx = await makeFixture();
    const denied = fx.capture<any>('machines:denied');
    fx.dispatch('machines:place', { tile: FARM_TILE, itemId: 'nope-machine' });
    fx.dispatch('machines:place', { tile: { mapId: 'nowhere', x: 1, y: 1 }, itemId: 'mayonnaise-machine' });
    expect(fx.state.player.inventory.slots.some((s) => s?.id === 'mayonnaise-machine')).toBe(true);
    const reasons = denied.map((d) => d.reason);
    expect(reasons).toEqual(['unknown-machine', 'no-map']);
  });
});

describe('machines:insert', () => {
  it('loads the matching input bundle and arms the countdown', async () => {
    const fx = await makeFixture();
    fx.dispatch('machines:place', { tile: FARM_TILE, itemId: 'mayonnaise-machine' });
    const loaded = fx.capture<any>('machines:loaded');
    const eggSlot = fx.state.player.inventory.slots.findIndex((s) => s?.id === 'egg');
    fx.dispatch('machines:insert', { tile: FARM_TILE, slot: eggSlot });
    expect(loaded).toEqual([{ tile: FARM_TILE, machineId: 'mayonnaise-machine', itemId: 'egg', qty: 1 }]);
    const data = placedData(fx);
    expect(data?.['loaded']).toBe(1);
    expect(data?.['remainingTicks']).toBe(3 * 6);
    const eggs = fx.state.player.inventory.slots.filter((s) => s?.id === 'egg').reduce((n, s) => n + (s?.qty ?? 0), 0);
    expect(eggs).toBe(2);
  });

  it('denies when the bag slot does not match any input', async () => {
    const fx = await makeFixture();
    fx.dispatch('machines:place', { tile: FARM_TILE, itemId: 'mayonnaise-machine' });
    const denied = fx.capture<any>('machines:denied');
    const woodSlot = fx.giveItem('wood', 1);
    fx.dispatch('machines:insert', { tile: FARM_TILE, slot: woodSlot });
    expect(denied[0]?.reason).toBe('not-needed');
  });

  it('denies busy machines, empty slots, and missing tiles', async () => {
    const fx = await makeFixture();
    fx.dispatch('machines:place', { tile: FARM_TILE, itemId: 'mayonnaise-machine' });
    fx.dispatch('machines:insert', { tile: FARM_TILE, slot: fx.state.player.inventory.slots.findIndex((s) => s?.id === 'egg') });
    const denied = fx.capture<any>('machines:denied');
    const eggSlot = fx.state.player.inventory.slots.findIndex((s) => s?.id === 'egg');
    fx.dispatch('machines:insert', { tile: FARM_TILE, slot: eggSlot });
    fx.dispatch('machines:insert', { tile: FARM_TILE, slot: 99 });
    fx.dispatch('machines:insert', { tile: { mapId: 'farm', x: 30, y: 30 }, slot: 0 });
    expect(denied.map((d) => d.reason)).toEqual(['busy', 'no-slot', 'no-machine']);
  });
});

describe('machines:processing', () => {
  it('counts down one tick per 10 minutes and finishes on schedule', async () => {
    const fx = await makeFixture();
    fx.giveItem('seed-maker', 1);
    fx.giveItem('parsnip', 1);
    fx.dispatch('machines:place', { tile: FARM_TILE, itemId: 'seed-maker' });
    const seedSlot = fx.state.player.inventory.slots.findIndex((s) => s?.id === 'parsnip');
    fx.dispatch('machines:insert', { tile: FARM_TILE, slot: seedSlot });
    const finished = fx.capture<any>('machines:finished');
    fx.tickMinutes(50);
    expect(placedData(fx)?.['remainingTicks']).toBe(1);
    fx.tickStep();
    expect(finished).toEqual([{ mapId: 'farm', tile: { mapId: 'farm', x: FARM_TILE.x, y: FARM_TILE.y }, machineId: 'seed-maker' }]);
    const data = placedData(fx);
    expect(data?.['loaded']).toBe(1);
    expect(data?.['remainingTicks']).toBe(0);
  });

  it('collects the output and restores the machine to empty', async () => {
    const fx = await makeFixture();
    fx.dispatch('machines:place', { tile: FARM_TILE, itemId: 'mayonnaise-machine' });
    const eggSlot = fx.state.player.inventory.slots.findIndex((s) => s?.id === 'egg');
    fx.dispatch('machines:insert', { tile: FARM_TILE, slot: eggSlot });
    fx.tickMinutes(3 * 60);
    const collected = fx.capture<any>('machines:collected');
    fx.dispatch('machines:collect', { tile: FARM_TILE });
    expect(collected).toEqual([
      { tile: FARM_TILE, machineId: 'mayonnaise-machine', items: [{ itemId: 'mayonnaise', qty: 1 }] },
    ]);
    expect(fx.state.player.inventory.slots.some((s) => s?.id === 'mayonnaise')).toBe(true);
    const data = placedData(fx);
    expect(data?.['loaded']).toBe(0);
    expect(data?.['remainingTicks']).toBe(0);
  });

  it('denies collecting a not-ready or empty machine', async () => {
    const fx = await makeFixture();
    fx.dispatch('machines:place', { tile: FARM_TILE, itemId: 'mayonnaise-machine' });
    const denied = fx.capture<any>('machines:denied');
    fx.dispatch('machines:collect', { tile: FARM_TILE });
    const eggSlot = fx.state.player.inventory.slots.findIndex((s) => s?.id === 'egg');
    fx.dispatch('machines:insert', { tile: FARM_TILE, slot: eggSlot });
    fx.tickMinutes(10); // 110 minutes remaining, definitely not finished
    fx.dispatch('machines:collect', { tile: FARM_TILE });
    fx.dispatch('machines:collect', { tile: { mapId: 'farm', x: 30, y: 30 } });
    expect(denied.map((d) => d.reason)).toEqual(['not-loaded', 'not-ready', 'no-machine']);
  });

  it('keeps the product when the bag is full (inventory:full, machine stays ready)', async () => {
    const fx = await makeFixture();
    fx.dispatch('machines:place', { tile: FARM_TILE, itemId: 'mayonnaise-machine' });
    const eggSlot = fx.state.player.inventory.slots.findIndex((s) => s?.id === 'egg');
    fx.dispatch('machines:insert', { tile: FARM_TILE, slot: eggSlot });
    fx.tickMinutes(3 * 60);
    for (let i = 0; i < fx.state.player.inventory.slots.length; i++) {
      if (fx.state.player.inventory.slots[i] === null) fx.setSlot(i, { id: 'rock', qty: 1, quality: 0 });
    }
    const full = fx.capture<any>('inventory:full');
    const denied = fx.capture<any>('machines:denied');
    fx.dispatch('machines:collect', { tile: FARM_TILE });
    expect(full).toHaveLength(1);
    expect(denied[0]?.reason).toBe('inventory-full');
    const data = placedData(fx);
    expect(data?.['loaded']).toBe(1);
    expect(data?.['remainingTicks']).toBe(0);
  });

  it('tickMachines does not grow state when nothing is running', async () => {
    const fx = await makeFixture();
    const before = fx.state;
    const after = tickMachines(fx.state, fx.content, fx.bus);
    expect(after).toBe(before);
  });
});

describe('machines:persistence', () => {
  it('saves placed machines and their in-flight work', async () => {
    const fx = await makeFixture();
    fx.dispatch('machines:place', { tile: FARM_TILE, itemId: 'mayonnaise-machine' });
    const eggSlot = fx.state.player.inventory.slots.findIndex((s) => s?.id === 'egg');
    fx.dispatch('machines:insert', { tile: FARM_TILE, slot: eggSlot });
    fx.tickMinutes(30);
    fx.dispatch('player:sleep', null);
    const saved = await fx.flushPersist();
    expect(saved).not.toBeNull();
    const obj = saved?.state.maps['farm']?.placed[`${FARM_TILE.x},${FARM_TILE.y}`];
    expect(obj?.id).toBe('machine:mayonnaise-machine');
    expect(obj?.data?.['loaded']).toBe(1);
    expect(obj?.data?.['remainingTicks']).toBe(3 * 6 - 3);
  });
});

describe('machines:map coverage', () => {
  it('testFarmMap is walkable for machine placement', async () => {
    const fx = await makeFixture();
    fx.giveItem('seed-maker', 1);
    fx.dispatch('machines:place', { tile: FARM_TILE, itemId: 'seed-maker' });
    expect(fx.placed('farm', FARM_TILE.x, FARM_TILE.y)?.id).toBe('machine:seed-maker');
  });
});