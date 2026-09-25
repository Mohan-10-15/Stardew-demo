/**
 * quest:sim — quest state machine (WORKER-2/people lane, M3).
 *
 * Quest state lives in extensions.people.quests[questId] = { prog, done,
 * doneDay? }. 'collect' progress is recomputed from the player's inventory so
 * it stays correct across save/load; 'deliver'/'talk' flip once via an
 * interaction. 'once' quests stay complete forever; 'weekly' quests become
 * available again seven in-game days after they were turned in.
 *
 * Interaction routing (accept -> complete -> turn in) is applied inside the
 * people `player:interact` reducer; the standalone actions below are also
 * exposed for scripting and tests.
 */
import type { ContentDb } from '@game/core/content';
import type { EventBus } from '@game/core/events';
import type { Rng } from '@game/core/rng';
import type { QuestDef } from '@game/core/schemas';
import type { GameState } from '@game/core/types';
import { addStackToInventory } from '../../inventory/sim/InventorySim';
import { clampHearts } from './friendship';
import { readPeopleExt, writePeopleExt, type PeopleExt, type PeopleQuestProgress } from './PeopleSim';

export const WEEKLY_REPEAT_DAYS = 7;

export interface QuestRef {
  questId: string;
  quest: QuestDef;
}

const FALLBACK_RELATIONSHIP = {
  npcId: '',
  hearts: 0,
  giftCountToday: 0,
  talkedToday: false,
  married: false,
  gaveBouquet: false,
};

export function countItem(state: GameState, itemId: string): number {
  let total = 0;
  for (const stack of state.player.inventory.slots) {
    if (stack && stack.id === itemId) total += stack.qty;
  }
  return total;
}

function activeRecord(ext: PeopleExt, questId: string): PeopleQuestProgress | undefined {
  const record = ext.quests[questId];
  return record && !record.done ? record : undefined;
}

/** Progress (0..target) as shown in the journal. */
export function questProgress(state: GameState, questId: string, quest: QuestDef, ext: PeopleExt): number {
  const record = ext.quests[questId];
  const done = record?.done === true;
  if (quest.objective.type === 'collect') {
    if (done) return quest.objective.count;
    return Math.min(countItem(state, quest.objective.item), quest.objective.count);
  }
  return done ? 1 : 0;
}

/** True once the objective is satisfied (and forever after a completion flag). */
export function questDone(state: GameState, questId: string, quest: QuestDef, ext: PeopleExt): boolean {
  const record = ext.quests[questId];
  if (record?.done === true) return true;
  if (quest.objective.type !== 'collect') return false;
  return countItem(state, quest.objective.item) >= quest.objective.count;
}

/** A quest may be accepted when never started, or when its weekly cooldown passed. */
export function questIsAvailable(state: GameState, questId: string, quest: QuestDef, ext: PeopleExt): boolean {
  const record = ext.quests[questId];
  if (!record) return true;
  if (quest.repeats === 'once') return false;
  if (!record.done) return false;
  const doneDay = typeof record.doneDay === 'number' ? record.doneDay : state.world.dayCount;
  return state.world.dayCount - doneDay >= WEEKLY_REPEAT_DAYS;
}

export function availableQuestsForNpc(state: GameState, npcId: string, content: ContentDb, ext: PeopleExt): QuestRef[] {
  const out: QuestRef[] = [];
  for (const [questId, quest] of content.quests) {
    if (quest.giver !== npcId) continue;
    if (!questIsAvailable(state, questId, quest, ext)) continue;
    out.push({ questId, quest });
  }
  return out;
}

/** Active 'deliver' quest whose recipient is `npcId`. */
export function findPendingDelivery(state: GameState, npcId: string, content: ContentDb, ext: PeopleExt): QuestRef | undefined {
  for (const [questId, quest] of content.quests) {
    if (!activeRecord(ext, questId)) continue;
    if (quest.objective.type === 'deliver' && quest.objective.to === npcId) return { questId, quest };
  }
  return undefined;
}

/** Active 'talk' quest whose target is `npcId`. */
export function findPendingTalk(state: GameState, npcId: string, content: ContentDb, ext: PeopleExt): QuestRef | undefined {
  for (const [questId, quest] of content.quests) {
    if (!activeRecord(ext, questId)) continue;
    if (quest.objective.type === 'talk' && quest.objective.to === npcId) return { questId, quest };
  }
  return undefined;
}

/** Active quest handed in to `npcId` whose objective is now satisfied. */
export function findPendingTurnIn(state: GameState, npcId: string, content: ContentDb, ext: PeopleExt): QuestRef | undefined {
  for (const [questId, quest] of content.quests) {
    const record = ext.quests[questId];
    if (!record || record.done) continue;
    if (quest.giver !== npcId) continue;
    if (!questDone(state, questId, quest, ext)) continue;
    return { questId, quest };
  }
  return undefined;
}

function markDone(state: GameState, questId: string, quest: QuestDef, prog: number): GameState {
  const ext = readPeopleExt(state);
  return writePeopleExt(state, {
    ...ext,
    quests: {
      ...ext.quests,
      [questId]: { prog, done: true, doneDay: state.world.dayCount },
    },
  });
}

export function removeItemQty(state: GameState, itemId: string, qty: number): GameState {
  let remaining = qty;
  const slots = [...state.player.inventory.slots];
  for (let i = 0; i < slots.length && remaining > 0; i++) {
    const stack = slots[i];
    if (!stack || stack.id !== itemId) continue;
    const take = Math.min(stack.qty, remaining);
    remaining -= take;
    slots[i] = stack.qty - take > 0 ? { ...stack, qty: stack.qty - take } : null;
  }
  if (remaining > 0) return state;
  return { ...state, player: { ...state.player, inventory: { ...state.player.inventory, slots } } };
}

function itemName(content: ContentDb, itemId: string): string {
  return content.items.get(itemId)?.name ?? itemId;
}

function npcName(content: ContentDb, npcId: string): string {
  return content.npcs.get(npcId)?.name ?? npcId;
}

function objectiveSummary(quest: QuestDef, content: ContentDb): string {
  switch (quest.objective.type) {
    case 'collect':
      return `Bring ${quest.objective.count} ${itemName(content, quest.objective.item)}`;
    case 'deliver':
      return `Deliver ${itemName(content, quest.objective.item)} to ${npcName(content, quest.objective.to)}`;
    case 'talk':
      return `Talk to ${npcName(content, quest.objective.to)}`;
  }
}

export function acceptQuest(state: GameState, questId: string, content: ContentDb, bus: EventBus, _rng: Rng): GameState {
  const quest = content.quests.get(questId);
  if (!quest) return state;
  const ext = readPeopleExt(state);
  if (!questIsAvailable(state, questId, quest, ext)) return state;
  const next = writePeopleExt(state, { ...ext, quests: { ...ext.quests, [questId]: { prog: 0, done: false } } });
  bus.emit('quests:accepted', { questId, giver: quest.giver });
  bus.emit('quests:board', { giver: quest.giver, quests: [questId] });
  bus.emit('quests:updated', { questId, prog: 0, done: false });
  bus.emit('dialogue:show', {
    npcId: quest.giver,
    lines: [`Accepted — ${quest.name}`, objectiveSummary(quest, content)],
  });
  return next;
}

function applyRewards(state: GameState, quest: QuestDef, bus: EventBus): GameState {
  let next: GameState = { ...state, player: { ...state.player, money: state.player.money + quest.reward.gold } };
  for (const itemId of quest.reward.items) {
    const res = addStackToInventory(next, { id: itemId, qty: 1, quality: 0 });
    if (res.added) next = res.state;
  }
  for (const hearts of quest.reward.hearts) {
    const npcId = hearts.npc;
    const previous = next.relationships[npcId];
    const nextHearts = clampHearts((previous?.hearts ?? 0) + hearts.amount);
    next = {
      ...next,
      relationships: {
        ...next.relationships,
        [npcId]: { ...(previous ?? { ...FALLBACK_RELATIONSHIP, npcId }), hearts: nextHearts },
      },
    };
    bus.emit('friendship:changed', { npcId, hearts: nextHearts, delta: hearts.amount, taste: 'reward' });
  }
  return next;
}

export function deliverQuest(state: GameState, questId: string, content: ContentDb, bus: EventBus, _rng: Rng): GameState {
  const quest = content.quests.get(questId);
  if (!quest) return state;
  if (quest.objective.type !== 'deliver') return state;
  const ext = readPeopleExt(state);
  if (ext.quests[questId]?.done) return state;
  const consumed = removeItemQty(state, quest.objective.item, 1);
  if (consumed === state) return state;
  const next = markDone(consumed, questId, quest, 1);
  bus.emit('quests:updated', { questId, prog: 1, done: true });
  bus.emit('dialogue:show', {
    npcId: quest.objective.to,
    lines: [`You hand over the ${itemName(content, quest.objective.item)}.`, `${quest.name} complete.`],
  });
  return next;
}

export function completeTalkQuest(state: GameState, questId: string, content: ContentDb, bus: EventBus): GameState {
  const quest = content.quests.get(questId);
  if (!quest) return state;
  if (quest.objective.type !== 'talk') return state;
  const ext = readPeopleExt(state);
  if (ext.quests[questId]?.done) return state;
  const next = markDone(state, questId, quest, 1);
  bus.emit('quests:updated', { questId, prog: 1, done: true });
  bus.emit('quests:talk-complete', { questId });
  return next;
}

export function turnInQuest(state: GameState, questId: string, content: ContentDb, bus: EventBus, _rng: Rng): GameState {
  const quest = content.quests.get(questId);
  if (!quest) return state;
  const ext = readPeopleExt(state);
  const record = ext.quests[questId];
  if (!record || record.done) return state;
  if (!questDone(state, questId, quest, ext)) return state;
  let next: GameState = state;
  if (quest.objective.type === 'collect') {
    next = removeItemQty(next, quest.objective.item, quest.objective.count);
    if (next === state) return state;
  }
  next = applyRewards(next, quest, bus);
  const prog = quest.objective.type === 'collect' ? quest.objective.count : 1;
  next = markDone(next, questId, quest, prog);
  bus.emit('quests:completed', { questId, giver: quest.giver });
  bus.emit('quests:updated', { questId, prog, done: true });
  bus.emit('dialogue:show', {
    npcId: quest.giver,
    lines: [`${quest.name} — thank you kindly.`, ...(quest.reward.gold > 0 ? [`You receive ${quest.reward.gold} gold.`] : [])],
  });
  return next;
}