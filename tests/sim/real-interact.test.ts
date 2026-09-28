/**
 * T-0502 — every WORKER-2 sim feature driven through the REAL input path.
 *
 * The bug this file exists for: `tool:use-requested` used to carry a tile with
 * no `mapId`, so in the running game every single tool swing failed with reason
 * 'no-map' while 300+ unit tests stayed green, because every one of them
 * dispatched `farming:tool-use` / `fishing:cast` / `machines:insert` directly
 * and hand-built a `WorldPos` the product never builds.
 *
 * So: nothing in here dispatches an internal action to *cause* a tool effect.
 * Every effect is produced by `standAt()` + `interactFront()`, which is exactly
 * what pressing Space/E/clicking the world does. Internal reducers are still
 * used for pure time advancement (`time:tick`) and day close (`player:sleep`),
 * both of which the real game drives on a timer.
 */
import { describe, expect, it } from 'vitest';
import { createSim, DEFAULT_MODULES, type SimFixture } from './harness';
import { fishingSim, readFishingExt } from '@game/features/fishing/sim/FishingSim';
import { craftingSim } from '@game/features/crafting/sim/CraftingSim';
import { machinesSim } from '@game/features/machines/sim/MachinesSim';
import { skillsSim, skillLevelOf, skillXpOf } from '@game/features/skills/sim/SkillsSim';
import type { ToolFailedEvent, ToolUsedEvent } from '@game/features/farming/sim/FarmingSim';
import { FORAGE_XP, HARVEST_XP } from '@game/features/farming/sim/summary';
import { tileKey } from '@game/features/farming/sim/utils';
import type { FeatureModule } from '@game/core/feature';
import type { Facing, WorldPos } from '@game/core/types';

type Tile = { x: number; y: number };

const MAP = 'farm';

async function fx(mods: readonly FeatureModule[] = []): Promise<SimFixture> {
  return createSim({ seed: 20260926, modules: [...DEFAULT_MODULES, ...mods] });
}

/** Stand one tile from `target` and swing at it. Returns the resolved front tile. */
function swingNeighbour(f: SimFixture, target: Tile, from: Tile, facing: Facing): WorldPos {
  expect({
    x: from.x + (facing === 'right' ? 1 : facing === 'left' ? -1 : 0),
    y: from.y + (facing === 'down' ? 1 : facing === 'up' ? -1 : 0),
  }).toEqual(target);
  f.standAt(MAP, from.x, from.y, facing);
  return f.interactFront();
}

// ===========================================================================
describe('tool:use-requested carries a resolvable map from the real emitter', () => {
  it('names the map, the front tile and the held tool for every facing', async () => {
    const f = await fx();
    f.holdItem('hoe-t0');
    const cases: Array<[Tile, Facing, Tile]> = [
      [{ x: 4, y: 4 }, 'up', { x: 4, y: 3 }],
      [{ x: 4, y: 4 }, 'down', { x: 4, y: 5 }],
      [{ x: 4, y: 4 }, 'left', { x: 3, y: 4 }],
      [{ x: 4, y: 4 }, 'right', { x: 5, y: 4 }],
    ];
    for (const [stand, facing, want] of cases) {
      f.standAt(MAP, stand.x, stand.y, facing);
      const payload = f.interactPayload();
      expect(payload.toolId, `held tool for ${facing}`).toBe('hoe-t0');
      expect(payload.tile, `payload for ${facing}`).toEqual({ mapId: MAP, x: want.x, y: want.y });
    }
  });

  it('reports a bare "hand" toolId when the hotbar slot is empty', async () => {
    const f = await fx();
    for (let i = 0; i < f.state.player.inventory.slots.length; i++) f.setSlot(i, null);
    f.holdHands();
    f.standAt(MAP, 6, 6, 'up');
    expect(f.interactPayload().toolId).toBe('hand');
  });

  it('never emits a tool:failed with reason no-map (the original symptom)', async () => {
    const f = await fx([machinesSim, fishingSim]);
    f.installMap(MAP);
    // Registered up front: EventBus replays its buffer to late subscribers, so a
    // listener attached after the swings would see the failures as history.
    const failed: ToolFailedEvent[] = [];
    f.bus.on<ToolFailedEvent>('tool:failed', (p) => failed.push(p));
    // Walk the starter kit over real authored terrain: tillable grass, each kind
    // of debris, water, and the shipping bin. Every farming/machines/fishing
    // subscriber sees a payload that resolves a map.
    f.holdItem('hoe-t0');
    swingNeighbour(f, { x: 6, y: 6 }, { x: 6, y: 7 }, 'up'); // tillable grass
    f.holdItem('axe-t0');
    swingNeighbour(f, { x: 22, y: 6 }, { x: 22, y: 7 }, 'up'); // weed
    f.holdItem('scythe-t0');
    swingNeighbour(f, { x: 20, y: 3 }, { x: 20, y: 4 }, 'up'); // weed
    f.holdItem('pickaxe-t0');
    swingNeighbour(f, { x: 29, y: 3 }, { x: 29, y: 4 }, 'up'); // rock
    f.holdItem('axe-t0');
    swingNeighbour(f, { x: 5, y: 8 }, { x: 5, y: 9 }, 'up'); // shipping bin
    f.holdItem('fishing-rod-t0');
    swingNeighbour(f, { x: 13, y: 12 }, { x: 13, y: 11 }, 'down'); // pond

    expect(
      failed.map((e) => e.reason),
      'no swing may die on a missing map',
    ).not.toContain('no-map');
    expect(
      failed.every((e) => e.tile?.mapId === MAP),
      'every failure still names a map',
    ).toBe(true);
  });

  it('drops a mapless tile instead of throwing or half-acting on it', async () => {
    const f = await fx([machinesSim, fishingSim]);
    const failed: ToolFailedEvent[] = [];
    f.bus.on<ToolFailedEvent>('tool:failed', (p) => failed.push(p));
    const before = f.state;
    const placedBefore = Object.keys(f.state.maps[MAP]!.placed).length;
    const energyBefore = f.energy();
    // The bus is loosely typed, so a hostile payload must be inert, not fatal.
    // Each of these WOULD do something if the mapId were there.
    f.bus.emit('tool:use-requested', { tile: { x: 5, y: 5 }, toolId: 'hoe-t0' });
    f.bus.emit('tool:use-requested', { tile: { x: 5, y: 5 }, toolId: 'mayonnaise-machine' });
    f.bus.emit('tool:use-requested', { tile: { x: 5, y: 5 }, toolId: 'fishing-rod-t0' });
    f.bus.emit('tool:use-requested', { tile: { x: 5, y: 5 } });
    f.bus.emit('tool:use-requested', null);
    f.bus.emit('tool:use-requested', undefined);
    expect(f.state, 'a mapless tile must not act on any map').toBe(before);
    expect(Object.keys(f.state.maps[MAP]!.placed), 'nothing may be placed').toHaveLength(
      placedBefore,
    );
    expect(f.energy(), 'nothing may cost energy').toBe(energyBefore);
    expect(readFishingExt(f.state).session, 'no cast may start').toBeNull();
    expect(failed, 'a malformed tile is not a gameplay failure to announce').toHaveLength(0);
  });
});

// ===========================================================================
describe('farming through player:interact', () => {
  it('tills, plants, waters, and harvests — the whole loop, no cheats', async () => {
    const f = await fx();
    const target = { x: 4, y: 4 };
    const used: ToolUsedEvent[] = [];
    f.bus.on<ToolUsedEvent>('tool:used', (e) => used.push(e));

    f.holdItem('hoe-t0');
    expect(swingNeighbour(f, target, { x: 4, y: 5 }, 'up')).toEqual({ mapId: MAP, x: 4, y: 4 });
    expect(f.placed(MAP, 4, 4)?.id).toBe('tilled');
    expect(used.at(-1)?.effect).toBe('tilled');

    f.holdItem('parsnip-seed');
    swingNeighbour(f, target, { x: 4, y: 5 }, 'up');
    expect(f.placed(MAP, 4, 4)?.id).toBe('crop:parsnip');

    f.holdItem('watering-can-t0');
    swingNeighbour(f, target, { x: 4, y: 5 }, 'up');
    expect(f.cropData(MAP, 4, 4)?.['watered']).toBe(true);
    expect(used.at(-1)?.effect).toBe('watered');

    // parsnip: 4 watered nights -> mature.
    for (let night = 0; night < 4; night++) {
      swingNeighbour(f, target, { x: 4, y: 5 }, 'up');
      f.sleepWithWeather('sun');
    }
    expect(f.cropData(MAP, 4, 4)?.['stage']).toBe(4);

    f.holdHands(); // crops are only pickable with bare hands
    swingNeighbour(f, target, { x: 4, y: 5 }, 'up');
    expect(f.state.player.inventory.slots.some((s) => s?.id === 'parsnip')).toBe(true);
    expect(used.at(-1)?.effect).toBe('harvested');
  });

  it('clears a weed with the axe and a rock with the pickaxe', async () => {
    const f = await fx();
    const cleared: ToolUsedEvent[] = [];
    f.bus.on<ToolUsedEvent>('tool:used', (e) => cleared.push(e));

    f.holdItem('axe-t0');
    swingNeighbour(f, { x: 20, y: 6 }, { x: 20, y: 7 }, 'up');
    expect(f.placed(MAP, 20, 6)).toBeUndefined();
    expect(cleared.at(-1)).toMatchObject({ toolId: 'axe-t0', effect: 'cleared' });
    expect(f.state.player.inventory.slots.some((s) => s?.id === 'fiber')).toBe(true);

    f.holdItem('pickaxe-t0');
    swingNeighbour(f, { x: 22, y: 6 }, { x: 22, y: 7 }, 'up');
    expect(f.placed(MAP, 22, 6)).toBeUndefined();
    expect(cleared.at(-1)).toMatchObject({ toolId: 'pickaxe-t0', effect: 'cleared' });
    expect(f.state.player.inventory.slots.some((s) => s?.id === 'stone')).toBe(true);
  });

  it('picks a forage item with bare hands off a real forage tile', async () => {
    const f = await fx();
    f.state.maps[MAP]!.placed[tileKey(8, 8)] = { id: 'forage:daffodil', x: 8, y: 8, data: {} };
    const used: ToolUsedEvent[] = [];
    f.bus.on<ToolUsedEvent>('tool:used', (e) => used.push(e));
    f.holdHands();
    swingNeighbour(f, { x: 8, y: 8 }, { x: 8, y: 9 }, 'up');
    expect(f.placed(MAP, 8, 8)).toBeUndefined();
    expect(f.state.player.inventory.slots.some((s) => s?.id === 'daffodil')).toBe(true);
    expect(used.at(-1)?.effect).toBe('cleared');
    expect(f.state.player.stats['day:xp:foraging']).toBe(FORAGE_XP);
  });

  it('reports the real reason on a blocked tile, not a map error', async () => {
    const f = await fx();
    const failed: ToolFailedEvent[] = [];
    f.bus.on<ToolFailedEvent>('tool:failed', (p) => failed.push(p));
    f.holdItem('axe-t0');
    swingNeighbour(f, { x: 4, y: 4 }, { x: 4, y: 5 }, 'up');
    expect(failed).toHaveLength(1);
    expect(failed[0]!.reason).toBe('no-debris');
  });
});

// ===========================================================================
describe('machines through player:interact (T-0502)', () => {
  const SPOT = { x: 6, y: 6 };
  const STAND = { x: 6, y: 7 };

  it('places, loads, ticks and collects — every step a real Space press', async () => {
    const f = await fx([machinesSim]);
    const placed: unknown[] = [];
    const loaded: unknown[] = [];
    const collected: unknown[] = [];
    const denied: Array<{ reason: string }> = [];
    f.bus.on('machines:placed', (p) => placed.push(p));
    f.bus.on('machines:loaded', (p) => loaded.push(p));
    f.bus.on('machines:collected', (p) => collected.push(p));
    f.bus.on<{ reason: string }>('machines:denied', (p) => denied.push(p));

    // 1. Crafted machine item in hand, bare walkable tile in front -> placed.
    f.giveItem('mayonnaise-machine', 1);
    f.holdItem('mayonnaise-machine');
    const front = swingNeighbour(f, SPOT, STAND, 'up');
    expect(front).toEqual({ mapId: MAP, x: SPOT.x, y: SPOT.y });
    expect(placed).toEqual([{ tile: front, machineId: 'mayonnaise-machine' }]);
    expect(f.placed(MAP, SPOT.x, SPOT.y)?.id).toBe('machine:mayonnaise-machine');
    expect(f.state.player.inventory.slots.some((s) => s?.id === 'mayonnaise-machine')).toBe(false);
    expect(denied, 'farming must not fight the placement').toHaveLength(0);

    // 2. Egg selected, same tile -> loaded from the hotbar, exactly like play.
    f.giveItem('egg', 2);
    f.holdItem('egg');
    swingNeighbour(f, SPOT, STAND, 'up');
    expect(loaded).toHaveLength(1);
    expect(f.cropData(MAP, SPOT.x, SPOT.y)).toMatchObject({
      machineId: 'mayonnaise-machine',
      loaded: 1,
      remainingTicks: 18,
    });

    // 3. Still working -> busy, product stays in the machine.
    swingNeighbour(f, SPOT, STAND, 'up');
    expect(denied.at(-1)?.reason).toBe('busy');
    expect(collected).toHaveLength(0);

    // 4. Three in-game hours later -> collect into the bag.
    f.tickMinutes(3 * 60);
    f.holdItem('scythe-t0'); // any held item; the machine claims the tile
    swingNeighbour(f, SPOT, STAND, 'up');
    expect(collected).toHaveLength(1);
    expect(f.state.player.inventory.slots.some((s) => s?.id === 'mayonnaise')).toBe(true);
    expect(f.cropData(MAP, SPOT.x, SPOT.y)).toMatchObject({ loaded: 0, remainingTicks: 0 });
  });

  it('farming stays out of the way on a machine tile', async () => {
    const f = await fx([machinesSim]);
    const failed: ToolFailedEvent[] = [];
    const used: ToolUsedEvent[] = [];
    f.bus.on<ToolFailedEvent>('tool:failed', (p) => failed.push(p));
    f.bus.on<ToolUsedEvent>('tool:used', (p) => used.push(p));
    f.giveItem('mayonnaise-machine', 1);
    f.holdItem('mayonnaise-machine');
    swingNeighbour(f, SPOT, STAND, 'up');
    // A machine tile is not soil: the hoe must not till it, and no failure may
    // reach audio/UI for an interaction machines:sim owns.
    f.holdItem('hoe-t0');
    swingNeighbour(f, SPOT, STAND, 'up');
    expect(used).toHaveLength(0);
    expect(failed).toHaveLength(0);
    expect(f.placed(MAP, SPOT.x, SPOT.y)?.id).toBe('machine:mayonnaise-machine');
  });

  it('refuses to place a machine on occupied or unwalkable ground', async () => {
    const f = await fx([machinesSim]);
    f.installMap(MAP); // the synthetic farm is all grass: nothing is unwalkable
    const denied: Array<{ reason: string }> = [];
    f.bus.on<{ reason: string }>('machines:denied', (p) => denied.push(p));
    f.giveItem('mayonnaise-machine', 2);
    f.holdItem('mayonnaise-machine');

    swingNeighbour(f, { x: 5, y: 8 }, { x: 5, y: 9 }, 'up'); // shipping bin
    expect(denied.at(-1)?.reason).toBe('occupied');

    f.state.player.energy = 0; // irrelevant, kept explicit: energy is not the gate
    swingNeighbour(f, { x: 14, y: 12 }, { x: 14, y: 11 }, 'down'); // pond
    expect(denied.at(-1)?.reason).toBe('blocked');
    expect(f.state.player.inventory.slots.some((s) => s?.id === 'mayonnaise-machine')).toBe(true);
  });
});

// ===========================================================================
describe('fishing through player:interact (T-0502)', () => {
  // The authored farm pond: rows 12-16, columns 12-17 are water.
  const SHORE = { x: 13, y: 11 };
  const WATER = { x: 13, y: 12 };

  async function rod(): Promise<SimFixture> {
    const f = await fx([fishingSim]);
    f.installMap(MAP); // the synthetic harness farm has no pond
    f.holdItem('fishing-rod-t0');
    return f;
  }

  it('casts onto real water from a real Space press, and the tile resolves', async () => {
    const f = await rod();
    const casts: Array<{ tile: WorldPos; toolId: string; fishId: string }> = [];
    const failed: ToolFailedEvent[] = [];
    f.bus.on<{ tile: WorldPos; toolId: string; fishId: string }>('fishing:cast', (p) =>
      casts.push(p),
    );
    f.bus.on<ToolFailedEvent>('tool:failed', (p) => failed.push(p));

    const front = swingNeighbour(f, WATER, SHORE, 'down');

    expect(front).toEqual({ mapId: MAP, x: WATER.x, y: WATER.y });
    expect(failed).toHaveLength(0);
    expect(casts).toHaveLength(1);
    expect(casts[0]!.tile).toEqual({ mapId: MAP, x: WATER.x, y: WATER.y });
    expect(f.content.fish.has(casts[0]!.fishId)).toBe(true);
    const session = readFishingExt(f.state).session;
    expect(session).not.toBeNull();
    expect(session!.mapId).toBe(MAP);
    expect(session!.phase).toBe('waiting');
  });

  it('catches a fish end to end: cast -> bite -> reel, from the same keypress', async () => {
    const f = await rod();
    for (let i = 0; i < f.state.player.inventory.slots.length; i++) f.setSlot(i, null);
    f.holdItem('fishing-rod-t0');
    const caught: Array<{ fishId: string; tile: WorldPos; xp: number }> = [];
    const bites: unknown[] = [];
    f.bus.on<{ fishId: string; tile: WorldPos; xp: number }>('fishing:caught', (p) =>
      caught.push(p),
    );
    f.bus.on('fishing:bite', (p) => bites.push(p));

    swingNeighbour(f, WATER, SHORE, 'down');
    const session = readFishingExt(f.state).session!;

    let guard = 0;
    while (readFishingExt(f.state).session?.phase === 'waiting') {
      f.tickMinutes(10);
      if (++guard > 15) throw new Error('bite never landed');
    }
    expect(bites).toHaveLength(1);
    expect(readFishingExt(f.state).session!.phase).toBe('hook');

    swingNeighbour(f, WATER, SHORE, 'down'); // reel

    expect(caught).toHaveLength(1);
    expect(caught[0]!.fishId).toBe(session.fishId);
    expect(caught[0]!.tile).toEqual({ mapId: MAP, x: WATER.x, y: WATER.y });
    const fish = f.content.fish.get(caught[0]!.fishId)!;
    expect(
      f.state.player.inventory.slots
        .filter((s) => s?.id === fish.itemId)
        .reduce((n, s) => n + (s?.qty ?? 0), 0),
    ).toBe(1);
    expect(f.state.player.stats['day:xp:fishing']).toBe(fish.xp);
    expect(readFishingExt(f.state).session).toBeNull();
  });

  it('rejects a cast onto dry ground with a real reason', async () => {
    const f = await rod();
    const failed: ToolFailedEvent[] = [];
    f.bus.on<ToolFailedEvent>('tool:failed', (p) => failed.push(p));
    swingNeighbour(f, { x: 5, y: 5 }, { x: 5, y: 6 }, 'up');
    expect(failed).toHaveLength(1);
    expect(failed[0]!.reason).toBe('not-water');
    expect(failed[0]!.tile).toEqual({ mapId: MAP, x: 5, y: 5 });
  });

  it('never spends energy, because farming defers on rod tools', async () => {
    const f = await rod();
    const before = f.energy();
    swingNeighbour(f, WATER, SHORE, 'down');
    expect(f.energy()).toBe(before);
    swingNeighbour(f, WATER, SHORE, 'down'); // cancel the cast
    expect(f.energy()).toBe(before);
    expect(readFishingExt(f.state).session).toBeNull();
  });
});

// ===========================================================================
describe('skills XP is fed by real play, not by tests (T-0502)', () => {
  it('turns nine real harvests into farming skill XP after the day closes', async () => {
    const f = await fx([skillsSim]);
    const levelups: Array<{ skill: string; level: number }> = [];
    f.bus.on<{ skill: string; level: number }>('player:levelup', (p) => levelups.push(p));

    // Row 8 is bare synthetic grass: clear of the farm's shipping bin (10,10)
    // and debris row (x 20-23, y 6).
    const row = { y: 8 };
    const tiles: Tile[] = Array.from({ length: 9 }, (_, i) => ({ x: 2 + i * 2, y: row.y }));

    // Day 1: till, plant, water — all through the interact key.
    f.holdItem('hoe-t0');
    for (const t of tiles) swingNeighbour(f, t, { x: t.x, y: t.y + 1 }, 'up');
    for (const t of tiles) expect(f.placed(MAP, t.x, t.y)?.id).toBe('tilled');
    f.holdItem('parsnip-seed', 12);
    for (const t of tiles) swingNeighbour(f, t, { x: t.x, y: t.y + 1 }, 'up');
    for (const t of tiles) expect(f.placed(MAP, t.x, t.y)?.id).toBe('crop:parsnip');

    // Four watered nights (parsnip = 4 stages).
    for (let night = 0; night < 4; night++) {
      f.holdItem('watering-can-t0');
      for (const t of tiles) swingNeighbour(f, t, { x: t.x, y: t.y + 1 }, 'up');
      f.sleepWithWeather('sun');
    }
    for (const t of tiles) expect(f.cropData(MAP, t.x, t.y)?.['stage']).toBe(4);

    // Day 5: harvest by hand. 9 x HARVEST_XP = 108 > 100 -> level 1.
    f.holdHands();
    for (const t of tiles) swingNeighbour(f, t, { x: t.x, y: t.y + 1 }, 'up');
    const harvested = f.state.player.inventory.slots
      .filter((s) => s?.id === 'parsnip')
      .reduce((n, s) => n + (s?.qty ?? 0), 0);
    expect(harvested).toBe(9);
    expect(f.state.player.stats['day:xp:farming']).toBe(9 * HARVEST_XP);
    expect(skillXpOf(f.state, 'farming'), 'XP only lands at the day close').toBe(0);
    expect(skillLevelOf(f.state, 'farming')).toBe(0);

    f.sleepWithWeather('sun');

    expect(skillLevelOf(f.state, 'farming'), 'nine harvests must level farming').toBe(1);
    expect(skillXpOf(f.state, 'farming')).toBe(108 - 100);
    expect(levelups).toContainEqual({ skill: 'farming', level: 1 });
  });

  it('turns a real catch into fishing XP at the day close', async () => {
    const f = await fx([skillsSim, fishingSim]);
    f.installMap(MAP);
    f.holdItem('fishing-rod-t0');
    swingNeighbour(f, { x: 13, y: 12 }, { x: 13, y: 11 }, 'down');
    const fish = f.content.fish.get(readFishingExt(f.state).session!.fishId)!;
    let guard = 0;
    while (readFishingExt(f.state).session?.phase === 'waiting') {
      f.tickMinutes(10);
      if (++guard > 15) throw new Error('bite never landed');
    }
    swingNeighbour(f, { x: 13, y: 12 }, { x: 13, y: 11 }, 'down');
    expect(f.state.player.stats['day:xp:fishing']).toBe(fish.xp);
    expect(skillXpOf(f.state, 'fishing')).toBe(0);
    f.sleepWithWeather('sun');
    expect(skillXpOf(f.state, 'fishing')).toBe(fish.xp);
  });

  it('lists every skill that has an XP source in normal play today', async () => {
    // Mining and combat are defined in skills.json with professions but have no
    // emitter: nothing bumps `day:xp:mining` or `day:xp:combat` (mines/combat
    // are M5). Recorded here so the day-close harvest cannot quietly grow a
    // new source without this expectation being updated on purpose.
    const f = await fx([skillsSim, fishingSim, machinesSim]);
    f.state.maps[MAP]!.placed[tileKey(8, 8)] = { id: 'forage:daffodil', x: 8, y: 8, data: {} };
    f.giveItem('egg', 1);
    f.giveItem('mayonnaise-machine', 1);

    f.holdItem('scythe-t0');
    swingNeighbour(f, { x: 8, y: 8 }, { x: 8, y: 9 }, 'up');
    f.holdItem('egg');
    swingNeighbour(f, { x: 6, y: 6 }, { x: 6, y: 7 }, 'up');
    f.sleepWithWeather('sun');

    const withXp: string[] = [];
    for (const key of ['farming', 'foraging', 'fishing', 'mining', 'combat'] as const) {
      if (skillXpOf(f.state, key) > 0) withXp.push(key);
    }
    expect(withXp).toEqual(['foraging']);
  });
});

// ===========================================================================
describe('everything the sim lane registers, from a fresh game, no cheats', () => {
  it('reaches machines and fishing from the authored starter loadout alone', async () => {
    const f = await fx([machinesSim, fishingSim]);
    f.installMap(MAP);
    // No giveItem: the starter bag already holds rod, hoe, can, axe, pickaxe,
    // scythe and parsnip seeds. Only the machine is missing, and it is
    // normally obtained from the crafting menu (covered above).
    expect(f.state.player.inventory.slots.some((s) => s?.id === 'fishing-rod-t0')).toBe(true);

    f.holdItem('hoe-t0');
    swingNeighbour(f, { x: 3, y: 7 }, { x: 3, y: 8 }, 'up'); // open grass, not the house
    expect(f.placed(MAP, 3, 7)?.id).toBe('tilled');

    f.holdItem('parsnip-seed');
    swingNeighbour(f, { x: 3, y: 7 }, { x: 3, y: 8 }, 'up');
    expect(f.placed(MAP, 3, 7)?.id).toBe('crop:parsnip');

    f.holdItem('fishing-rod-t0');
    swingNeighbour(f, { x: 13, y: 12 }, { x: 13, y: 11 }, 'down');
    expect(readFishingExt(f.state).session).not.toBeNull();
  });

  it('keeps a placed machine and a cast line across save -> reload', async () => {
    const f = await fx([machinesSim, fishingSim]);
    f.installMap(MAP);
    f.giveItem('mayonnaise-machine', 1);
    f.giveItem('egg', 1);
    f.holdItem('mayonnaise-machine');
    swingNeighbour(f, { x: 6, y: 6 }, { x: 6, y: 7 }, 'up');
    f.holdItem('egg');
    swingNeighbour(f, { x: 6, y: 6 }, { x: 6, y: 7 }, 'up');
    f.holdItem('fishing-rod-t0');
    swingNeighbour(f, { x: 13, y: 12 }, { x: 13, y: 11 }, 'down');
    const live = readFishingExt(f.state).session!;
    f.sleep();

    const saved = await f.flushPersist();
    expect(saved).not.toBeNull();
    const obj = saved!.state.maps[MAP]?.placed[tileKey(6, 6)];
    expect(obj?.id).toBe('machine:mayonnaise-machine');
    expect(obj?.data?.['loaded']).toBe(1);
    // Sleeping dismisses the line (day-end), so the save carries no session.
    expect((saved!.state.extensions['fishing'] as { session: unknown }).session).toBeNull();
    expect(live.mapId).toBe(MAP);
  });
});

// ===========================================================================
/**
 * T-0510 — the content expansion is only real if a fresh save can reach it
 * through normal play. No `giveItem` anywhere below: gold comes from shipping
 * what you grew, the new seeds come from the seed shop, and the new machines
 * come from the crafting menu using materials the general store sells.
 *
 * The one shortcut is `skills:grant-xp`, which is the very reducer the day
 * close dispatches from `day:summary` — standing in for 25 harvests, not for a
 * different code path.
 */
describe('T-0510 content is reachable from a fresh game through normal play', () => {
  const FIELD: Tile = { x: 3, y: 7 };
  const KILN_TILE: Tile = { x: 9, y: 9 };
  const KILN_STAND: Tile = { x: 9, y: 10 };

  function work(f: SimFixture, tile: Tile, stand: Tile, tool: string, qty = 1): void {
    f.holdItem(tool, qty);
    swingNeighbour(f, tile, stand, 'up');
  }

  /** Plant `seedId` on every tile, water it nightly and harvest it. Normal play only. */
  function growAndHarvest(f: SimFixture, seedId: string, cropId: string, tiles: Tile[]): number {
    const nights = f.content.crops.get(cropId)?.days.length ?? 4;
    for (const t of tiles) {
      work(f, t, { x: t.x, y: t.y + 1 }, 'hoe-t0');
      work(f, t, { x: t.x, y: t.y + 1 }, seedId);
    }
    for (let night = 0; night < nights; night++) {
      for (const t of tiles) work(f, t, { x: t.x, y: t.y + 1 }, 'watering-can-t0');
      f.sleepWithWeather('sun');
    }
    for (const t of tiles) {
      expect(
        f.cropData(MAP, t.x, t.y)?.['stage'],
        `${cropId} reached its last growth day`,
      ).toBe(nights);
    }
    f.holdHands();
    for (const t of tiles) swingNeighbour(f, t, { x: t.x, y: t.y + 1 }, 'up');
    const got = f.state.player.inventory.slots
      .filter((s) => s?.id === cropId)
      .reduce((n, s) => n + (s?.qty ?? 0), 0);
    expect(got, `harvested ${cropId}`).toBe(tiles.length);
    return got;
  }

  it('buys a T-0510 seed with starting gold and grows it in the field', async () => {
    const f = await fx();
    f.installMap(MAP);
    const start = f.money();
    expect(start, 'a new save must be able to afford the new seeds').toBeGreaterThanOrEqual(45);

    f.buy('seed-shop', 'turnip-seed', 1);
    expect(f.money()).toBe(start - 45);
    expect(f.state.player.inventory.slots.some((s) => s?.id === 'turnip-seed')).toBe(true);

    const sold = growAndHarvest(f, 'turnip-seed', 'turnip', [FIELD]);
    f.insertSlot(f.state.player.inventory.slots.findIndex((s) => s?.id === 'turnip')!);
    f.sleepWithWeather('sun');
    // Turnip sells for 50 base; a normal-quality crop pays out at 1.0x.
    expect(sold).toBe(1);
    expect(f.money()).toBe(start - 45 + 50);
  });

  it('crafts, places, loads and collects a T-0510 machine, then sells its product', async () => {
    const f = await fx([machinesSim, craftingSim, skillsSim]);
    f.installMap(MAP);

    // Step 1: earn the 620g the kiln costs by shipping a starter harvest.
    growAndHarvest(f, 'parsnip-seed', 'parsnip', [FIELD, { x: 4, y: 7 }, { x: 5, y: 7 }, { x: 6, y: 7 }]);
    for (const id of ['parsnip']) {
      const slot = f.state.player.inventory.slots.findIndex((s) => s?.id === id);
      if (slot >= 0) f.insertSlot(slot);
    }
    f.sleepWithWeather('sun');
    expect(f.money(), 'four parsnips must fund the kiln').toBeGreaterThanOrEqual(620);

    // Step 2: buy the exact inputs. Stone is sold per-unit, clay and coal in bulk.
    f.buy('general-store', 'stone', 28);
    f.buy('general-store', 'clay', 10);
    f.buy('general-store', 'coal', 5);
    expect(f.money()).toBeGreaterThan(0);
    for (const [id, qty] of [
      ['stone', 28],
      ['clay', 10],
      ['coal', 5],
    ] as const) {
      const have = f.state.player.inventory.slots
        .filter((s) => s?.id === id)
        .reduce((n, s) => n + (s?.qty ?? 0), 0);
      expect(have, `bought ${id}`).toBe(qty);
    }
    // Step 3: the kiln is a farming-4 recipe; that is the day-close XP reducer.
    f.dispatch('skills:grant-xp', { skill: 'farming', amount: 1000 });
    expect(skillLevelOf(f.state, 'farming')).toBeGreaterThanOrEqual(4);

    f.dispatch('crafting:craft', { recipeId: 'glass-furnace' });
    const kilnSlot = f.state.player.inventory.slots.findIndex((s) => s?.id === 'glass-furnace');
    expect(kilnSlot, 'the kiln was crafted').toBeGreaterThanOrEqual(0);

    // Step 4: place it the way a player does — hold it and press Space.
    f.holdItem('glass-furnace');
    swingNeighbour(f, KILN_TILE, KILN_STAND, 'up');
    expect(f.placed(MAP, KILN_TILE.x, KILN_TILE.y)?.id).toBe('machine:glass-furnace');

    // Step 5: load 3 stone and wait out the 6-hour cycle.
    f.holdItem('stone', 3);
    swingNeighbour(f, KILN_TILE, KILN_STAND, 'up');
    expect(f.cropData(MAP, KILN_TILE.x, KILN_TILE.y)?.['loaded']).toBe(1);
    f.tickMinutes(6 * 60);
    expect(f.cropData(MAP, KILN_TILE.x, KILN_TILE.y)?.['remainingTicks']).toBe(0);

    // Step 6: collect by walking up and pressing Space again.
    f.holdHands();
    swingNeighbour(f, KILN_TILE, KILN_STAND, 'up');
    const glass = f.state.player.inventory.slots
      .filter((s) => s?.id === 'glass')
      .reduce((n, s) => n + (s?.qty ?? 0), 0);
    expect(glass, 'the kiln produced glass').toBe(1);
    expect(f.cropData(MAP, KILN_TILE.x, KILN_TILE.y)?.['loaded']).toBe(0);

    // Step 7: it is a real good — ship it and get paid.
    const before = f.money();
    f.insertSlot(f.state.player.inventory.slots.findIndex((s) => s?.id === 'glass')!);
    f.sleepWithWeather('sun');
    expect(f.money()).toBeGreaterThan(before);
  });

  it('never lets a player ship a machine away and lose it', async () => {
    const f = await fx([machinesSim, craftingSim, skillsSim]);
    f.installMap(MAP);
    // Any craftable machine proves the rule; the churn is the cheapest one a
    // fresh save can afford outright (wood 12 + stone 8 + clay-pot).
    f.dispatch('skills:grant-xp', { skill: 'foraging', amount: 300 });
    f.buy('general-store', 'stone', 8);
    f.buy('general-store', 'clay', 3);
    f.buy('general-store', 'wood', 12);
    const crafted = f.capture<{ itemId: string }>('crafting:crafted');
    // Two crafts, in order: the pot, then the churn that consumes it.
    f.dispatch('crafting:craft', { recipeId: 'clay-pot' });
    f.dispatch('crafting:craft', { recipeId: 'butter-churn' });
    expect(crafted.map((c) => c.itemId)).toEqual(['clay-pot', 'butter-churn']);

    const denied = f.capture<{ reason: string; itemId?: string }>('shipping:denied');
    const slot = f.state.player.inventory.slots.findIndex((s) => s?.id === 'butter-churn');
    expect(slot, 'the churn is in the bag').toBeGreaterThanOrEqual(0);
    f.insertSlot(slot);
    expect(denied.at(-1)).toMatchObject({ reason: 'not-shippable', itemId: 'butter-churn' });
    expect(f.state.player.inventory.slots[slot]?.id).toBe('butter-churn');
  });
});
