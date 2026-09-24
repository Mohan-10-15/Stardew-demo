import { describe, expect, it } from 'vitest';
import { createSim } from './harness';

interface ReportSold {
  itemId: string;
  qty: number;
  gold: number;
}
interface ReportEvent {
  sold: ReportSold[];
  total: number;
}
interface InsertedEvent {
  itemId: string;
  qty: number;
}
interface StartedEvent {
  dayCount: number;
}

describe('shipping box + sleep payout', () => {
  it('insert -> sleep pays out, empties the box and reports', async () => {
    const sim = await createSim();
    const reports = sim.capture<ReportEvent>('shipping:report');
    const inserted = sim.capture<InsertedEvent>('shipping:inserted');
    const started = sim.capture<StartedEvent>('day:started');

    const slot = sim.giveItem('parsnip', 3, 1);
    sim.insertSlot(slot);
    expect(sim.shippingBox()).toHaveLength(1);
    expect(sim.shippingBox()[0]).toEqual({ id: 'parsnip', qty: 3, quality: 1 });
    expect(sim.state.player.inventory.slots[slot]).toBeNull();
    expect(inserted).toHaveLength(1);
    expect(sim.money()).toBe(500);

    const before = sim.state.world.dayCount;
    sim.sleep();

    const expected = Math.round(35 * 3 * 1.25);
    expect(sim.money()).toBe(500 + expected);
    expect(sim.shippingBox()).toHaveLength(0);
    expect(reports).toHaveLength(1);
    expect(reports[0]?.sold).toEqual([{ itemId: 'parsnip', qty: 3, gold: expected }]);
    expect(reports[0]?.total).toBe(expected);
    expect(started).toHaveLength(1);
    expect(sim.state.world.dayCount).toBe(before + 1);
    expect(sim.state.world.clock).toEqual({ hour: 6, minute: 0 });
    expect(sim.energy()).toBe(270);
  });

  it('applies silver x1.25 and gold x1.5 multipliers', async () => {
    const sim = await createSim();
    const reports = sim.capture<ReportEvent>('shipping:report');

    const normal = sim.giveItem('parsnip', 1, 0);
    const silver = sim.giveItem('parsnip', 2, 1);
    const gold = sim.giveItem('parsnip', 4, 2);
    sim.insertSlot(normal);
    sim.insertSlot(silver);
    sim.insertSlot(gold);
    expect(sim.shippingBox()).toHaveLength(3);

    sim.sleep();

    const normalGold = Math.round(35 * 1 * 1);
    const silverGold = Math.round(35 * 2 * 1.25);
    const goldGold = Math.round(35 * 4 * 1.5);
    expect(reports[0]?.sold.map((s) => s.gold)).toEqual([normalGold, silverGold, goldGold]);
    expect(reports[0]?.total).toBe(normalGold + silverGold + goldGold);
    expect(sim.money()).toBe(500 + normalGold + silverGold + goldGold);
  });

  it('merges identical stacks in the box and moves whole stacks out', async () => {
    const sim = await createSim();
    const a = sim.giveItem('wood', 10, 0);
    sim.insertSlot(a);
    const b = sim.giveItem('wood', 5, 0);
    sim.insertSlot(b);
    expect(sim.shippingBox()).toHaveLength(1);
    expect(sim.shippingBox()[0]?.qty).toBe(15);
    expect(sim.state.player.inventory.slots[a]).toBeNull();
    expect(sim.state.player.inventory.slots[b]).toBeNull();
  });

  it('sleeping with an empty box pays nothing but still reports and rolls the day', async () => {
    const sim = await createSim();
    const reports = sim.capture<ReportEvent>('shipping:report');
    sim.sleep();
    expect(reports).toEqual([{ sold: [], total: 0 }]);
    expect(sim.money()).toBe(500);
    expect(sim.state.world.calendar).toEqual({ year: 1, seasonIndex: 0, dayOfMonth: 2 });
    expect(sim.state.world.dayCount).toBe(2);
  });

  it('ignores inserts from empty or out-of-range slots', async () => {
    const sim = await createSim();
    const inserted = sim.capture<InsertedEvent>('shipping:inserted');
    sim.insertSlot(11);
    sim.insertSlot(99);
    expect(sim.shippingBox()).toHaveLength(0);
    expect(inserted).toHaveLength(0);
  });

  it('autosaves money and the cleared box on sleep', async () => {
    const sim = await createSim();
    const slot = sim.giveItem('parsnip', 2, 2);
    sim.insertSlot(slot);
    sim.sleep();
    const saved = await sim.flushPersist();
    expect(saved).not.toBeNull();
    expect(saved?.state.player.money).toBe(500 + Math.round(35 * 2 * 1.5));
    const ext = saved?.state.extensions['farming'] as { shippingBox: unknown[] } | undefined;
    expect(ext?.shippingBox).toEqual([]);
    expect(saved?.state.world.dayCount).toBe(2);
  });
});
