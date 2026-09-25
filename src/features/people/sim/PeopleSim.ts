import { clockToGameMinutes, dayOfWeek, dayOfWeekName } from '@game/core/time';
import { defineFeature, type FeatureContext, type FeatureModule } from '@game/core/feature';
import type { ContentDb } from '@game/core/content';
import type { EventBus } from '@game/core/events';
import type { Rng } from '@game/core/rng';
import type { NpcDef, NpcScheduleDef } from '@game/core/schemas';
import type { GameState, MapState, NpcPresence, SimAction, TilePos, WorldPos } from '@game/core/types';
import { pickDialogue, selectDialoguePool, type DialogueContext } from './dialogue';
import { applyGift, applyTalk, type GiftTaste } from './friendship';
import { triggerHeartEvents } from './events';
import {
  acceptQuest,
  availableQuestsForNpc,
  completeTalkQuest,
  deliverQuest,
  findPendingDelivery,
  findPendingTalk,
  findPendingTurnIn,
  turnInQuest,
} from './quests';
import {
  findPath,
  NPC_WALK_TILES_PER_TICK,
  resolveSchedule,
  sameTarget,
  stepNpc,
  type ScheduleContext,
  type ScheduleTarget,
} from './schedule';

export const PEOPLE_EXT_ID = 'people';

export interface PeoplePath {
  mapId: string;
  tiles: TilePos[];
}

export interface PeopleQuestProgress {
  prog: number;
  done: boolean;
  /** dayCount when the quest was turned in (drives weekly repeats). */
  doneDay?: number;
}

export interface PeopleExt {
  targets: Record<string, ScheduleTarget>;
  paths: Record<string, PeoplePath>;
  eventsPlayed: string[];
  quests: Record<string, PeopleQuestProgress>;
  lastDayCount: number;
}

export interface NpcLocation {
  mapId: string;
  presence: NpcPresence;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function readTarget(value: unknown): ScheduleTarget | undefined {
  if (!isRecord(value)) return undefined;
  const { mapId, x, y } = value;
  return typeof mapId === 'string' && typeof x === 'number' && typeof y === 'number'
    ? { mapId, x, y }
    : undefined;
}

function readPath(value: unknown): PeoplePath | undefined {
  if (!isRecord(value)) return undefined;
  const { mapId, tiles } = value;
  if (typeof mapId !== 'string' || !Array.isArray(tiles)) return undefined;
  const parsed: TilePos[] = [];
  for (const tile of tiles) {
    if (!isRecord(tile) || typeof tile.x !== 'number' || typeof tile.y !== 'number') continue;
    parsed.push({ x: tile.x, y: tile.y });
  }
  return { mapId, tiles: parsed };
}

function readQuestProgress(value: unknown): PeopleQuestProgress | undefined {
  if (!isRecord(value)) return undefined;
  if (typeof value.prog !== 'number' || typeof value.done !== 'boolean') return undefined;
  const progress: PeopleQuestProgress = { prog: value.prog, done: value.done };
  if (typeof value.doneDay === 'number') progress.doneDay = value.doneDay;
  return progress;
}

export function readPeopleExt(state: GameState): PeopleExt {
  const raw = isRecord(state.extensions[PEOPLE_EXT_ID]) ? state.extensions[PEOPLE_EXT_ID] : {};
  const targets: Record<string, ScheduleTarget> = {};
  if (isRecord(raw.targets)) {
    for (const [npcId, value] of Object.entries(raw.targets)) {
      const target = readTarget(value);
      if (target) targets[npcId] = target;
    }
  }
  const paths: Record<string, PeoplePath> = {};
  if (isRecord(raw.paths)) {
    for (const [npcId, value] of Object.entries(raw.paths)) {
      const path = readPath(value);
      if (path) paths[npcId] = path;
    }
  }
  const eventsPlayed = Array.isArray(raw.eventsPlayed)
    ? raw.eventsPlayed.filter((id): id is string => typeof id === 'string')
    : [];
  const quests: Record<string, PeopleQuestProgress> = {};
  if (isRecord(raw.quests)) {
    for (const [questId, value] of Object.entries(raw.quests)) {
      const progress = readQuestProgress(value);
      if (progress) quests[questId] = progress;
    }
  }
  return {
    targets,
    paths,
    eventsPlayed,
    quests,
    lastDayCount: typeof raw.lastDayCount === 'number' ? raw.lastDayCount : state.world.dayCount,
  };
}

export function writePeopleExt(state: GameState, ext: PeopleExt): GameState {
  return {
    ...state,
    extensions: {
      ...state.extensions,
      [PEOPLE_EXT_ID]: {
        targets: ext.targets,
        paths: ext.paths,
        eventsPlayed: ext.eventsPlayed,
        quests: ext.quests,
        lastDayCount: ext.lastDayCount,
      },
    },
  };
}

export function ensurePeopleExt(state: GameState): GameState {
  const ext = readPeopleExt(state);
  return writePeopleExt(state, ext);
}

export function scheduleContextFromState(state: GameState): ScheduleContext {
  const { calendar, clock, weather } = state.world;
  return {
    seasonIndex: calendar.seasonIndex,
    weather,
    dayOfMonth: calendar.dayOfMonth,
    dayOfWeek: dayOfWeek(calendar),
    gameMinutes: clockToGameMinutes(clock),
  };
}

function scheduleTarget(
  schedule: NpcScheduleDef,
  state: GameState,
  content: ContentDb,
): ScheduleTarget {
  const homeSpawn = content.maps.get(schedule.home)?.spawn;
  return resolveSchedule(schedule, scheduleContextFromState(state), homeSpawn);
}

function findNpc(state: GameState, npcId: string): NpcLocation | undefined {
  for (const [mapId, map] of Object.entries(state.maps)) {
    const presence = map.npcs[npcId];
    if (presence) return { mapId, presence };
  }
  return undefined;
}

function setNpc(
  maps: Record<string, MapState>,
  mapId: string,
  npcId: string,
  presence: NpcPresence | null,
): Record<string, MapState> {
  const map = maps[mapId];
  if (!map) return maps;
  const npcs = { ...map.npcs };
  if (presence) npcs[npcId] = presence;
  else delete npcs[npcId];
  return { ...maps, [mapId]: { ...map, npcs } };
}

function withNpcRelationships(state: GameState, npcs: ReadonlyMap<string, NpcDef>): GameState {
  let relationships = state.relationships;
  let changed = false;
  for (const npcId of npcs.keys()) {
    if (relationships[npcId]) continue;
    relationships = {
      ...relationships,
      [npcId]: {
        npcId,
        hearts: 0,
        giftCountToday: 0,
        talkedToday: false,
        married: false,
        gaveBouquet: false,
      },
    };
    changed = true;
  }
  return changed ? { ...state, relationships } : state;
}

function blockedTiles(maps: Record<string, MapState>, mapId: string, excludeNpcId: string): Set<string> {
  const blocked = new Set<string>();
  for (const [id, map] of Object.entries(maps)) {
    if (id !== mapId) continue;
    for (const [npcId, npc] of Object.entries(map.npcs)) {
      if (npcId !== excludeNpcId) blocked.add(`${npc.x},${npc.y}`);
    }
  }
  return blocked;
}

function pathFor(
  maps: Record<string, MapState>,
  mapId: string,
  presence: NpcPresence,
  target: ScheduleTarget,
  content: ContentDb,
): TilePos[] {
  const map = maps[mapId];
  const mapDef = content.maps.get(mapId);
  if (!map || !mapDef) return [];
  return findPath(
    map,
    { x: presence.x, y: presence.y },
    { x: target.x, y: target.y },
    mapDef.legend,
    blockedTiles(maps, mapId, presence.npcId),
  );
}

function locationAfterTarget(
  maps: Record<string, MapState>,
  npcId: string,
  current: NpcLocation,
  target: ScheduleTarget,
): { maps: Record<string, MapState>; location: NpcLocation } {
  if (current.mapId === target.mapId) return { maps, location: current };
  if (!maps[target.mapId]) return { maps, location: current };
  const without = setNpc(maps, current.mapId, npcId, null);
  const presence: NpcPresence = { npcId, x: target.x, y: target.y, facing: 'down' };
  const withNpc = setNpc(without, target.mapId, npcId, presence);
  return { maps: withNpc, location: { mapId: target.mapId, presence } };
}

export function initializePeople(state: GameState, content: ContentDb): GameState {
  let next = withNpcRelationships(state, content.npcs);
  const ext = readPeopleExt(next);
  let maps = { ...next.maps };
  const targets: Record<string, ScheduleTarget> = { ...ext.targets };
  const paths: Record<string, PeoplePath> = { ...ext.paths };

  for (const npcId of content.npcs.keys()) {
    const schedule = content.schedules.get(npcId);
    if (!schedule) continue;
    const target = scheduleTarget(schedule, next, content);
    targets[npcId] = target;
    let current = findNpc({ ...next, maps }, npcId);
    if (!current) {
      if (!maps[target.mapId]) continue;
      const presence: NpcPresence = { npcId, x: target.x, y: target.y, facing: 'down' };
      maps = setNpc(maps, target.mapId, npcId, presence);
      current = { mapId: target.mapId, presence };
    } else {
      const relocated = locationAfterTarget(maps, npcId, current, target);
      maps = relocated.maps;
      current = relocated.location;
    }
    if (current.mapId === target.mapId) {
      const path = current.presence.x === target.x && current.presence.y === target.y
        ? []
        : pathFor(maps, current.mapId, current.presence, target, content);
      paths[npcId] = { mapId: target.mapId, tiles: path };
    } else {
      paths[npcId] = { mapId: target.mapId, tiles: [] };
    }
  }
  next = { ...next, maps };
  return writePeopleExt(next, { ...ext, targets, paths, lastDayCount: next.world.dayCount });
}

export function advancePeople(state: GameState, content: ContentDb, bus?: EventBus): GameState {
  let next = state;
  if (bus) {
    next = triggerHeartEvents(next, content, bus);
  }
  next = ensurePeopleExt(next);
  let ext = readPeopleExt(next);
  if (ext.lastDayCount !== next.world.dayCount) {
    next = {
      ...next,
      relationships: Object.fromEntries(
        Object.entries(next.relationships).map(([npcId, relationship]) => [
          npcId,
          { ...relationship, giftCountToday: 0, talkedToday: false },
        ]),
      ),
    };
    ext = { ...ext, lastDayCount: next.world.dayCount };
  }

  let maps = { ...next.maps };
  const targets: Record<string, ScheduleTarget> = { ...ext.targets };
  const paths: Record<string, PeoplePath> = { ...ext.paths };

  for (const npcId of content.npcs.keys()) {
    const schedule = content.schedules.get(npcId);
    if (!schedule) continue;
    const target = scheduleTarget(schedule, next, content);
    targets[npcId] = target;
    let current = findNpc({ ...next, maps }, npcId);
    if (!current) {
      if (!maps[target.mapId]) {
        paths[npcId] = { mapId: target.mapId, tiles: [] };
        continue;
      }
      const presence: NpcPresence = { npcId, x: target.x, y: target.y, facing: 'down' };
      maps = setNpc(maps, target.mapId, npcId, presence);
      paths[npcId] = { mapId: target.mapId, tiles: [] };
      continue;
    }

    const targetChanged = !sameTarget(ext.targets[npcId], target);
    if (current.mapId !== target.mapId) {
      const relocated = locationAfterTarget(maps, npcId, current, target);
      maps = relocated.maps;
      current = relocated.location;
      paths[npcId] = { mapId: target.mapId, tiles: [] };
      continue;
    }

    let path = targetChanged ? [] : paths[npcId]?.tiles ?? [];
    const atTarget = current.presence.x === target.x && current.presence.y === target.y;
    if (targetChanged || !paths[npcId] || paths[npcId]?.mapId !== target.mapId || (!atTarget && path.length === 0)) {
      path = pathFor(maps, current.mapId, current.presence, target, content);
    }
    const blocked = blockedTiles(maps, current.mapId, npcId);
    if (current.mapId === next.player.position.mapId) blocked.add(`${next.player.position.x},${next.player.position.y}`);
    const stepped = stepNpc(current.presence, path, NPC_WALK_TILES_PER_TICK, blocked, {
      x: target.x,
      y: target.y,
    });
    if (stepped.presence.x !== current.presence.x || stepped.presence.y !== current.presence.y || stepped.presence.facing !== current.presence.facing) {
      maps = setNpc(maps, current.mapId, npcId, stepped.presence);
    }
    paths[npcId] = { mapId: target.mapId, tiles: stepped.path };
  }

  next = { ...next, maps };
  return writePeopleExt(next, { ...ext, targets, paths, lastDayCount: next.world.dayCount });
}

export function peopleTickReducer(state: GameState, content: ContentDb, bus?: EventBus): GameState {
  return advancePeople(state, content, bus);
}

export const tickPeople = peopleTickReducer;

function frontTile(position: WorldPos & { facing: GameState['player']['facing'] }): TilePos {
  if (position.facing === 'up') return { x: position.x, y: position.y - 1 };
  if (position.facing === 'down') return { x: position.x, y: position.y + 1 };
  if (position.facing === 'left') return { x: position.x - 1, y: position.y };
  return { x: position.x + 1, y: position.y };
}

export function npcAtFront(state: GameState, explicitNpcId?: string): NpcLocation | undefined {
  if (explicitNpcId) return findNpc(state, explicitNpcId);
  const tile = frontTile({ ...state.player.position, facing: state.player.facing });
  const map = state.maps[state.player.position.mapId];
  if (!map) return undefined;
  for (const [npcId, presence] of Object.entries(map.npcs)) {
    if (presence.x === tile.x && presence.y === tile.y) return { mapId: map.id, presence: { ...presence, npcId } };
  }
  return undefined;
}

function selectedItemId(state: GameState): string | undefined {
  const stack = state.player.inventory.slots[state.player.inventory.selected];
  return stack && stack.qty > 0 ? stack.id : undefined;
}

function dialogueContext(
  state: GameState,
  npcId: string,
  giftJustGiven: boolean,
  giftTaste?: GiftTaste,
): DialogueContext {
  return {
    hearts: state.relationships[npcId]?.hearts ?? 0,
    weather: state.world.weather,
    seasonIndex: state.world.calendar.seasonIndex,
    gameMinutes: clockToGameMinutes(state.world.clock),
    giftJustGiven,
    giftTaste,
    npcId,
    dayCount: state.world.dayCount,
  };
}

function emitDialogue(
  state: GameState,
  npcId: string,
  giftJustGiven: boolean,
  giftTaste: GiftTaste | undefined,
  bus: EventBus,
  content: ContentDb,
  rng: Rng,
): void {
  const dialogue = content.dialogue.get(npcId);
  if (!dialogue) return;
  const context = dialogueContext(state, npcId, giftJustGiven, giftTaste);
  const selected = selectDialoguePool(dialogue, context);
  if (selected.lines.length === 0) return;
  const chosen = pickDialogue(dialogue, context, rng);
  const start = selected.lines.indexOf(chosen);
  const lines = start < 0 ? [chosen] : [...selected.lines.slice(start), ...selected.lines.slice(0, start)];
  bus.emit('dialogue:show', { npcId, lines });
}

export function talkToNpc(
  state: GameState,
  npcId: string,
  bus: EventBus,
  rng: Rng,
  content: ContentDb,
): GameState {
  const result = applyTalk(state, npcId);
  if (result.changed) {
    bus.emit('friendship:changed', { npcId, hearts: result.hearts, delta: result.delta, taste: 'talk' });
  }
  emitDialogue(result.state, npcId, false, undefined, bus, content, rng);
  return result.state;
}

export function giftToNpc(
  state: GameState,
  npcId: string,
  itemId: string,
  bus: EventBus,
  rng: Rng,
  content: ContentDb,
): GameState {
  const npc = content.npcs.get(npcId);
  const result = applyGift(state, npc, npcId, itemId);
  if (!result.consumed) {
    bus.emit('gift:denied', { npcId, itemId, reason: result.reason ?? 'missing' });
    return result.state;
  }
  if (result.counted) {
    bus.emit('friendship:changed', {
      npcId,
      hearts: result.hearts,
      delta: result.delta,
      taste: result.taste,
    });
  }
  emitDialogue(result.state, npcId, true, result.taste, bus, content, rng);
  return result.state;
}

function interactReducer(
  state: GameState,
  action: SimAction<string, unknown>,
  bus: EventBus,
  rng: Rng,
  content: ContentDb,
): GameState {
  const payload = isRecord(action.payload) ? action.payload : {};
  const explicitNpcId = typeof payload.npcId === 'string' ? payload.npcId : undefined;
  const location = npcAtFront(state, explicitNpcId);
  if (!location) return state;
  const npcId = location.presence.npcId;
  const explicitItemId = typeof payload.itemId === 'string' && payload.itemId.length > 0 ? payload.itemId : undefined;
  const itemId = explicitItemId ?? selectedItemId(state);
  const ext = readPeopleExt(state);

  const pendingDelivery = findPendingDelivery(state, npcId, content, ext);
  if (pendingDelivery && pendingDelivery.quest.objective.type === 'deliver' && itemId === pendingDelivery.quest.objective.item) {
    return deliverQuest(state, pendingDelivery.questId, content, bus, rng);
  }

  const pendingTalk = findPendingTalk(state, npcId, content, ext);
  if (pendingTalk) {
    const result = completeTalkQuest(state, pendingTalk.questId, content, bus);
    return talkToNpc(result, npcId, bus, rng, content);
  }

  const pendingTurnIn = findPendingTurnIn(state, npcId, content, ext);
  if (pendingTurnIn) {
    return turnInQuest(state, pendingTurnIn.questId, content, bus, rng);
  }

  const available = availableQuestsForNpc(state, npcId, content, ext);
  const firstAvailable = available[0];
  if (firstAvailable) {
    return acceptQuest(state, firstAvailable.questId, content, bus, rng);
  }

  if (itemId) {
    const itemDef = content.items.get(itemId);
    if (itemDef && itemDef.category !== 'tool') return giftToNpc(state, npcId, itemId, bus, rng, content);
  }
  return talkToNpc(state, npcId, bus, rng, content);
}

export const peopleSim: FeatureModule = defineFeature({
  id: 'people:sim',
  lane: 'sim',
  setup(ctx: FeatureContext): void {
    ctx.store.replaceState(initializePeople(ctx.store.state, ctx.content));
    ctx.store.registerReducer('time:tick', (state) => peopleTickReducer(state, ctx.content, ctx.bus));
    ctx.store.registerReducer('quests:accept', (state, action, rng) => {
      const payload = isRecord(action.payload) ? action.payload : {};
      const questId = typeof payload.questId === 'string' ? payload.questId : undefined;
      if (!questId) return state;
      return acceptQuest(state, questId, ctx.content, ctx.bus, rng);
    });
    ctx.store.registerReducer('quests:turn-in', (state, action, rng) => {
      const payload = isRecord(action.payload) ? action.payload : {};
      const questId = typeof payload.questId === 'string' ? payload.questId : undefined;
      if (!questId) return state;
      return turnInQuest(state, questId, ctx.content, ctx.bus, rng);
    });
    ctx.store.registerReducer('player:interact', (state, action, rng) =>
      interactReducer(state, action, ctx.bus, rng, ctx.content),
    );
    ctx.store.registerReducer('people:interact', (state, action, rng) =>
      interactReducer(state, action, ctx.bus, rng, ctx.content),
    );
    ctx.store.registerReducer('people:talk', (state, action, rng) => {
      const payload = isRecord(action.payload) ? action.payload : {};
      const npcId = typeof payload.npcId === 'string' ? payload.npcId : npcAtFront(state)?.presence.npcId;
      if (!npcId) return state;
      return talkToNpc(state, npcId, ctx.bus, rng, ctx.content);
    });
    ctx.store.registerReducer('people:gift', (state, action, rng) => {
      const payload = isRecord(action.payload) ? action.payload : {};
      const location = npcAtFront(state, typeof payload.npcId === 'string' ? payload.npcId : undefined);
      const npcId = location?.presence.npcId;
      const itemId = typeof payload.itemId === 'string' && payload.itemId.length > 0 ? payload.itemId : selectedItemId(state);
      if (!npcId || !itemId) return state;
      return giftToNpc(state, npcId, itemId, ctx.bus, rng, ctx.content);
    });
  },
});

export const peopleFeature = peopleSim;
export { dayOfWeekName };
