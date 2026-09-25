import { beforeAll, describe, expect, it } from 'vitest';
import { EventBus } from '@game/core/events';
import { loadContent, type ContentDb } from '@game/core/content';
import type { FeatureContext } from '@game/core/feature';
import { Rng } from '@game/core/rng';
import { buildInitialMaps, createInitialState } from '@game/core/state';
import { advanceClock } from '@game/core/time';
import { Store } from '@game/core/store';
import type { DialogueDef, MapLegend, NpcDef, NpcScheduleDef } from '@game/core/schemas';
import type { GameState, MapState, NpcPresence, TilePos } from '@game/core/types';
import {
  advancePeople,
  applyGift,
  applyTalk,
  clampHearts,
  giftDelta,
  giftTasteForItem,
  initializePeople,
  peopleSim,
  readPeopleExt,
  resetDailyFriendship,
  pickDialogue,
} from '@game/features/people';
import { findPath, resolveSchedule, stepNpc } from '@game/features/people';

function scheduleFixture(): NpcScheduleDef {
  return {
    home: 'home',
    homeAnchor: { x: 2, y: 2 },
    default: [
      { from: 600, to: 800, map: 'a', x: 1, y: 1 },
      { from: 800, to: 900, map: 'a', x: 2, y: 1 },
      { from: 900, to: 1000, map: 'b', x: 3, y: 3 },
    ],
    overrides: [
      { when: { weather: 'rain' }, rules: [{ from: 600, to: 1000, map: 'a', x: 4, y: 1 }] },
      { when: { day: 2 }, rules: [{ from: 600, to: 1000, map: 'b', x: 5, y: 1 }] },
    ],
  };
}

function mapFixture(id = 'village'): MapState {
  return {
    id,
    grid: { tiles: new Array(25).fill('g'), width: 5, height: 5 },
    placed: {},
    npcs: {},
    version: 1,
  };
}

const legend: MapLegend = {
  g: { walkable: true, tillable: false, respawn: false, water: false },
};

function npcFixture(): NpcDef {
  return {
    id: 'tester',
    name: 'Tester',
    birth: { season: 0, day: 1 },
    gift: { loves: ['love'], likes: ['like'], neutral: ['neutral'], dislikes: ['dislike'], hates: ['hate'] },
    baseProfile: {},
  };
}

function stateWithItems(items: Array<[string, number]>): GameState {
  const state = createInitialState(31, 'people-test');
  state.player.inventory.slots.fill(null);
  items.forEach(([id, qty], index) => {
    state.player.inventory.slots[index] = { id, qty, quality: 0 };
  });
  return state;
}

function makeContext(state: GameState, content: ContentDb): { store: Store; bus: EventBus; ctx: FeatureContext } {
  const bus = new EventBus();
  const rng = new Rng(1234);
  const store = new Store(state, rng, bus);
  store.registerReducer('time:tick', (current) => ({ ...current, world: advanceClock(current.world, 10).world }));
  const ctx: FeatureContext = {
    store,
    bus,
    rng,
    content,
    headless: true,
    getRenderer: () => undefined,
    getConfig: () => ({}),
    persist: async () => undefined,
  };
  return { store, bus, ctx };
}

let content: ContentDb;

beforeAll(async () => {
  content = await loadContent();
});

describe('people schedules and movement', () => {
  it('uses the first matching override, last active rule, and home fallback', () => {
    const schedule = scheduleFixture();
    const base = { seasonIndex: 0, weather: 'sun' as const, dayOfMonth: 1, dayOfWeek: 0 };
    expect(resolveSchedule(schedule, { ...base, gameMinutes: 850 })).toEqual({ mapId: 'a', x: 2, y: 1 });
    expect(resolveSchedule(schedule, { ...base, weather: 'rain', gameMinutes: 850 })).toEqual({ mapId: 'a', x: 4, y: 1 });
    expect(resolveSchedule(schedule, { ...base, dayOfMonth: 2, gameMinutes: 850 })).toEqual({ mapId: 'b', x: 5, y: 1 });
    expect(resolveSchedule(schedule, { ...base, gameMinutes: 1000 })).toEqual({ mapId: 'home', x: 2, y: 2 });
  });

  it('finds deterministic paths and steps at most three tiles per tick', () => {
    const map = mapFixture();
    const start: TilePos = { x: 0, y: 2 };
    const goal: TilePos = { x: 4, y: 2 };
    const path = findPath(map, start, goal, legend);
    expect(path).toEqual(findPath(map, start, goal, legend));
    expect(path).toHaveLength(4);
    const presence: NpcPresence = { npcId: 'walker', x: start.x, y: start.y, facing: 'down' };
    const stepped = stepNpc(presence, path, 3);
    expect(stepped.moved).toBe(3);
    expect(stepped.presence).toMatchObject({ x: 3, y: 2, facing: 'right' });
    expect(stepped.path).toEqual([{ x: 4, y: 2 }]);
  });

  it('does not step through a blocked tile', () => {
    const map = mapFixture();
    const start: TilePos = { x: 0, y: 2 };
    const goal: TilePos = { x: 4, y: 2 };
    const path = findPath(map, start, goal, legend, new Set(['1,2']));
    expect(path.every((tile) => !(tile.x === 1 && tile.y === 2))).toBe(true);
    const presence: NpcPresence = { npcId: 'walker', x: start.x, y: start.y, facing: 'down' };
    const stepped = stepNpc(presence, path, 3, new Set([`${path[0]?.x},${path[0]?.y}`]));
    expect(stepped.moved).toBe(0);
  });
});

describe('people dialogue and friendship', () => {
  const dialogue: DialogueDef = {
    default: ['default'],
    heartEvents: [],
    byHeart: { '5': ['high-heart'] },
    weather: { sun: ['sunny'], rain: ['rainy'] },
    season: { '0': ['spring'] },
    time: { morning: ['morning'], day: ['day'], evening: ['evening'], night: ['night'] },
    giftReply: {
      loves: ['love-reply'],
      likes: ['like-reply'],
      neutral: ['neutral-reply'],
      dislikes: ['dislike-reply'],
      hates: ['hate-reply'],
    },
  };

  it('applies gift, heart, weather, season, time, and default precedence', () => {
    const ctx = { weather: 'sun' as const, seasonIndex: 0, gameMinutes: 1300, npcId: 'tester', dayCount: 1 };
    expect(requireDialogue(dialogue, { ...ctx, hearts: 0 })).toBe('sunny');
    expect(requireDialogue(dialogue, { ...ctx, hearts: 5 })).toBe('high-heart');
    expect(requireDialogue(dialogue, { ...ctx, hearts: 0, weather: 'rain' })).toBe('rainy');
    const timeOnly = { ...dialogue, season: undefined, weather: undefined };
    expect(requireDialogue(timeOnly, { ...ctx, hearts: 0, weather: 'storm', gameMinutes: 1900 })).toBe('evening');
    expect(requireDialogue(timeOnly, { ...ctx, hearts: 0, weather: 'sun', gameMinutes: 2500 })).toBe('night');
    expect(requireDialogue(timeOnly, { ...ctx, hearts: 0, weather: 'sun', gameMinutes: 600 })).toBe('morning');
  });

  it('uses the same seeded selection and maps singular tastes to reply pools', () => {
    const def: DialogueDef = { ...dialogue, default: ['one', 'two', 'three'] };
    const ctx = { hearts: 0, weather: 'sun' as const, seasonIndex: 0, gameMinutes: 1300, npcId: 'tester', dayCount: 4 };
    expect(requireDialogue(def, ctx)).toBe(requireDialogue(def, ctx));
    const gift = requireDialogue(dialogue, { ...ctx, giftJustGiven: true, giftTaste: 'loved' });
    const hated = requireDialogue(dialogue, { ...ctx, giftJustGiven: true, giftTaste: 'hates' });
    expect(gift).toBe('love-reply');
    expect(hated).toBe('hate-reply');
    expect(gift).not.toBe(hated);
  });

  it('applies first-per-day gift deltas, consumes one item, and clamps hearts', () => {
    const npc = npcFixture();
    const state = stateWithItems([['love', 2], ['hate', 1]]);
    state.relationships.tester = {
      npcId: 'tester',
      hearts: 9.5,
      giftCountToday: 0,
      talkedToday: false,
      married: false,
      gaveBouquet: false,
    };
    const first = applyGift(state, npc, 'tester', 'love');
    expect(first.consumed).toBe(true);
    expect(first.delta).toBe(1);
    expect(first.hearts).toBe(10);
    expect(first.state.player.inventory.slots[0]?.qty).toBe(1);
    const second = applyGift(first.state, npc, 'tester', 'hate');
    expect(second.consumed).toBe(true);
    expect(second.counted).toBe(false);
    expect(second.delta).toBe(0);
    expect(second.hearts).toBe(10);
    expect(second.state.player.inventory.slots[1]).toBeNull();
    expect(giftDelta('disliked')).toBe(-0.5);
    expect(giftTasteForItem(npc, 'hate')).toBe('hates');
    expect(clampHearts(-4)).toBe(0);
  });

  it('counts only the first talk per day and resets at the day boundary', () => {
    const state = stateWithItems([]);
    const first = applyTalk(state, 'tester');
    const second = applyTalk(first.state, 'tester');
    expect(first.hearts).toBe(0.25);
    expect(first.state.relationships.tester?.talkedToday).toBe(true);
    expect(second.changed).toBe(false);
    expect(resetDailyFriendship(second.state).relationships.tester?.talkedToday).toBe(false);
  });
});

describe('people feature integration', () => {
  it('loads six shipped NPCs with schedules and dialogue content', () => {
    expect(content.npcs.size).toBeGreaterThanOrEqual(6);
    for (const npcId of content.npcs.keys()) {
      expect(content.schedules.has(npcId)).toBe(true);
      expect(content.dialogue.has(npcId)).toBe(true);
    }
  });

  it('places NPCs, relocates across maps, and routes talk and gift interactions', () => {
    const initial = createInitialState(77, 'people-integration', { maps: buildInitialMaps(content.maps) });
    const { store, bus, ctx } = makeContext(initial, content);
    peopleSim.setup?.(ctx);
    const afterSetup = store.state;
    expect(afterSetup.relationships.rowan).toBeDefined();
    expect(afterSetup.extensions.people).toBeDefined();
    const initialRowan = Object.entries(afterSetup.maps).find(([, map]) => map.npcs.rowan !== undefined);
    expect(initialRowan?.[0]).toBe('farm');

    const beforeRollover: GameState = {
      ...afterSetup,
      world: { ...afterSetup.world, clock: { hour: 8, minute: 50 } },
    };
    store.replaceState(beforeRollover);
    store.dispatch({ type: 'time:tick', payload: null });
    const farm = store.state.maps.farm;
    const village = store.state.maps.village;
    if (!farm || !village) throw new Error('integration maps missing');
    expect(farm.npcs.rowan).toBeUndefined();
    expect(village.npcs.rowan).toBeDefined();
    expect(readPeopleExt(store.state).targets.rowan?.mapId).toBe('village');

    const dialogueEvents: Array<{ npcId: string; lines: string[] }> = [];
    const friendshipEvents: Array<{ npcId: string; hearts: number; delta: number; taste: string }> = [];
    bus.on<{ npcId: string; lines: string[] }>('dialogue:show', (event) => dialogueEvents.push(event));
    bus.on<{ npcId: string; hearts: number; delta: number; taste: string }>('friendship:changed', (event) => friendshipEvents.push(event));
    store.dispatch({ type: 'people:talk', payload: { npcId: 'rowan' } });
    expect(store.state.relationships.rowan?.hearts).toBe(0.25);
    expect(dialogueEvents).toHaveLength(1);
    expect(dialogueEvents[0]?.lines.length).toBeGreaterThan(0);
    expect(friendshipEvents[0]?.taste).toBe('talk');

    const withGift = store.state;
    withGift.player.inventory.slots[0] = { id: 'parsnip', qty: 1, quality: 0 };
    withGift.player.inventory.selected = 0;
    store.replaceState(withGift);
    store.dispatch({ type: 'people:gift', payload: { npcId: 'rowan', itemId: 'parsnip' } });
    expect(store.state.relationships.rowan?.hearts).toBe(1.25);
    expect(store.state.player.inventory.slots[0]).toBeNull();
    expect(friendshipEvents[1]?.taste).toBe('loved');
  });

  it('keeps deterministic positions for equal seeds and movement ticks', () => {
    const run = (): string[] => {
      const initial = createInitialState(404, 'people-determinism', { maps: buildInitialMaps(content.maps) });
      let state = initializePeople(initial, content);
      for (let i = 0; i < 8; i++) state = advancePeople(state, content);
      return Object.entries(state.maps).flatMap(([mapId, map]) =>
        Object.values(map.npcs).map((npc) => `${mapId}:${npc.npcId}:${npc.x},${npc.y},${npc.facing}`),
      );
    };
    expect(run()).toEqual(run());
  });
});

function requireDialogue(def: DialogueDef, ctx: Parameters<typeof pickDialogue>[1]): string {
  return pickDialogue(def, ctx, new Rng(88));
}
