import type { EventBus } from '../../../core/events';
import type { NpcDef } from '../../../core/schemas';
import type { GameState, ItemStack, RelationshipState } from '../../../core/types';
import { addStackToInventory, summarizeInventory } from '../../inventory/sim/InventorySim';

export const GIFT_TASTES = ['loved', 'liked', 'neutral', 'disliked', 'hates'] as const;
export type GiftTaste = (typeof GIFT_TASTES)[number];

export interface TalkApplication {
  state: GameState;
  hearts: number;
  delta: number;
  changed: boolean;
}

export interface GiftApplication {
  state: GameState;
  hearts: number;
  delta: number;
  taste: GiftTaste;
  consumed: boolean;
  counted: boolean;
  reason?: 'missing';
}

export function clampHearts(value: number): number {
  const clamped = Math.max(0, Math.min(10, Number.isFinite(value) ? value : 0));
  return Math.round(clamped * 4) / 4;
}

export function giftDelta(taste: GiftTaste): number {
  switch (taste) {
    case 'loved':
      return 1;
    case 'liked':
      return 0.5;
    case 'neutral':
      return 0;
    case 'disliked':
      return -0.5;
    case 'hates':
      return -1;
  }
}

export function giftTasteForItem(npc: NpcDef | undefined, itemId: string): GiftTaste {
  if (!npc) return 'neutral';
  if (npc.gift.loves.includes(itemId)) return 'loved';
  if (npc.gift.likes.includes(itemId)) return 'liked';
  if (npc.gift.neutral.includes(itemId)) return 'neutral';
  if (npc.gift.dislikes.includes(itemId)) return 'disliked';
  if (npc.gift.hates.includes(itemId)) return 'hates';
  return 'neutral';
}

export const tasteForItem = giftTasteForItem;
export const giftTaste = giftTasteForItem;

function relationshipFor(state: GameState, npcId: string): RelationshipState {
  const current = state.relationships[npcId];
  if (current) return { ...current };
  return {
    npcId,
    hearts: 0,
    giftCountToday: 0,
    talkedToday: false,
    married: false,
    gaveBouquet: false,
  };
}

function putRelationship(state: GameState, relationship: RelationshipState): GameState {
  return {
    ...state,
    relationships: {
      ...state.relationships,
      [relationship.npcId]: relationship,
    },
  };
}

function removeOneItem(state: GameState, itemId: string): GameState | undefined {
  const slots = [...state.player.inventory.slots];
  const index = slots.findIndex((slot) => slot !== null && slot.id === itemId && slot.qty > 0);
  if (index === -1) return undefined;
  const stack = slots[index];
  if (!stack) return undefined;
  if (stack.qty <= 1) slots[index] = null;
  else slots[index] = { ...stack, qty: stack.qty - 1 };
  return {
    ...state,
    player: {
      ...state.player,
      inventory: { ...state.player.inventory, slots },
    },
  };
}

function hasItem(state: GameState, itemId: string): boolean {
  return summarizeInventory(state).some((stack) => stack.id === itemId && stack.qty > 0);
}

export function applyTalk(state: GameState, npcId: string): TalkApplication {
  const relationship = relationshipFor(state, npcId);
  if (relationship.talkedToday) {
    return { state, hearts: relationship.hearts, delta: 0, changed: false };
  }
  const delta = 0.25;
  const hearts = clampHearts(relationship.hearts + delta);
  const nextRelationship: RelationshipState = { ...relationship, hearts, talkedToday: true };
  return {
    state: putRelationship(state, nextRelationship),
    hearts,
    delta,
    changed: true,
  };
}

export function applyGift(
  state: GameState,
  npc: NpcDef | undefined,
  npcId: string,
  itemId: string,
): GiftApplication {
  const taste = giftTasteForItem(npc, itemId);
  if (!hasItem(state, itemId)) {
    const relationship = relationshipFor(state, npcId);
    return { state, hearts: relationship.hearts, delta: 0, taste, consumed: false, counted: false, reason: 'missing' };
  }
  const consumedState = removeOneItem(state, itemId);
  if (!consumedState) {
    const relationship = relationshipFor(state, npcId);
    return { state, hearts: relationship.hearts, delta: 0, taste, consumed: false, counted: false, reason: 'missing' };
  }
  const relationship = relationshipFor(consumedState, npcId);
  const counted = relationship.giftCountToday < 1;
  const delta = counted ? giftDelta(taste) : 0;
  const hearts = clampHearts(relationship.hearts + delta);
  const nextRelationship: RelationshipState = {
    ...relationship,
    hearts,
    giftCountToday: counted ? 1 : relationship.giftCountToday,
  };
  return {
    state: putRelationship(consumedState, nextRelationship),
    hearts,
    delta,
    taste,
    consumed: true,
    counted,
  };
}

export function talkReducer(state: GameState, npcId: string, bus?: EventBus): GameState {
  const result = applyTalk(state, npcId);
  if (result.changed) {
    bus?.emit('friendship:changed', { npcId, hearts: result.hearts, delta: result.delta, taste: 'talk' });
  }
  return result.state;
}

export function giftReducer(
  state: GameState,
  npc: NpcDef | undefined,
  npcId: string,
  itemId: string,
  bus?: EventBus,
): GameState {
  const result = applyGift(state, npc, npcId, itemId);
  if (!result.consumed) {
    bus?.emit('gift:denied', { npcId, itemId, reason: result.reason ?? 'missing' });
    return result.state;
  }
  if (result.counted) {
    bus?.emit('friendship:changed', {
      npcId,
      hearts: result.hearts,
      delta: result.delta,
      taste: result.taste,
    });
  }
  return result.state;
}

export function resetDailyFriendship(state: GameState): GameState {
  const entries = Object.entries(state.relationships);
  if (entries.length === 0) return state;
  const relationships = { ...state.relationships };
  for (const [npcId, relationship] of entries) {
    relationships[npcId] = { ...relationship, giftCountToday: 0, talkedToday: false };
  }
  return { ...state, relationships };
}

export function addPeopleReward(state: GameState, itemId: string, quantity = 1): { state: GameState; added: boolean } {
  const stack: ItemStack = { id: itemId, qty: Math.max(1, Math.trunc(quantity)), quality: 0 };
  return addStackToInventory(state, stack);
}

export const applyTalkReducer = talkReducer;
export const applyGiftReducer = giftReducer;
