import { beforeAll, describe, expect, it } from 'vitest';
import { EventBus } from '@game/core/events';
import { loadContent, type ContentDb } from '@game/core/content';
import type { FeatureContext } from '@game/core/feature';
import { Rng } from '@game/core/rng';
import { buildInitialMaps, createInitialState } from '@game/core/state';
import { Store } from '@game/core/store';
import type { GameState, NpcPresence } from '@game/core/types';
import {
  countItem,
  deliverQuest,
  peopleSim,
  questDone,
  questIsAvailable,
  questProgress,
  readPeopleExt,
} from '@game/features/people';

function makeContext(state: GameState, content: ContentDb): { store: Store; bus: EventBus; ctx: FeatureContext } {
  const bus = new EventBus();
  const rng = new Rng(4321);
  const store = new Store(state, rng, bus);
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

function boot(content: ContentDb): { store: Store; bus: EventBus } {
  const initial = createInitialState(7, 'quests-test', { maps: buildInitialMaps(content.maps) });
  const { store, bus, ctx } = makeContext(initial, content);
  peopleSim.setup?.(ctx);
  return { store, bus };
}

function addItems(state: GameState, items: Array<[string, number]>): GameState {
  const slots = state.player.inventory.slots.map((stack) => (stack ? { ...stack } : null));
  let selected = state.player.inventory.selected;
  items.forEach(([id, qty]) => {
    const index = slots.findIndex((stack) => stack?.id === id);
    if (index >= 0 && slots[index]) {
      slots[index] = { id, qty: (slots[index]?.qty ?? 0) + qty, quality: 0 };
      selected = index;
    } else {
      const empty = slots.findIndex((stack) => stack === null);
      if (empty >= 0) {
        slots[empty] = { id, qty, quality: 0 };
        selected = empty;
      }
    }
  });
  return {
    ...state,
    player: { ...state.player, inventory: { ...state.player.inventory, slots, selected } },
  };
}

function faceNpc(state: GameState, npcId: string): GameState {
  for (const [mapId, map] of Object.entries(state.maps)) {
    const presence = map.npcs[npcId];
    if (!presence) continue;
    return {
      ...state,
      player: {
        ...state.player,
        position: { mapId, x: presence.x, y: presence.y - 1 },
        facing: 'down',
      },
    };
  }
  return state;
}

function npcOn(state: GameState, npcId: string): NpcPresence | undefined {
  for (const map of Object.values(state.maps)) {
    const presence = map.npcs[npcId];
    if (presence) return presence;
  }
  return undefined;
}

let content: ContentDb;

beforeAll(async () => {
  content = await loadContent();
});

describe('quest lifecycle', () => {
  it('accepts a collect quest, tracks progress from inventory, and pays out on turn-in', () => {
    const { store } = boot(content);
    const questId = 'q-rowan-cinders';
    const quest = content.quests.get(questId);
    if (!quest) throw new Error('missing quest ' + questId);

    store.dispatch({ type: 'quests:accept', payload: { questId } });
    let state = store.state;
    expect(readPeopleExt(state).quests[questId]).toMatchObject({ done: false });
    expect(questIsAvailable(state, questId, quest, readPeopleExt(state))).toBe(false);
    expect(questProgress(state, questId, quest, readPeopleExt(state))).toBe(0);

    state = addItems(state, [['parsnip', 3]]);
    expect(questDone(state, questId, quest, readPeopleExt(state))).toBe(false);
    expect(questProgress(state, questId, quest, readPeopleExt(state))).toBe(3);

    state = addItems(state, [['parsnip', 2]]);
    store.replaceState(state);
    expect(questDone(store.state, questId, quest, readPeopleExt(store.state))).toBe(true);

    const moneyBefore = store.state.player.money;
    store.dispatch({ type: 'quests:turn-in', payload: { questId } });
    const after = store.state;
    expect(countItem(after, 'parsnip')).toBe(0);
    expect(after.player.money).toBe(moneyBefore + 350);
    expect(after.relationships.rowan?.hearts).toBe(1);
    expect(readPeopleExt(after).quests[questId]).toMatchObject({
      prog: 5,
      done: true,
      doneDay: after.world.dayCount,
    });
    expect(questIsAvailable(after, questId, quest, readPeopleExt(after))).toBe(false);
  });

  it('refuses to turn in a collect quest before the objective is met', () => {
    const { store, bus } = boot(content);
    const questId = 'q-marisol-wagon';
    const quest = content.quests.get(questId);
    if (!quest) throw new Error('missing quest ' + questId);
    store.dispatch({ type: 'quests:accept', payload: { questId } });
    const moneyBefore = store.state.player.money;
    const completed: string[] = [];
    bus.on<{ questId: string }>('quests:completed', (e) => completed.push(e.questId));
    store.dispatch({ type: 'quests:turn-in', payload: { questId } });
    expect(completed).toHaveLength(0);
    expect(store.state.player.money).toBe(moneyBefore);
    expect(readPeopleExt(store.state).quests[questId]?.done).toBe(false);
  });

  it('reopens weekly quests seven days after completion', () => {
    const { store } = boot(content);
    const questId = 'q-bramble-delivery';
    const quest = content.quests.get(questId);
    if (!quest) throw new Error('missing quest ' + questId);
    store.dispatch({ type: 'quests:accept', payload: { questId } });
    let state = addItems(store.state, [['chocolate', 1]]);
    const rng = new Rng(1);
    state = deliverQuest(state, questId, content, store.bus, rng);
    store.replaceState(state);
    const record = readPeopleExt(store.state).quests[questId];
    expect(record?.done).toBe(true);
    expect(questIsAvailable(store.state, questId, quest, readPeopleExt(store.state))).toBe(false);

    const sevenDays = { ...store.state, world: { ...store.state.world, dayCount: (record?.doneDay ?? 0) + 7 } };
    expect(questIsAvailable(sevenDays, questId, quest, readPeopleExt(sevenDays))).toBe(true);
  });
});

describe('quest routing through interactions', () => {
  it('delivers a quest item to the recipient instead of gifting it', () => {
    const { store, bus } = boot(content);
    const questId = 'q-bramble-delivery';
    store.dispatch({ type: 'quests:accept', payload: { questId } });
    let state = addItems(store.state, [['chocolate', 1]]);
    state = faceNpc(state, 'juniper');
    store.replaceState(state);
    const shown: Array<{ npcId: string; lines: string[] }> = [];
    bus.on<{ npcId: string; lines: string[] }>('dialogue:show', (e) => shown.push(e));
    store.dispatch({ type: 'player:interact', payload: {} });
    expect(countItem(store.state, 'chocolate')).toBe(0);
    expect(readPeopleExt(store.state).quests[questId]?.done).toBe(true);
    expect(shown.some((e) => e.lines.join(' ').includes('complete'))).toBe(true);
  });

  it('completes a talk quest on interaction and still grants the talk', () => {
    const { store } = boot(content);
    const questId = 'q-sable-message';
    store.dispatch({ type: 'quests:accept', payload: { questId } });
    const state = faceNpc(store.state, 'juniper');
    store.replaceState(state);
    store.dispatch({ type: 'player:interact', payload: {} });
    expect(readPeopleExt(store.state).quests[questId]?.done).toBe(true);
    expect(store.state.relationships.juniper?.talkedToday).toBe(true);
    expect(store.state.relationships.juniper?.hearts).toBe(0.25);
  });

  it('never hands a held tool to an NPC as a gift', () => {
    const { store, bus } = boot(content);
    const state = addItems(store.state, [['hoe-t0', 1]]);
    const faced = faceNpc(state, 'juniper');
    store.replaceState(faced);
    const denied: Array<{ npcId: string; itemId: string }> = [];
    bus.on<{ npcId: string; itemId: string }>('gift:denied', (e) => denied.push(e));
    const hoesBefore = countItem(store.state, 'hoe-t0');
    store.dispatch({ type: 'player:interact', payload: {} });
    expect(countItem(store.state, 'hoe-t0')).toBe(hoesBefore);
    expect(denied).toHaveLength(0);
    expect(store.state.relationships.juniper?.talkedToday).toBe(true);
  });

  it('accepts a giver-available quest on interaction', () => {
    const { store } = boot(content);
    const state = faceNpc(store.state, 'rowan');
    store.replaceState(state);
    store.dispatch({ type: 'player:interact', payload: {} });
    expect(readPeopleExt(store.state).quests['q-rowan-cinders']).toBeDefined();
    expect(readPeopleExt(store.state).quests['q-rowan-cinders']?.done).toBe(false);
  });
});

describe('heart events', () => {
  it('plays each scripted event once and applies its rewards', () => {
    const { store, bus } = boot(content);
    const events: Array<{ eventId: string; npcId: string }> = [];
    bus.on<{ eventId: string; npcId: string }>('people:event', (e) => events.push(e));

    let state = store.state;
    state = {
      ...state,
      relationships: {
        ...state.relationships,
        rowan: {
          npcId: 'rowan',
          hearts: 2,
          giftCountToday: state.relationships.rowan?.giftCountToday ?? 0,
          talkedToday: state.relationships.rowan?.talkedToday ?? false,
          married: state.relationships.rowan?.married ?? false,
          gaveBouquet: state.relationships.rowan?.gaveBouquet ?? false,
        },
      },
      player: {
        ...state.player,
        position: { mapId: 'village', x: 10, y: 10 },
      },
      world: { ...state.world, clock: { hour: 12, minute: 0 } },
    };
    store.replaceState(state);
    store.dispatch({ type: 'time:tick', payload: null });

    expect(events).toHaveLength(1);
    expect(events[0]?.eventId).toBe('e-rowan-cinders');
    expect(store.state.relationships.rowan?.hearts).toBe(3);
    expect(countItem(store.state, 'wood')).toBeGreaterThanOrEqual(1);
    const regifted = npcOn(store.state, 'rowan');
    expect(regifted).toBeDefined();

    store.replaceState(store.state);
    store.dispatch({ type: 'time:tick', payload: null });
    expect(events).toHaveLength(1);
  });

  it('keeps a low-heart friendship from firing an event', () => {
    const { store, bus } = boot(content);
    const events: string[] = [];
    bus.on<{ eventId: string }>('people:event', (e) => events.push(e.eventId));
    const state = {
      ...store.state,
      player: { ...store.state.player, position: { mapId: 'village', x: 10, y: 10 } },
      world: { ...store.state.world, clock: { hour: 12, minute: 0 } },
    };
    store.replaceState(state);
    store.dispatch({ type: 'time:tick', payload: null });
    expect(events).toHaveLength(0);
  });
});