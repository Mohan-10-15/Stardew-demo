import { describe, expect, it } from 'vitest';
import { createSim } from './harness';
import type { ShopExt } from '@game/features/shop/sim/ShopSim';

interface BoughtEvent {
  shopId: string;
  itemId: string;
  qty: number;
  gold: number;
}
interface SoldEvent {
  shopId: string;
  itemId: string;
  qty: number;
  gold: number;
}
interface DeniedEvent {
  reason: string;
  shopId: string;
  itemId: string;
}

function shopStock(sim: { state: { extensions: Record<string, unknown> } }): ShopExt['stock'] {
  const raw = sim.state.extensions['shop'] as Partial<ShopExt> | undefined;
  return raw?.stock ?? {};
}

describe('shopping (shop:sim)', () => {
  it('buys at the price override, deducts money and adds to inventory', async () => {
    const sim = await createSim();
    const bought = sim.capture<BoughtEvent>('shop:bought');
    const denied = sim.capture<DeniedEvent>('shop:denied');

    sim.buy('general-store', 'wood', 5);
    expect(bought).toEqual([{ shopId: 'general-store', itemId: 'wood', qty: 5, gold: 10 }]);
    expect(denied).toHaveLength(0);
    expect(sim.money()).toBe(490);
    const wood = sim.state.player.inventory.slots.find((s) => s !== null && s.id === 'wood');
    expect(wood?.qty).toBe(5);
  });

  it('buys seed at the item buy price through a resolved price', async () => {
    const sim = await createSim();
    sim.buy('general-store', 'parsnip-seed', 1);
    expect(sim.money()).toBe(480); // 500 - 20
    const seeds = sim.state.player.inventory.slots.find((s) => s !== null && s.id === 'parsnip-seed');
    expect(seeds?.qty).toBe(16); // merges with the 15 starter seeds
  });

  it('denies buys beyond daily stock and restocks each morning', async () => {
    const sim = await createSim();
    const denied = sim.capture<DeniedEvent>('shop:denied');
    const restocked = sim.capture<{ dayCount: number }>('shop:restocked');

    for (let i = 0; i < 5; i++) sim.buy('general-store', 'parsnip-seed', 1);
    expect(sim.money()).toBe(400);
    expect(shopStock(sim)['general-store']?.['parsnip-seed']).toBe(0);
    expect(denied).toHaveLength(0);

    sim.buy('general-store', 'parsnip-seed', 1);
    expect(denied).toEqual([
      { reason: 'stock', shopId: 'general-store', itemId: 'parsnip-seed' },
    ]);
    expect(sim.money()).toBe(400);

    sim.sleep();
    expect(shopStock(sim)['general-store']?.['parsnip-seed']).toBe(5);
    expect(restocked).toHaveLength(1);
    sim.buy('general-store', 'parsnip-seed', 5);
    expect(sim.money()).toBe(300);
  });

  it('rejects a whole purchase that exceeds daily stock', async () => {
    const sim = await createSim();
    const denied = sim.capture<DeniedEvent>('shop:denied');
    sim.buy('general-store', 'parsnip-seed', 6);
    expect(denied).toEqual([
      { reason: 'stock', shopId: 'general-store', itemId: 'parsnip-seed' },
    ]);
    expect(sim.money()).toBe(500);
    expect(shopStock(sim)['general-store']?.['parsnip-seed']).toBe(5);
  });

  it('denies when funds are insufficient', async () => {
    const sim = await createSim();
    const denied = sim.capture<DeniedEvent>('shop:denied');
    sim.buy('general-store', 'sword-t0', 3); // 250 each, 750 > 500
    expect(denied).toEqual([{ reason: 'funds', shopId: 'general-store', itemId: 'sword-t0' }]);
    expect(sim.money()).toBe(500);
    // the starter sword is still exactly qty 1 (no purchase went through)
    const sword = sim.state.player.inventory.slots.find((s) => s !== null && s.id === 'sword-t0');
    expect(sword?.qty).toBe(1);
  });

  it('denies when the inventory has no room', async () => {
    const sim = await createSim();
    const denied = sim.capture<DeniedEvent>('shop:denied');
    // occupy every slot with non-stackable tools and drop the starter seeds
    sim.store.state.player.inventory.slots[7] = { id: 'hoe-t0', qty: 1, quality: 0 };
    for (let i = 0; i < 4; i++) sim.giveItem('hoe-t0', 1); // slots 8..11
    sim.buy('general-store', 'parsnip-seed', 1);
    expect(denied).toEqual([
      { reason: 'space', shopId: 'general-store', itemId: 'parsnip-seed' },
    ]);
    expect(sim.money()).toBe(500);
  });

  it('denies unknown goods and zero/negative quantities', async () => {
    const sim = await createSim();
    const denied = sim.capture<DeniedEvent>('shop:denied');
    // rainbow-prism is a real item but this shop does not stock it.
    sim.buy('general-store', 'rainbow-prism', 1);
    sim.buy('general-store', 'wood', 0);
    sim.buy('general-store', 'wood', -2);
    expect(denied).toEqual([
      { reason: 'stock', shopId: 'general-store', itemId: 'rainbow-prism' },
      { reason: 'stock', shopId: 'general-store', itemId: 'wood' },
      { reason: 'stock', shopId: 'general-store', itemId: 'wood' },
    ]);
  });

  it('sells to a buying shop across stacks at base price', async () => {
    const sim = await createSim();
    const sold = sim.capture<SoldEvent>('shop:sold');
    const a = sim.giveItem('parsnip', 3, 0);
    const b = sim.giveItem('parsnip', 2, 1);

    sim.sell('general-store', 'parsnip', 2);
    expect(sim.money()).toBe(570); // 500 + 35*2
    expect(sold).toEqual([{ shopId: 'general-store', itemId: 'parsnip', qty: 2, gold: 70 }]);
    expect(sim.state.player.inventory.slots[a]?.qty).toBe(1);
    expect(sim.state.player.inventory.slots[b]?.qty).toBe(2); // normal stack paid first

    sim.sell('general-store', 'parsnip', 3);
    expect(sim.money()).toBe(675); // 500 + 70 + 105
    expect(sim.state.player.inventory.slots[a]).toBeNull();
    expect(sim.state.player.inventory.slots[b]).toBeNull();
  });

  it('denies selling more than the player owns and to a shop that does not buy', async () => {
    const sim = await createSim();
    const denied = sim.capture<DeniedEvent>('shop:denied');
    sim.giveItem('parsnip', 1, 0);

    sim.sell('general-store', 'parsnip', 2);
    expect(denied).toEqual([
      { reason: 'stock', shopId: 'general-store', itemId: 'parsnip' },
    ]);
    expect(sim.money()).toBe(500);

    sim.giveItem('wood', 1, 0);
    sim.sell('clinic', 'wood', 1);
    expect(denied).toEqual([
      { reason: 'stock', shopId: 'general-store', itemId: 'parsnip' },
      { reason: 'stock', shopId: 'clinic', itemId: 'wood' },
    ]);
    expect(sim.money()).toBe(500);
  });

  it('buys property from a shop that only sells (clinic)', async () => {
    const sim = await createSim();
    sim.buy('clinic', 'wood', 2);
    expect(sim.money()).toBe(494); // 500 - 3*2
    const wood = sim.state.player.inventory.slots.find((s) => s !== null && s.id === 'wood');
    expect(wood?.qty).toBe(2);
  });
});