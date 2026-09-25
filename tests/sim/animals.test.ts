/**
 * animals:sim specs (WORKER-2 lane). Covers buying with gold, the feed/hunger/
 * hearts cycle across mornings (both sleep and forced pass-out paths), product
 * readiness gating on bond, inventory quality from happiness, and that the
 * whole herd survives save/load like any other extension.
 *
 * Product gating: an animal only produces once its bond crosses
 * MIN_HEARTS_TO_PRODUCE (2). Feeding a morning is +0.35 hearts and petting
 * +0.2, so a fresh animal needs ~4 fully-cared days before its first product.
 */
import { describe, expect, it } from 'vitest';
import { animalsSim } from '@game/features/animals/sim/AnimalsSim';
import { animalsOf, readAnimalsExt, rollAnimalQuality } from '@game/features/animals';
import { ANIMALS_EXT_ID } from '@game/features/animals';
import { wrapSave, serializeToJson, parseJson, migrateSave } from '@game/core/save';
import { createSim, DEFAULT_MODULES, type SimFixture } from './harness';
import { Rng } from '@game/core/rng';

async function makeFixture(): Promise<SimFixture> {
  const fx = await createSim({ modules: [...DEFAULT_MODULES, animalsSim] });
  fx.store.state.player.money = 10000;
  fx.giveItem('hay', 50);
  return fx;
}

function buyChicken(fx: SimFixture, qty = 1): void {
  const bought = fx.capture<any>('animals:bought');
  fx.dispatch('animals:buy', { species: 'chicken', qty });
  expect(bought).toHaveLength(1);
}

/** feed + pet + sleep for `days` mornings (each full care day = +0.55 hearts). */
function careFor(fx: SimFixture, animalId: string, days = 4): void {
  for (let i = 0; i < days; i++) {
    fx.dispatch('animals:feed', { animalId });
    fx.dispatch('animals:pet', { animalId });
    fx.sleep();
  }
}

function hayCount(fx: SimFixture): number {
  return fx.state.player.inventory.slots
    .filter((s) => s?.id === 'hay')
    .reduce((t, s) => t + (s?.qty ?? 0), 0);
}

describe('buying', () => {
  it('charges gold, adds the animal, and rejects an unknown species', async () => {
    const fx = await makeFixture();
    const before = fx.money();
    const denied = fx.capture<any>('animals:denied');

    fx.dispatch('animals:buy', { species: 'chicken', qty: 2 });
    expect(fx.money()).toBe(before - 800);
    expect(animalsOf(fx.state)).toHaveLength(2);
    expect(animalsOf(fx.state).map((a) => a.species).sort()).toEqual(['chicken', 'chicken']);

    fx.dispatch('animals:buy', { species: 'unicorn', qty: 1 });
    expect(denied).toHaveLength(1);
    expect(denied[0]!.reason).toBe('unknown-species');
    expect(animalsOf(fx.state)).toHaveLength(2);
  });

  it('refuses when broke and when the barn is full', async () => {
    const fx = await makeFixture();
    const denied = fx.capture<any>('animals:denied');

    fx.store.state.player.money = 100;
    fx.dispatch('animals:buy', { species: 'cow', qty: 1 });
    expect(denied.filter((d) => d.reason === 'no-gold')).toHaveLength(1);

    fx.store.state.player.money = 1_000_000;
    fx.dispatch('animals:buy', { species: 'chicken', qty: 24 });
    expect(animalsOf(fx.state)).toHaveLength(24);
    fx.dispatch('animals:buy', { species: 'chicken', qty: 1 });
    expect(denied.filter((d) => d.reason === 'full')).toHaveLength(1);
  });

  it('uid sequence stays unique across species', async () => {
    const fx = await makeFixture();
    fx.dispatch('animals:buy', { species: 'chicken', qty: 2 });
    fx.dispatch('animals:buy', { species: 'cow', qty: 1 });
    const ids = animalsOf(fx.state).map((a) => a.id);
    expect(new Set(ids).size).toBe(3);
    expect(new Set(ids)).toEqual(new Set(['chicken-1', 'chicken-2', 'cow-3']));
  });
});

describe('daily roll (sleep path)', () => {
  it('a fed, petted morning raises happiness and bond; one day is not enough for a product', async () => {
    const fx = await makeFixture();
    buyChicken(fx);
    const a = animalsOf(fx.state)[0]!;
    expect(a.productReady).toBe(false);

    fx.dispatch('animals:feed', { animalId: a.id });
    expect(animalsOf(fx.state)[0]!.fedToday).toBe(true);
    expect(hayCount(fx)).toBe(49);

    fx.sleep();
    const after = animalsOf(fx.state)[0]!;
    expect(after.happy).toBeGreaterThan(a.happy);
    expect(after.hearts).toBeGreaterThan(0);
    expect(after.fedToday).toBe(false);
    expect(after.hungerStreak).toBe(0);
    expect(after.productReady).toBe(false); // 0.35 hearts < the bond gate
  });

  it('unfed animals get hungrier, lose happiness and never bond', async () => {
    const fx = await makeFixture();
    buyChicken(fx);
    const before = animalsOf(fx.state)[0]!;

    fx.sleep();
    const d1 = animalsOf(fx.state)[0]!;
    expect(d1.hungerStreak).toBe(1);
    expect(d1.happy).toBeLessThan(before.happy);

    fx.sleep();
    const d2 = animalsOf(fx.state)[0]!;
    expect(d2.hungerStreak).toBe(2);
    expect(d2.happy).toBeLessThan(d1.happy);
    expect(d2.hearts).toBe(0);
    expect(d2.productReady).toBe(false);
  });

  it('a fully-cared animal crosses the bond gate and produces its first product', async () => {
    const fx = await makeFixture();
    buyChicken(fx);
    const a = animalsOf(fx.state)[0]!;
    careFor(fx, a.id, 4);
    const after = animalsOf(fx.state)[0]!;
    expect(after.hearts).toBeGreaterThanOrEqual(2);
    expect(after.productReady).toBe(true);
    expect(readAnimalsExt(fx.state).lastRolledDay).toBe(fx.state.world.dayCount);
  });

  it('the roll is idempotent across both rollover paths', async () => {
    const fx = await makeFixture();
    buyChicken(fx);
    const a = animalsOf(fx.state)[0]!;
    fx.dispatch('animals:feed', { animalId: a.id });

    // sleep reducer evaluates day+1; afterwards a plain tick must not re-roll.
    fx.sleep();
    const afterSleep = animalsOf(fx.state)[0]!;
    fx.tickMinutes(10);
    const afterTick = animalsOf(fx.state)[0]!;
    expect(afterTick.happy).toBe(afterSleep.happy);
    expect(readAnimalsExt(fx.state).lastRolledDay).toBe(fx.state.world.dayCount);
  });
});

describe('daily roll (forced pass-out path)', () => {
  it('processes via time:tick when the clock crosses midnight', async () => {
    const fx = await makeFixture();
    buyChicken(fx);
    const a = animalsOf(fx.state)[0]!;
    fx.dispatch('animals:feed', { animalId: a.id });

    fx.store.state.world.clock.hour = 23;
    fx.store.state.world.clock.minute = 50;
    fx.tickStep(); // 23:50 -> 00:00: one day rolls, the fed morning applies
    const after = animalsOf(fx.state)[0]!;
    expect(fx.state.world.dayCount).toBe(a.bornDay + 1);
    expect(after.hearts).toBe(0.35);
    expect(after.fedToday).toBe(false);
    expect(after.productReady).toBe(false);
    expect(readAnimalsExt(fx.state).lastRolledDay).toBe(fx.state.world.dayCount);
  });
});

describe('feeding / petting / collecting', () => {
  it('feeding consumes exactly the feed item and refuses a second serving', async () => {
    const fx = await makeFixture();
    buyChicken(fx);
    const a = animalsOf(fx.state)[0]!;
    const denied = fx.capture<any>('animals:denied');

    fx.dispatch('animals:feed', { animalId: a.id });
    expect(animalsOf(fx.state)[0]!.fedToday).toBe(true);

    fx.dispatch('animals:feed', { animalId: a.id });
    expect(denied).toHaveLength(1);
    expect(denied[0]!.reason).toBe('already-fed');

    fx.dispatch('animals:pet', { animalId: a.id });
    fx.dispatch('animals:pet', { animalId: a.id });
    expect(denied).toHaveLength(2);
    expect(denied[1]!.reason).toBe('already-petted');
  });

  it('a hungry owner cannot feed without hay', async () => {
    const fx = await makeFixture();
    buyChicken(fx);
    const a = animalsOf(fx.state)[0]!;
    const denied = fx.capture<any>('animals:denied');
    fx.store.state.player.inventory.slots.fill(null);

    fx.dispatch('animals:feed', { animalId: a.id });
    expect(denied).toHaveLength(1);
    expect(denied[0]!.reason).toBe('no-feed');
    expect(animalsOf(fx.state)[0]!.fedToday).toBe(false);
  });

  it('collecting takes the ready product into the bag and schedules the next', async () => {
    const fx = await makeFixture();
    buyChicken(fx);
    const a = animalsOf(fx.state)[0]!;
    careFor(fx, a.id, 4);
    fx.store.state.player.inventory.slots.fill(null); // clear hay remnants

    const collected = fx.capture<any>('animals:collected');
    const denied = fx.capture<any>('animals:denied');
    fx.dispatch('animals:collect', { animalId: a.id });
    expect(collected).toHaveLength(1);
    expect(collected[0]!.itemId).toBe('egg');
    expect(collected[0]!.quality).toBeGreaterThanOrEqual(0);
    const stack = fx.store.state.player.inventory.slots.find((s) => s?.id === 'egg');
    expect(stack).not.toBeUndefined();
    expect(stack!.qty).toBe(1);

    const after = animalsOf(fx.state)[0]!;
    expect(after.productReady).toBe(false);
    expect(after.nextProductAt).toBe(fx.state.world.dayCount + 1);

    fx.dispatch('animals:collect', { animalId: a.id });
    expect(denied).toHaveLength(1);
    expect(denied[0]!.reason).toBe('not-ready');
  });

  it('collecting cannot overflow the bag (inventory:full)', async () => {
    const fx = await makeFixture();
    buyChicken(fx);
    const a = animalsOf(fx.state)[0]!;
    careFor(fx, a.id, 4);
    const full = fx.capture<any>('inventory:full');
    fx.store.state.player.inventory.slots.fill({ id: 'egg', qty: 999, quality: 0 });
    fx.dispatch('animals:collect', { animalId: a.id });
    expect(full).toHaveLength(1);
    expect(animalsOf(fx.state)[0]!.productReady).toBe(true); // stays ready
  });

  it('quality rolls only improve with a happy, bonded animal', () => {
    const rng = new Rng(12345);
    const low = Array.from({ length: 60 }, () => rollAnimalQuality(rng, 20, 0, 10));
    expect(low.every((q) => q === 0)).toBe(true);
    const r = new Rng(7);
    const some = Array.from({ length: 600 }, () => rollAnimalQuality(r, 90, 9, 10));
    expect(some.includes(2)).toBe(true);
    expect(some.some((q) => q === 1)).toBe(true);
  });
});

describe('products vary by species', () => {
  it('each species produces its own item on its own cadence', async () => {
    const fx = await makeFixture();
    for (const species of ['chicken', 'duck', 'cow', 'goat', 'sheep']) {
      fx.dispatch('animals:buy', { species, qty: 1 });
    }
    const animals = animalsOf(fx.state);
    for (let d = 0; d < 4; d++) {
      for (const a of animals) {
        fx.dispatch('animals:feed', { animalId: a.id });
        fx.dispatch('animals:pet', { animalId: a.id });
      }
      fx.sleep();
    }
    fx.store.state.player.inventory.slots.fill(null); // make room for the goods
    for (const a of animals) fx.dispatch('animals:collect', { animalId: a.id });

    const bag = fx.state.player.inventory.slots
      .filter((s) => s !== null)
      .reduce<Record<string, number>>((acc, s) => ({ ...acc, [s!.id]: (acc[s!.id] ?? 0) + s!.qty }), {});
    expect(bag['egg']).toBe(1);
    expect(bag['duck-egg']).toBe(1);
    expect(bag['milk']).toBe(1);
    expect(bag['goat-milk']).toBe(1);
    expect(bag['wool']).toBe(1);
    expect(readAnimalsExt(fx.state).animals.every((a) => a.productReady === false)).toBe(true);
  });
});

describe('save/load', () => {
  it('the herd round-trips through save/load intact', async () => {
    const fx = await makeFixture();
    buyChicken(fx);
    careFor(fx, 'chicken-1', 4);
    const before = readAnimalsExt(fx.state);

    const restored = migrateSave(parseJson(serializeToJson(wrapSave(fx.store.state)))) as unknown as {
      extensions: Record<string, unknown>;
    };
    const extRaw = restored.extensions[ANIMALS_EXT_ID] as {
      animals: unknown[];
      lastRolledDay: number;
      seq: number;
    };
    expect(extRaw.animals).toHaveLength(1);
    expect(extRaw.lastRolledDay).toBe(before.lastRolledDay);
    expect(extRaw.seq).toBe(1);
    expect((extRaw.animals[0] as { fedToday: boolean }).fedToday).toBe(false);
    expect((extRaw.animals[0] as { productReady: boolean }).productReady).toBe(true);
  });
});