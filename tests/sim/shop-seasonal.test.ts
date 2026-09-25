import { describe, expect, it } from 'vitest';
import { createSim, type SimFixture } from './harness';
import type { ShopExt } from '@game/features/shop/sim/ShopSim';

interface DeniedEvent {
  reason: string;
  shopId: string;
  itemId: string;
}

function shopExt(sim: SimFixture): ShopExt {
  return sim.state.extensions['shop'] as unknown as ShopExt;
}

function merchantAvailable(sim: SimFixture): Record<string, boolean> {
  return shopExt(sim).seasonStock['traveling-merchant'] ?? {};
}

async function merchantStockSet(sim: SimFixture): Promise<string[]> {
  const availability = merchantAvailable(sim);
  return Object.entries(availability)
    .filter(([, ok]) => ok)
    .map(([id]) => id);
}

describe('seasonal shop stock (shop:sim)', () => {
  it('keeps the traveling merchant closed from spring Monday to Friday', async () => {
    const sim = await createSim();
    const denied = sim.capture<DeniedEvent>('shop:denied');
    sim.buy('traveling-merchant', 'amethyst', 1);
    expect(denied).toEqual([
      { reason: 'closed', shopId: 'traveling-merchant', itemId: 'amethyst' },
    ]);
    expect(sim.money()).toBe(500);
    expect(shopExt(sim).merchantToday).toBe(false);
  });

  it('opens the traveling merchant on Fridays with a seeded 4-item rotation', async () => {
    const sim = await createSim();
    for (let i = 0; i < 5; i++) sim.sleep(); // day 6 = friday
    const denied = sim.capture<DeniedEvent>('shop:denied');

    expect(shopExt(sim).merchantToday).toBe(true);
    const offered = await merchantStockSet(sim);
    expect(offered).toHaveLength(4);
    for (const id of offered) {
      expect(['amethyst', 'emerald', 'topaz', 'opal', 'chocolate', 'rainbow-prism', 'strawberry-seed', 'hot-pepper-seed']).toContain(id);
    }

    const pick = offered[0]!;
    sim.buy('traveling-merchant', pick, 1);
    expect(shopExt(sim).stock['traveling-merchant']?.[pick]).toBe(0);
    sim.buy('traveling-merchant', pick, 2);
    expect(denied).toEqual([
      { reason: 'stock', shopId: 'traveling-merchant', itemId: pick },
    ]);
  });

  it('rotates the merchant stock deterministically by seed', async () => {
    const a = await createSim();
    const b = await createSim(Object.assign({}, { seed: 20260924 }));
    const c = await createSim({ seed: 987654321 });
    for (let i = 0; i < 5; i++) {
      a.sleep();
      b.sleep();
      c.sleep();
    }
    expect(await merchantStockSet(a)).toEqual(await merchantStockSet(b));
    const cSet = await merchantStockSet(c);
    expect(cSet).toHaveLength(4);
    expect(await merchantStockSet(a)).toHaveLength(4);
  });

  it('closes the merchant again once Friday passes', async () => {
    const sim = await createSim();
    for (let i = 0; i < 6; i++) sim.sleep(); // saturday
    const denied = sim.capture<DeniedEvent>('shop:denied');
    sim.buy('traveling-merchant', 'amethyst', 1);
    expect(denied[0]).toMatchObject({ reason: 'closed', shopId: 'traveling-merchant' });
    expect(shopExt(sim).merchantToday).toBe(false);
  });

  it('gates seed-shop and general-store stock by season', async () => {
    const sim = await createSim();
    // Spring (season 0): cauliflower-seed (spring only) is on sale, blueberry-seed is not.
    sim.buy('seed-shop', 'cauliflower-seed', 1);
    expect(sim.money()).toBe(500 - 55);
    const springDenied = sim.capture<DeniedEvent>('shop:denied');
    sim.buy('seed-shop', 'blueberry-seed', 1);
    expect(springDenied).toEqual([
      { reason: 'stock', shopId: 'seed-shop', itemId: 'blueberry-seed' },
    ]);

    // Summer (season 1): cauliflower-seed and general-store parsnip-seed leave stock,
    // blueberry-seed and seasonless tomato-seed arrive. The capture replays the
    // spring blueberry denial from the event buffer, so match the two summer rows.
    const summerDenied = sim.capture<DeniedEvent>('shop:denied');
    for (let i = 0; i < 28; i++) sim.sleep();
    sim.buy('seed-shop', 'cauliflower-seed', 1);
    sim.buy('general-store', 'parsnip-seed', 1);
    const row = (d: DeniedEvent): string => `${d.reason}:${d.shopId}:${d.itemId}`;
    expect(summerDenied.map(row)).toEqual(
      expect.arrayContaining(['stock:seed-shop:cauliflower-seed', 'stock:general-store:parsnip-seed']),
    );
    sim.buy('seed-shop', 'blueberry-seed', 2);
    expect(sim.money()).toBe(500 - 55 - 2 * 80);
    sim.buy('seed-shop', 'tomato-seed', 2);
    expect(sim.state.player.inventory.slots.find((s) => s !== null && s.id === 'tomato-seed')?.qty).toBe(2);
  });
});