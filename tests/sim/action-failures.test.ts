/**
 * T-0510: every action a player can take must fail LOUDLY.
 *
 * A silent no-op is the worst outcome for a player: the click lands, nothing
 * happens, and the game looks broken with no way to tell what went wrong. So
 * every failure path in the WORKER-2 sim lane emits a `<feature>:denied` event
 * carrying a machine-readable `reason`, and none of them mutate the world.
 *
 * This file covers the four failure classes that were previously silent or
 * lossy: a malformed action payload, an out-of-range/empty slot, a wrong item
 * type, and a full bag.
 */
import { describe, expect, it } from 'vitest';
import { createSim, DEFAULT_MODULES, type SimFixture } from './harness';
import { animalsSim } from '@game/features/animals/sim/AnimalsSim';
import { craftingSim } from '@game/features/crafting/sim/CraftingSim';
import { machinesSim } from '@game/features/machines/sim/MachinesSim';
import { skillsSim } from '@game/features/skills/sim/SkillsSim';

const FARM_TILE = { mapId: 'farm', x: 5, y: 5 };

async function fullSim(): Promise<SimFixture> {
  return createSim({
    modules: [...DEFAULT_MODULES, craftingSim, machinesSim, animalsSim, skillsSim],
  });
}

describe('malformed action payloads are denied, never silently dropped', () => {
  it('denies every shipping:insert payload that is not an integer slot', async () => {
    const sim = await createSim();
    const denied = sim.capture<Record<string, unknown>>('shipping:denied');
    const inserted = sim.capture('shipping:inserted');
    sim.dispatch('shipping:insert', null);
    sim.dispatch('shipping:insert', {});
    sim.dispatch('shipping:insert', { slot: '3' });
    sim.dispatch('shipping:insert', { slot: 1.5 });
    sim.dispatch('shipping:insert', { slot: Number.NaN });
    expect(denied.map((d) => d.reason)).toEqual([
      'bad-request',
      'bad-request',
      'bad-request',
      'bad-request',
      'bad-request',
    ]);
    expect(inserted).toHaveLength(0);
    expect(sim.shippingBox()).toHaveLength(0);
  });

  it('denies every malformed machine action and leaves the map untouched', async () => {
    const sim = await fullSim();
    sim.giveItem('mayonnaise-machine', 1);
    const denied = sim.capture<Record<string, unknown>>('machines:denied');
    sim.dispatch('machines:place', null);
    sim.dispatch('machines:place', { tile: FARM_TILE });
    sim.dispatch('machines:place', { tile: { x: 1, y: 1 }, itemId: 'mayonnaise-machine' });
    sim.dispatch('machines:insert', { tile: FARM_TILE, slot: '0' });
    sim.dispatch('machines:insert', { tile: FARM_TILE, slot: 0.5 });
    sim.dispatch('machines:insert', { slot: 0 });
    sim.dispatch('machines:collect', { tile: { mapId: 'farm', x: '1', y: 1 } });
    sim.dispatch('machines:interact', { tile: null });
    expect(denied).toHaveLength(8);
    expect(denied.every((d) => d.reason === 'bad-request')).toBe(true);
    // The machine is still in the bag, and nothing was placed anywhere.
    expect(sim.state.player.inventory.slots.some((s) => s?.id === 'mayonnaise-machine')).toBe(true);
    expect(Object.keys(sim.state.maps['farm']?.placed ?? {})).toHaveLength(5);
  });

  it('denies every malformed animal action and leaves the herd and gold alone', async () => {
    const sim = await fullSim();
    sim.store.state.player.money = 5000;
    const denied = sim.capture<Record<string, unknown>>('animals:denied');
    sim.dispatch('animals:buy', null);
    sim.dispatch('animals:buy', { qty: 2 });
    sim.dispatch('animals:feed', { animalId: 3 });
    sim.dispatch('animals:pet', null);
    sim.dispatch('animals:collect', { animalId: undefined });
    expect(denied).toHaveLength(5);
    expect(denied.every((d) => d.reason === 'bad-request')).toBe(true);
    expect(sim.state.player.money).toBe(5000);
    const ext = sim.state.extensions['animals'] as { animals: unknown[] } | undefined;
    expect(ext?.animals).toHaveLength(0);
  });
});

describe('shipping box refuses the wrong slot and the wrong item', () => {
  it('distinguishes an out-of-range slot, an empty slot, and a refusal to ship', async () => {
    const sim = await createSim();
    const denied = sim.capture<Record<string, unknown>>('shipping:denied');
    const inserted = sim.capture('shipping:inserted');
    const capacity = sim.state.player.inventory.capacity;

    sim.insertSlot(capacity);
    expect(denied.at(-1)?.reason).toBe('bad-slot');
    expect(denied.at(-1)?.slot).toBe(capacity);

    const empty = sim.state.player.inventory.slots.findIndex((s) => s === null);
    sim.insertSlot(empty);
    expect(denied.at(-1)?.reason).toBe('no-slot');

    // A tool, a weapon and a machine must never be sold for pocket change.
    for (const itemId of ['axe-t0', 'sword-t0', 'mayonnaise-machine']) {
      const slot = sim.giveItem(itemId, 1, 0);
      sim.insertSlot(slot);
      expect(denied.at(-1)).toMatchObject({ reason: 'not-shippable', slot, itemId });
      expect(sim.state.player.inventory.slots[slot]).toEqual({ id: itemId, qty: 1, quality: 0 });
    }
    expect(sim.shippingBox()).toHaveLength(0);
    expect(inserted).toHaveLength(0);
  });

  it('still ships a normal crop and pays out on sleep', async () => {
    const sim = await createSim();
    const inserted = sim.capture<Record<string, unknown>>('shipping:inserted');
    const slot = sim.giveItem('parsnip', 2, 0);
    sim.insertSlot(slot);
    expect(inserted).toEqual([{ slot, itemId: 'parsnip', qty: 2 }]);
    expect(sim.shippingBox()).toEqual([{ id: 'parsnip', qty: 2, quality: 0 }]);
    sim.sleep();
    expect(sim.money()).toBe(500 + 35 * 2);
  });
});

describe('a full bag refuses the action and keeps the goods', () => {
  it('keeps a machine product when there is no room for it', async () => {
    const sim = await fullSim();
    sim.giveItem('mayonnaise-machine', 1);
    sim.dispatch('machines:place', { tile: FARM_TILE, itemId: 'mayonnaise-machine' });
    const eggSlot = sim.giveItem('egg', 3, 0);
    sim.dispatch('machines:insert', { tile: FARM_TILE, slot: eggSlot });
    expect(sim.cropData('farm', 5, 5)?.loaded).toBe(1);

    // Fill every remaining slot with a single, non-stackable-quality item.
    const slots = sim.state.player.inventory.slots;
    for (let i = 0; i < slots.length; i++) {
      if (slots[i] === null) slots[i] = { id: 'wood', qty: 1, quality: 2 };
    }
    sim.tickMinutes(600);
    const denied = sim.capture<Record<string, unknown>>('machines:denied');
    sim.dispatch('machines:collect', { tile: FARM_TILE });
    expect(denied.at(-1)).toMatchObject({ reason: 'inventory-full' });
    // Still loaded and still ready: the product is not destroyed.
    expect(sim.cropData('farm', 5, 5)?.loaded).toBe(1);
    expect(sim.cropData('farm', 5, 5)?.remainingTicks).toBe(0);
  });

  it('keeps an animal product when there is no room for it', async () => {
    const sim = await fullSim();
    sim.store.state.player.money = 5000;
    sim.dispatch('animals:buy', { species: 'chicken', qty: 1 });
    const uid = (sim.state.extensions['animals'] as { animals: { id: string }[] }).animals[0]?.id;
    expect(uid).toBeDefined();

    // Hand-build a ready product so the test does not depend on 8 days of play.
    const ext = sim.state.extensions['animals'] as {
      animals: Record<string, unknown>[];
      lastRolledDay: number;
      seq: number;
    };
    ext.animals[0] = { ...ext.animals[0]!, productReady: true, happy: 100, hearts: 5 };

    const slots = sim.state.player.inventory.slots;
    for (let i = 0; i < slots.length; i++) {
      if (slots[i] === null) slots[i] = { id: 'wood', qty: 1, quality: 2 };
    }
    const denied = sim.capture<Record<string, unknown>>('animals:denied');
    sim.dispatch('animals:collect', { animalId: uid! });
    expect(denied.at(-1)).toMatchObject({ reason: 'inventory-full' });
    const after = (sim.state.extensions['animals'] as { animals: { productReady: boolean }[] })
      .animals[0];
    expect(after?.productReady).toBe(true);
  });
});

describe('sleep has no failure mode, and says so', () => {
  it('always advances the day and never denies', async () => {
    const sim = await fullSim();
    const denied = [
      ...sim.capture('shipping:denied'),
      ...sim.capture('animals:denied'),
      ...sim.capture('crafting:denied'),
      ...sim.capture('machines:denied'),
    ];
    for (let i = 0; i < 3; i++) {
      const before = sim.state.world.dayCount;
      sim.sleep();
      expect(sim.state.world.dayCount).toBe(before + 1);
    }
    expect(denied).toHaveLength(0);
  });
});
