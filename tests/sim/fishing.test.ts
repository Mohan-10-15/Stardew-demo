/**
 * fishing:sim tests (WORKER-2 sim lane). Uses the real village map, which keeps
 * its water tiles (rows 28-31) because the harness only replaces the farm map.
 * The player stands on village (10,27) (ground) and casts onto (10,28) (water).
 */
import { describe, expect, it } from 'vitest';
import { fishingSim } from '@game/features/fishing/sim/FishingSim';
import { availableFish, readFishingExt } from '@game/features/fishing';
import { wrapSave, serializeToJson, parseJson, migrateSave } from '@game/core/save';
import { mapStateFromDef } from '@game/core/state';
import { createSim, DEFAULT_MODULES, type SimFixture } from './harness';
import { MAX_STACK } from '@game/features/inventory/sim/InventorySim';
import type { WorldPos } from '@game/core/types';

const ROD = 'fishing-rod-t0';
/** Ground tile the player stands on; casting down targets the water below. */
const GROUND_TILE: WorldPos = { mapId: 'village', x: 10, y: 27 };
/** Water: village row 28 is all `w`. */
const WATER_TILE: WorldPos = { mapId: 'village', x: 10, y: 28 };

async function makeFixture(): Promise<SimFixture> {
  const fx = await createSim({ modules: [...DEFAULT_MODULES, fishingSim] });
  const villageDef = fx.content.maps.get('village');
  if (!villageDef) throw new Error('village map missing from content');
  fx.store.state.maps.village = mapStateFromDef(villageDef);
  fx.store.state.player.position = { mapId: 'village', x: GROUND_TILE.x, y: GROUND_TILE.y };
  fx.store.state.player.facing = 'down';
  fx.giveItem(ROD, 1);
  return fx;
}

describe('availableFish gating', () => {
  it('gates on season (walleye is fall-only)', async () => {
    const fx = await makeFixture();
    const s = fx.store.state;
    s.world.clock.hour = 13;
    s.world.clock.minute = 0;
    s.world.weather = 'sun';

    s.world.calendar.seasonIndex = 0;
    expect(availableFish(s, fx.content).some((f) => f.id === 'walleye')).toBe(false);
    s.world.calendar.seasonIndex = 2;
    expect(availableFish(s, fx.content).some((f) => f.id === 'walleye')).toBe(true);
  });

  it('gates on weather (catfish needs rain/storm)', async () => {
    const fx = await makeFixture();
    const s = fx.store.state;
    s.world.clock.hour = 12;
    s.world.clock.minute = 0;
    s.world.calendar.seasonIndex = 1;

    s.world.weather = 'sun';
    expect(availableFish(s, fx.content).some((f) => f.id === 'catfish')).toBe(false);
    s.world.weather = 'rain';
    expect(availableFish(s, fx.content).some((f) => f.id === 'catfish')).toBe(true);
  });

  it('gates on time of day (goldfish is gone by 20:00)', async () => {
    const fx = await makeFixture();
    const s = fx.store.state;
    s.world.calendar.seasonIndex = 3;
    s.world.weather = 'sun';

    s.world.clock.hour = 10;
    expect(availableFish(s, fx.content).some((f) => f.id === 'goldfish')).toBe(true);
    s.world.clock.hour = 20;
    expect(availableFish(s, fx.content).some((f) => f.id === 'goldfish')).toBe(false);
  });

  it('returns the all-season night forager at 23:00 in spring', async () => {
    const fx = await makeFixture();
    const s = fx.store.state;
    s.world.calendar.seasonIndex = 0;
    s.world.weather = 'sun';
    s.world.clock.hour = 23;
    const available = availableFish(s, fx.content);
    expect(available.length).toBeGreaterThan(0);
    expect(available.every((f) => f.seasons === undefined || f.seasons.includes(0))).toBe(true);
  });
});

describe('cast', () => {
  it('creates a waiting session on water and emits fishing:cast', async () => {
    const fx = await makeFixture();
    const casts = fx.capture<any>('fishing:cast');
    const fails = fx.capture<any>('tool:failed');

    fx.requestTool(WATER_TILE, ROD);

    expect(fails).toHaveLength(0);
    expect(casts).toHaveLength(1);
    expect(casts[0]!.tile).toEqual({ mapId: 'village', x: 10, y: 28 });

    const ext = readFishingExt(fx.store.state);
    expect(ext.session).not.toBeNull();
    expect(ext.session!.phase).toBe('waiting');
    expect(ext.session!.mapId).toBe('village');
    expect(ext.session!.x).toBe(10);
    expect(ext.session!.y).toBe(28);
    expect(fx.content.fish.get(ext.session!.fishId)).toBeDefined();
  });

  it('rejects a cast on solid ground with tool:failed not-water', async () => {
    const fx = await makeFixture();
    const fails = fx.capture<any>('tool:failed');
    const casts = fx.capture<any>('fishing:cast');

    fx.requestTool(GROUND_TILE, ROD);

    expect(casts).toHaveLength(0);
    expect(fails).toHaveLength(1);
    expect(fails[0]!.reason).toBe('not-water');
    expect(readFishingExt(fx.store.state).session).toBeNull();
  });

  it('does not spend energy — farming:sim ignores rod tools', async () => {
    const fx = await makeFixture();
    const before = fx.energy();
    fx.requestTool(WATER_TILE, ROD);
    expect(fx.energy()).toBe(before);
    expect(readFishingExt(fx.store.state).session).not.toBeNull();
    // A rod press while the line is out is a reel (cancel here) — still free.
    fx.requestTool(WATER_TILE, ROD);
    expect(fx.energy()).toBe(before);
    expect(readFishingExt(fx.store.state).session).toBeNull();
  });

  it('emits fishing:no-fish when no species is available at 03:00 winter', async () => {
    const fx = await makeFixture();
    const s = fx.store.state;
    s.world.calendar.seasonIndex = 3;
    s.world.weather = 'sun';
    s.world.clock.hour = 3;
    const noFish = fx.capture<any>('fishing:no-fish');

    fx.requestTool(WATER_TILE, ROD);

    expect(noFish).toHaveLength(1);
    expect(noFish[0]!.reason).toBe('no-fish-now');
    expect(readFishingExt(fx.store.state).session).toBeNull();
  });

  it('round-trips a waiting session through save/load', async () => {
    const fx = await makeFixture();
    fx.requestTool(WATER_TILE, ROD);
    const session = readFishingExt(fx.store.state).session!;

    const restored = migrateSave(parseJson(serializeToJson(wrapSave(fx.store.state))));
    const ext = readFishingExt(restored);
    expect(ext.session).not.toBeNull();
    expect(ext.session!.fishId).toBe(session.fishId);
    expect(ext.session!.phase).toBe('waiting');
    expect(ext.session!.castDay).toBe(session.castDay);
  });
});

describe('bite -> reel -> catch', () => {
  it('bites, catches, adds the fish to the inventory and grants XP', async () => {
    const fx = await makeFixture();
    fx.store.state.player.inventory.slots.fill(null);
    const bites = fx.capture<any>('fishing:bite');
    const caught = fx.capture<any>('fishing:caught');

    fx.requestTool(WATER_TILE, ROD);
    const session = readFishingExt(fx.store.state).session!;

    // Advance until the bite lands (bite offset is castAt + 10..89 minutes).
    let guard = 0;
    while (readFishingExt(fx.store.state).session?.phase === 'waiting') {
      fx.tickMinutes(10);
      if (++guard > 15) throw new Error('bite never landed within 150 minutes');
    }

    expect(bites).toHaveLength(1);
    expect(bites[0]!.fishId).toBe(session.fishId);
    const hookExt = readFishingExt(fx.store.state);
    expect(hookExt.session!.phase).toBe('hook');

    fx.requestTool(WATER_TILE, ROD); // reel
    expect(caught).toHaveLength(1);
    expect(caught[0]!.fishId).toBe(session.fishId);
    expect(caught[0]!.quality).toBeGreaterThanOrEqual(0);
    expect(caught[0]!.xp).toBeGreaterThanOrEqual(1);
    expect(caught[0]!.tile).toEqual({ mapId: 'village', x: 10, y: 28 });
    expect(readFishingExt(fx.store.state).session).toBeNull();

    const fish = fx.content.fish.get(session.fishId)!;
    const item = fx.content.items.get(fish.itemId)!;
    const stack = fx.store.state.player.inventory.slots.find((s) => s?.id === fish.itemId);
    expect(stack).not.toBeUndefined();
    expect(stack!.qty).toBe(1);
    expect(item.category).toBe('fish');

    const stats = fx.store.state.player.stats;
    expect(stats[`day:caught:${fish.itemId}`]).toBe(1);
    expect(stats['day:xp:fishing']).toBe(fish.xp);
  });

  it('reeling while waiting just pulls the line back', async () => {
    const fx = await makeFixture();
    const cancels = fx.capture<any>('fishing:reel-cancel');
    const caught = fx.capture<any>('fishing:caught');
    fx.store.state.player.inventory.slots.fill(null);

    fx.requestTool(WATER_TILE, ROD);
    fx.requestTool(WATER_TILE, ROD); // reel immediately

    expect(cancels).toHaveLength(1);
    expect(caught).toHaveLength(0);
    expect(readFishingExt(fx.store.state).session).toBeNull();
    expect(fx.store.state.player.inventory.slots.every((s) => s === null)).toBe(true);
  });

  it('a fish escapes (too-slow) when the 30-minute hook window lapses', async () => {
    const fx = await makeFixture();
    const escaped = fx.capture<any>('fishing:escaped');
    const caught = fx.capture<any>('fishing:caught');

    fx.requestTool(WATER_TILE, ROD);
    let guard = 0;
    while (readFishingExt(fx.store.state).session?.phase === 'waiting') {
      fx.tickMinutes(10);
      if (++guard > 15) throw new Error('bite never landed');
    }
    fx.tickMinutes(30); // exactly hookAt + 30

    expect(escaped).toHaveLength(1);
    expect(escaped[0]!.reason).toBe('too-slow');
    expect(caught).toHaveLength(0);
    expect(readFishingExt(fx.store.state).session).toBeNull();
  });

  it('escapes with reason inventory-full when every slot is taken', async () => {
    const fx = await makeFixture();
    const escaped = fx.capture<any>('fishing:escaped');
    const caught = fx.capture<any>('fishing:caught');

    fx.requestTool(WATER_TILE, ROD);
    const session = readFishingExt(fx.store.state).session!;
    const fish = fx.content.fish.get(session.fishId)!;
    fx.store.state.player.inventory.slots.fill({ id: fish.itemId, qty: MAX_STACK, quality: 0 });

    let guard = 0;
    while (readFishingExt(fx.store.state).session?.phase === 'waiting') {
      fx.tickMinutes(10);
      if (++guard > 15) throw new Error('bite never landed');
    }
    fx.requestTool(WATER_TILE, ROD);

    expect(escaped).toHaveLength(1);
    expect(escaped[0]!.reason).toBe('inventory-full');
    expect(caught).toHaveLength(0);
    expect(readFishingExt(fx.store.state).session).toBeNull();
  });
});

describe('day boundary', () => {
  it('clears a stale session on sleep with reason day-end', async () => {
    const fx = await makeFixture();
    const escaped = fx.capture<any>('fishing:escaped');

    fx.requestTool(WATER_TILE, ROD);
    expect(readFishingExt(fx.store.state).session).not.toBeNull();
    fx.sleep();

    expect(escaped.some((e) => e.reason === 'day-end')).toBe(true);
    expect(readFishingExt(fx.store.state).session).toBeNull();
  });
});