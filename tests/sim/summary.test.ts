import { describe, expect, it } from 'vitest';
import { createSim } from './harness';
import type { DaySummaryPayload } from '@game/features/farming/sim/summary';

const TILE = { mapId: 'farm', x: 3, y: 3 };

type FarmForageEntry = { id: string };

function farmForageTiles(sim: {
  state: { maps: Record<string, { placed: Record<string, FarmForageEntry> }> };
}): [string, FarmForageEntry][] {
  const placed = sim.state.maps['farm']?.placed ?? {};
  return Object.entries(placed).filter(([, obj]) => obj.id.startsWith('forage:'));
}

describe('end-of-day summary (day:summary)', () => {
  it('emits exactly one summary per sleep with the day content', async () => {
    const sim = await createSim();
    const summaries = sim.capture<DaySummaryPayload>('day:summary');
    const farm = sim.store.state.maps['farm'];
    expect(farm).toBeDefined();
    if (!farm) throw new Error('farm map missing');

    // Day 1 morning content: a mature crop, seeds on hand, a forage to pick.
    farm.placed[`${TILE.x},${TILE.y}`] = {
      id: 'crop:parsnip',
      x: TILE.x,
      y: TILE.y,
      data: { stage: 3, grownDays: 3, watered: false, missedWater: 0 },
    };
    sim.sleepWithWeather('sun'); // night 1: forage spawns, summary #1 (empty day 1)

    expect(summaries).toHaveLength(1);
    expect(summaries[0]?.dayCount).toBe(1);

    // Day 2: harvest, forage pick, ship a parsnip. (Re-fetch: the rollover
    // replaced the farm map object.)
    const farmDay2 = sim.store.state.maps['farm'];
    if (!farmDay2) throw new Error('farm map missing');
    farmDay2.placed[`${TILE.x},${TILE.y}`] = {
      id: 'crop:parsnip',
      x: TILE.x,
      y: TILE.y,
      data: { stage: 4, grownDays: 4, watered: false, missedWater: 0 },
    };
    sim.useTool(TILE, ''); // bare-hand harvest
    const forage = farmForageTiles(sim)[0];
    const forageTile = forage
      ? { mapId: 'farm' as const, x: Number(forage[0].split(',')[0]), y: Number(forage[0].split(',')[1]) }
      : null;
    if (forageTile) sim.useTool(forageTile, ''); // bare-hand forage pickup

    const parsnip = sim.giveItem('parsnip', 1, 0);
    sim.insertSlot(parsnip);
    sim.sleepWithWeather('sun'); // night 2: payout + close day 2

    expect(summaries).toHaveLength(2);
    const day2 = summaries[1];
    expect(day2?.dayCount).toBe(2);
    expect(day2?.date).toEqual({ year: 1, seasonIndex: 0, dayOfMonth: 2 });
    expect(day2?.weather).toBe('sun');
    expect(day2?.itemsSold).toEqual([{ itemId: 'parsnip', qty: 1, gold: 35 }]);
    expect(day2?.goldEarned).toBe(35);
    expect(day2?.cropsHarvested).toEqual([{ cropId: 'parsnip', qty: 1 }]);
    expect(day2?.collectedForage).toHaveLength(1);
    const forageRow = day2?.collectedForage[0];
    expect(['daffodil', 'leek', 'wild-horseradish', 'common-mushroom', 'ember-bloom']).toContain(
      forageRow?.itemId,
    );
    expect(forageRow?.qty).toBe(1);
    expect(day2?.xpEarned).toContainEqual({ skill: 'farming', amount: 12 });
    expect(day2?.xpEarned).toContainEqual({ skill: 'foraging', amount: 5 });
  });

  it('includes shop sales in the day totals and resets the counters', async () => {
    const sim = await createSim();
    const summaries = sim.capture<DaySummaryPayload>('day:summary');

    sim.giveItem('parsnip', 2, 0);
    sim.sell('general-store', 'parsnip', 2); // +70
    sim.sleepWithWeather('sun');

    const day1 = summaries[0];
    expect(day1?.goldEarned).toBe(70);
    expect(day1?.itemsSold).toEqual([{ itemId: 'parsnip', qty: 2, gold: 70 }]);
    // Counters reset after the close.
    expect(sim.state.player.stats['day:gold']).toBeUndefined();
    expect(sim.state.player.stats['day:sold:parsnip']).toBeUndefined();
  });

  it('emits a summary too on a forced pass-out (2:00 AM)', async () => {
    const sim = await createSim();
    const summaries = sim.capture<DaySummaryPayload>('day:summary');
    const started = sim.capture('day:started');

    const parsnip = sim.giveItem('parsnip', 1, 0);
    sim.insertSlot(parsnip);
    sim.store.state.world.clock = { hour: 1, minute: 50 };
    sim.tickStep();

    expect(summaries).toHaveLength(1);
    expect(summaries[0]?.dayCount).toBe(1);
    expect(summaries[0]?.itemsSold).toEqual([{ itemId: 'parsnip', qty: 1, gold: 35 }]);
    expect(summaries[0]?.goldEarned).toBe(35);
    expect(started).toHaveLength(0);
  });

  it('never re-emits for the same day (no double close)', async () => {
    const sim = await createSim();
    const summaries = sim.capture<DaySummaryPayload>('day:summary');

    sim.sleepWithWeather('sun');
    sim.tickMinutes(120); // still the same morning
    sim.tickStep(); // not passed out
    expect(summaries).toHaveLength(1);

    sim.sleepWithWeather('sun');
    expect(summaries).toHaveLength(2);
    expect(summaries[1]?.dayCount).toBe(2);
  });
});