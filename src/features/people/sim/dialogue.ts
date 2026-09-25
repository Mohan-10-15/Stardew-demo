import { Rng } from '../../../core/rng';
import type { DialogueDef, DialogueTimeKey } from '../../../core/schemas';
import type { Weather } from '../../../core/types';
import type { GiftTaste } from './friendship';

export interface DialogueContext {
  hearts: number;
  weather: Weather;
  seasonIndex: number;
  gameMinutes: number;
  giftJustGiven?: boolean;
  giftTaste?: GiftTaste;
  taste?: GiftTaste;
  npcId?: string;
  dayCount?: number;
  lineIndex?: number;
}

export type DialoguePoolKind = 'gift' | 'heart' | 'weather' | 'season' | 'time' | 'default';

export interface SelectedDialoguePool {
  kind: DialoguePoolKind;
  lines: readonly string[];
}

export function dialogueTimeBucket(gameMinutes: number): DialogueTimeKey {
  if (gameMinutes < 1200) return 'morning';
  if (gameMinutes < 1800) return 'day';
  if (gameMinutes < 2400) return 'evening';
  return 'night';
}

export const timeBucket = dialogueTimeBucket;

export function selectDialoguePool(def: DialogueDef, ctx: DialogueContext): SelectedDialoguePool {
  if (ctx.giftJustGiven && def.giftReply) {
    const taste = ctx.giftTaste ?? ctx.taste ?? 'neutral';
    const replyKey = taste === 'loved'
      ? 'loves'
      : taste === 'liked'
        ? 'likes'
        : taste === 'disliked'
          ? 'dislikes'
          : taste === 'hates'
            ? 'hates'
            : 'neutral';
    return { kind: 'gift', lines: def.giftReply[replyKey] };
  }

  const heartTiers = Object.keys(def.byHeart ?? {})
    .map((key) => ({ key, tier: Number(key) }))
    .filter((entry) => Number.isFinite(entry.tier))
    .sort((a, b) => b.tier - a.tier);
  for (const entry of heartTiers) {
    if (ctx.hearts >= entry.tier) {
      return { kind: 'heart', lines: def.byHeart?.[entry.key] ?? [] };
    }
  }

  const weather = def.weather?.[ctx.weather];
  if (weather) return { kind: 'weather', lines: weather };
  const season = def.season?.[String(ctx.seasonIndex)];
  if (season) return { kind: 'season', lines: season };
  const time = def.time?.[dialogueTimeBucket(ctx.gameMinutes)];
  if (time) return { kind: 'time', lines: time };
  return { kind: 'default', lines: def.default };
}

export function pickDialogue(def: DialogueDef, ctx: DialogueContext, rng: Rng): string {
  const selected = selectDialoguePool(def, ctx);
  if (selected.lines.length === 0) return '';
  const npcId = ctx.npcId ?? '';
  const dayCount = ctx.dayCount ?? 0;
  const child = rng.fork(`dialogue:${npcId}@${dayCount}`);
  if (ctx.lineIndex === undefined) return child.pick(selected.lines);
  const base = child.int(0, selected.lines.length - 1);
  const offset = Math.trunc(ctx.lineIndex);
  const index = ((base + offset) % selected.lines.length + selected.lines.length) % selected.lines.length;
  return selected.lines[index] ?? '';
}

export function dialoguePool(def: DialogueDef, ctx: DialogueContext): SelectedDialoguePool {
  return selectDialoguePool(def, ctx);
}
