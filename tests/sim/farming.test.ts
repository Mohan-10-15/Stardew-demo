import { describe, expect, it } from 'vitest';
import { createSim } from './harness';

const TILE = { mapId: 'farm', x: 3, y: 3 };

interface HarvestedEvent {
  cropId: string;
  qty: number;
  quality: number;
}
interface PlantedEvent {
  cropId: string;
}
interface WitheredEvent {
  mapId: string;
  x: number;
  y: number;
  cropId: string;
}
interface RejectedEvent {
  reason: string;
}
interface UsedEvent {
  toolId: string;
  effect: string;
}
interface PickedEvent {
  itemId: string;
  qty: number;
}
interface ExhaustedEvent {
  toolId: string;
}

describe('farming sim: till > plant > water > harvest', () => {
  it('grows a parsnip from seed to harvest in 4 watered days', async () => {
    const sim = await createSim();
    const planted = sim.capture<PlantedEvent>('crop:planted');
    const harvested = sim.capture<HarvestedEvent>('crop:harvested');
    const withered = sim.capture<WitheredEvent>('crop:withered');

    sim.useTool(TILE, 'hoe-t0');
    expect(sim.placed('farm', 3, 3)?.id).toBe('tilled');
    expect(sim.energy()).toBe(264);

    sim.useTool(TILE, 'parsnip-seed');
    expect(sim.placed('farm', 3, 3)?.id).toBe('crop:parsnip');
    expect(planted).toHaveLength(1);
    expect(sim.state.player.inventory.slots[7]?.qty).toBe(14);

    let waterings = 0;
    let stage = 0;
    for (let day = 1; day <= 6 && stage < 4; day++) {
      sim.useTool(TILE, 'watering-can-t0');
      waterings += 1;
      sim.sleep();
      stage = Number(sim.cropData('farm', 3, 3)?.stage ?? 0);
    }
    expect(stage).toBe(4);
    expect(waterings).toBeGreaterThanOrEqual(4);
    expect(waterings).toBe(4);
    expect(sim.state.world.dayCount).toBe(5);

    sim.useTool(TILE, '');
    const parsnip = sim.state.player.inventory.slots.find((s) => s !== null && s.id === 'parsnip');
    expect(parsnip).toBeDefined();
    expect(parsnip?.qty).toBe(1);
    expect([0, 1, 2]).toContain(parsnip?.quality);
    expect(harvested).toHaveLength(1);
    expect(harvested[0]?.quality).toBe(parsnip?.quality);
    expect(sim.placed('farm', 3, 3)?.id).toBe('tilled');
    expect(withered).toHaveLength(0);
    expect(sim.energy()).toBe(270);
  });

  it('withers an unwatered crop after two dry days', async () => {
    const sim = await createSim();
    const withered = sim.capture<WitheredEvent>('crop:withered');

    sim.useTool(TILE, 'hoe-t0');
    sim.useTool(TILE, 'parsnip-seed');
    expect(sim.placed('farm', 3, 3)?.id).toBe('crop:parsnip');

    sim.sleep();
    expect(sim.placed('farm', 3, 3)?.id).toBe('crop:parsnip');
    expect(sim.cropData('farm', 3, 3)?.stage).toBe(0);
    expect(sim.cropData('farm', 3, 3)?.missedWater).toBe(1);

    sim.sleep();
    expect(sim.placed('farm', 3, 3)).toBeUndefined();
    expect(withered).toHaveLength(1);
    expect(withered[0]?.cropId).toBe('parsnip');
    expect(withered[0]?.mapId).toBe('farm');
  });

  it('does not grow a crop on a dry day', async () => {
    const sim = await createSim();
    sim.useTool(TILE, 'hoe-t0');
    sim.useTool(TILE, 'parsnip-seed');
    sim.sleep();
    expect(sim.cropData('farm', 3, 3)?.stage).toBe(0);
    sim.useTool(TILE, 'watering-can-t0');
    expect(sim.cropData('farm', 3, 3)?.watered).toBe(true);
    sim.sleep();
    expect(sim.cropData('farm', 3, 3)?.stage).toBe(1);
  });

  it('rejects a wrong-season seed so it never sprouts', async () => {
    const sim = await createSim();
    const rejected = sim.capture<RejectedEvent>('crop:plant-rejected');

    sim.useTool(TILE, 'hoe-t0');
    const seedSlot = sim.giveItem('blueberry-seed', 3);

    sim.useTool(TILE, 'blueberry-seed');
    expect(rejected).toHaveLength(1);
    expect(rejected[0]?.reason).toBe('wrong-season');
    expect(sim.placed('farm', 3, 3)?.id).toBe('tilled');
    expect(sim.state.player.inventory.slots[seedSlot]?.qty).toBe(3);

    sim.plant(TILE, 'blueberry-seed');
    expect(rejected).toHaveLength(2);
    expect(sim.placed('farm', 3, 3)?.id).toBe('tilled');
    expect(sim.state.player.inventory.slots[seedSlot]?.qty).toBe(3);

    sim.sleep();
    expect(sim.placed('farm', 3, 3)?.id).toBe('tilled');
  });

  it('kills crops that fall out of season at rollover (every map)', async () => {
    const sim = await createSim();
    const withered = sim.capture<WitheredEvent>('crop:withered');
    sim.useTool(TILE, 'hoe-t0');
    sim.useTool(TILE, 'parsnip-seed');

    sim.store.state.world.calendar.dayOfMonth = 28;
    sim.sleep();

    expect(sim.state.world.calendar.seasonIndex).toBe(1);
    expect(sim.state.world.calendar.dayOfMonth).toBe(1);
    expect(sim.placed('farm', 3, 3)).toBeUndefined();
    expect(withered).toHaveLength(1);
    expect(withered[0]?.cropId).toBe('parsnip');
  });

  it('charges energy per tool use and refuses when exhausted', async () => {
    const sim = await createSim();
    const exhausted = sim.capture<ExhaustedEvent>('player:exhausted');

    sim.store.state.player.energy = 5;
    sim.useTool(TILE, 'hoe-t0');
    expect(exhausted).toHaveLength(1);
    expect(sim.placed('farm', 3, 3)).toBeUndefined();
    expect(sim.energy()).toBe(5);

    sim.store.state.player.energy = 10;
    sim.useTool(TILE, 'hoe-t0');
    expect(sim.placed('farm', 3, 3)?.id).toBe('tilled');
    expect(sim.energy()).toBe(4);
  });

  it("resolves WORKER-1's tool:use-requested from the bus", async () => {
    const sim = await createSim();
    const used = sim.capture<UsedEvent>('tool:used');
    const watered = sim.capture<{ tile: unknown }>('tile:watered');

    sim.requestTool(TILE, 'hoe-t0');
    expect(sim.placed('farm', 3, 3)?.id).toBe('tilled');
    sim.requestTool(TILE, 'parsnip-seed');
    expect(sim.placed('farm', 3, 3)?.id).toBe('crop:parsnip');
    sim.requestTool(TILE, 'watering-can-t0');
    expect(sim.cropData('farm', 3, 3)?.watered).toBe(true);

    expect(used.map((u) => u.effect)).toEqual(['tilled', 'planted', 'watered']);
    expect(watered).toHaveLength(1);
  });

  it('clears debris with the right tools and yields resources', async () => {
    const sim = await createSim();
    const picked = sim.capture<PickedEvent>('item:picked');

    sim.useTool({ mapId: 'farm', x: 20, y: 6 }, 'axe-t0');
    expect(sim.placed('farm', 20, 6)).toBeUndefined();
    sim.useTool({ mapId: 'farm', x: 22, y: 6 }, 'pickaxe-t0');
    expect(sim.placed('farm', 22, 6)).toBeUndefined();
    sim.useTool({ mapId: 'farm', x: 23, y: 6 }, 'scythe-t0');
    expect(sim.placed('farm', 23, 6)).toBeDefined();
    sim.useTool({ mapId: 'farm', x: 23, y: 6 }, 'axe-t0');
    expect(sim.placed('farm', 23, 6)).toBeUndefined();

    expect(picked.map((p) => p.itemId)).toEqual(['fiber', 'stone', 'wood']);
    const summaryIds = sim.state.player.inventory.slots.map((s) => s?.id);
    expect(summaryIds).toContain('fiber');
    expect(summaryIds).toContain('stone');
    expect(summaryIds).toContain('wood');
  });

  it('tills only tillable, empty soil', async () => {
    const sim = await createSim();
    sim.useTool({ mapId: 'farm', x: 20, y: 6 }, 'axe-t0');
    expect(sim.placed('farm', 20, 6)).toBeUndefined();
    sim.useTool({ mapId: 'farm', x: 20, y: 6 }, 'hoe-t0');
    expect(sim.placed('farm', 20, 6)?.id).toBe('tilled');
    sim.useTool({ mapId: 'farm', x: 20, y: 6 }, 'hoe-t0');
    expect(sim.placed('farm', 20, 6)?.id).toBe('tilled');
    sim.useTool({ mapId: 'farm', x: 10, y: 10 }, 'hoe-t0');
    expect(sim.placed('farm', 10, 10)?.id).toBe('shipping-bin');
  });
});
