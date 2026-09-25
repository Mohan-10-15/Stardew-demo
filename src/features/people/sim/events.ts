/**
 * Heart-event trigger (people lane, M3). Scripted events live in
 * content/dialogue.json under each npc's `heartEvents[]`; a def points at an
 * `eventLine` pool by id. An event fires at most once (extensions.people.
 * eventsPlayed), when the player is on the required map during the time window
 * and friendship is high enough. Rewards (hearts/items) are applied at trigger.
 */
import type { ContentDb } from '@game/core/content';
import type { EventBus } from '@game/core/events';
import { clockToGameMinutes } from '@game/core/time';
import type { GameState } from '@game/core/types';
import { addStackToInventory } from '../../inventory/sim/InventorySim';
import { clampHearts } from './friendship';
import { readPeopleExt, writePeopleExt } from './PeopleSim';

const RELATIONSHIP_FALLBACK = {
  hearts: 0,
  giftCountToday: 0,
  talkedToday: false,
  married: false,
  gaveBouquet: false,
};

/** Check every heart event once per tick; returns the (possibly rewarded) state. */
export function triggerHeartEvents(state: GameState, content: ContentDb, bus: EventBus): GameState {
  let next = state;
  const ext = readPeopleExt(next);
  const played = new Set(ext.eventsPlayed);
  const triggered: string[] = [];

  for (const npcId of [...content.dialogue.keys()].sort()) {
    const def = content.dialogue.get(npcId);
    if (!def || def.heartEvents.length === 0) continue;
    for (const event of def.heartEvents) {
      if (played.has(event.id)) continue;
      const hearts = next.relationships[npcId]?.hearts ?? 0;
      if (hearts < event.hearts) continue;
      if (event.map && next.player.position.mapId !== event.map) continue;
      const gameMinutes = clockToGameMinutes(next.world.clock);
      if (event.time && (gameMinutes < event.time.from || gameMinutes > event.time.to)) continue;
      const lines = def.eventLine?.[event.line] ?? [];
      if (lines.length === 0) continue;

      const heartsReward = event.reward.hearts ?? 0;
      if (heartsReward > 0) {
        const previous = next.relationships[npcId];
        const nextHearts = clampHearts((previous?.hearts ?? 0) + heartsReward);
        next = {
          ...next,
          relationships: {
            ...next.relationships,
            [npcId]: { ...(previous ?? { ...RELATIONSHIP_FALLBACK, npcId }), hearts: nextHearts },
          },
        };
        bus.emit('friendship:changed', { npcId, hearts: nextHearts, delta: heartsReward, taste: 'event' });
      }
      for (const itemId of event.reward.items) {
        const res = addStackToInventory(next, { id: itemId, qty: 1, quality: 0 });
        if (res.added) next = res.state;
      }
      played.add(event.id);
      triggered.push(event.id);
      bus.emit('people:event', { eventId: event.id, npcId });
      bus.emit('dialogue:show', { npcId, lines });
    }
  }

  if (triggered.length === 0) return state;
  const extNext = readPeopleExt(next);
  return writePeopleExt(next, { ...extNext, eventsPlayed: [...extNext.eventsPlayed, ...triggered] });
}