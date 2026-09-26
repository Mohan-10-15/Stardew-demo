/**
 * fishing:sim — the cast / wait / hook / reel mini-loop (WORKER-2 lane).
 *
 * Casting is claimed from the shared `tool:use-requested` event when the held
 * tool is a rod (item tag `tool:rod` or id prefix `fishing-rod-`); farming:sim
 * ignores rod tools. The cast tile must be water (legend `.water`).
 *
 * A session lives in `extensions.fishing` so a mid-catch state survives
 * save/reload. Species are picked deterministically at cast time — weighted
 * by rarity (weight = 111 - difficulty) among fish whose season / weather /
 * time-of-day gates (content fish.json) match the current moment; the pick is
 * revealed by `fishing:bite` when the clock passes the bite mark. Reeling
 * while waiting pulls the line back (no catch); reeling during the hook
 * window catches (quality roll, inventory + fishing XP via the shared
 * `day:xp:fishing` counter that skills:sim harvests at day close). Losing the
 * 30-minute hook window, a full inventory, or crossing midnight all dismiss
 * the session as `fishing:escaped`.
 */
import { defineFeature, type FeatureContext, type FeatureModule } from '@game/core/feature';
import type { EventBus } from '@game/core/events';
import type { ContentDb } from '@game/core/content';
import type { Rng } from '@game/core/rng';
import { addStackToInventory } from '../../inventory/sim/InventorySim';
import type { GameState, QualityTier, WorldPos } from '@game/core/types';
import type { FishDef } from '@game/core/schemas';
import { bumpStat } from '../../farming/sim/summary';

export const FISHING_EXT_ID = 'fishing';

export type FishingPhase = 'waiting' | 'hook';

export interface FishingSession {
  mapId: string;
  x: number;
  y: number;
  phase: FishingPhase;
  /** World day the cast happened; sessions never cross midnight. */
  castDay: number;
  /** Absolute minute marker (dayCount*1440 + hour*60 + minute). */
  castAt: number;
  biteAt: number;
  hookAt: number;
  fishId: string;
}

export interface FishingExt {
  session: FishingSession | null;
}

export function absoluteMinutes(state: GameState): number {
  const { dayCount } = state.world;
  const { hour, minute } = state.world.clock;
  return dayCount * 1440 + hour * 60 + minute;
}

/** Stardew-scale game minutes (6:00 AM = 600), the unit of fish.time windows. */
export function gameMinuteOf(state: GameState): number {
  return state.world.clock.hour * 100 + state.world.clock.minute;
}

export function readFishingExt(state: GameState): FishingExt {
  const raw = state.extensions[FISHING_EXT_ID];
  if (raw && typeof raw === 'object' && 'session' in raw) return raw as unknown as FishingExt;
  return { session: null };
}

export function ensureFishingExt(state: GameState): GameState {
  if (state.extensions[FISHING_EXT_ID] !== undefined) return state;
  return { ...state, extensions: { ...state.extensions, [FISHING_EXT_ID]: { session: null } } };
}

export function writeFishingExt(state: GameState, ext: FishingExt): GameState {
  return { ...state, extensions: { ...state.extensions, [FISHING_EXT_ID]: { ...ext } } };
}

export function isRod(toolId: string | null | undefined, content: ContentDb): boolean {
  if (!toolId) return false;
  if (toolId.startsWith('fishing-rod-')) return true;
  return content.items.get(toolId)?.tags.includes('tool:rod') ?? false;
}

/** Fish whose season/weather/time gates match the current moment, in content order. */
export function availableFish(state: GameState, content: ContentDb): FishDef[] {
  const cur = gameMinuteOf(state);
  const season = state.world.calendar.seasonIndex;
  const weather = state.world.weather;
  const out: FishDef[] = [];
  for (const f of content.fish.values()) {
    if (f.seasons && !f.seasons.includes(season)) continue;
    if (f.weather && !f.weather.includes(weather)) continue;
    if (f.time && (cur < f.time.from || cur > f.time.to)) continue;
    out.push(f);
  }
  return out;
}

/** Weighted pick: rarer (higher difficulty) species bite less often. */
export function pickFish(candidates: readonly FishDef[], rng: Rng): FishDef | null {
  if (candidates.length === 0) return null;
  if (candidates.length === 1) return candidates[0]!;
  const weights = candidates.map((f) => 111 - f.difficulty);
  const total = weights.reduce((a, b) => a + b, 0);
  let roll = rng.fork('fishing:species').next() * total;
  for (let i = 0; i < weights.length; i++) {
    roll -= weights[i]!;
    if (roll <= 0) return candidates[i]!;
  }
  return candidates[candidates.length - 1]!;
}

/** ~94% normal / ~5% silver / ~1% gold, matching the crop harvest roll. */
export function rollCatchQuality(rng: Rng): QualityTier {
  const r = rng.fork('fishing:quality').next();
  if (r < 0.94) return 0;
  if (r < 0.99) return 1;
  return 2;
}

export interface FishingDeps {
  bus: EventBus;
  content: ContentDb;
}

function tileIsWater(state: GameState, tile: WorldPos, deps: FishingDeps): boolean {
  // Resolve the map from the TILE, not from where the player happens to be
  // standing: the two were conflated here while the bus payload's mapId was
  // being dropped, which is the same class of bug as the missing-mapId defect
  // in tool:use-requested. `tile.mapId` is what the emitter sends.
  const mapId = tile.mapId;
  const map = state.maps[mapId];
  const def = deps.content.maps.get(mapId);
  if (!map || !def) return false;
  if (tile.x < 0 || tile.y < 0 || tile.x >= map.grid.width || tile.y >= map.grid.height) return false;
  const code = map.grid.tiles[tile.y * map.grid.width + tile.x];
  if (code === undefined) return false;
  const glyph = def.legend[code];
  return glyph?.water === true;
}

export function castFishing(state: GameState, tile: WorldPos, toolId: string, rng: Rng, deps: FishingDeps): GameState {
  const ext = readFishingExt(state);
  if (ext.session) return state; // the line is already out
  const mapId = tile.mapId;
  if (!tileIsWater(state, tile, deps)) {
    deps.bus.emit('tool:failed', { tile: { ...tile, mapId }, toolId, reason: 'not-water' });
    return state;
  }
  const picked = pickFish(availableFish(state, deps.content), rng);
  if (!picked) {
    deps.bus.emit('fishing:no-fish', { tile: { ...tile, mapId }, reason: 'no-fish-now' });
    return state;
  }
  const now = absoluteMinutes(state);
  const biteOffset = 10 + Math.floor(rng.fork('fishing:bite').next() * 80); // next 10..89 game minutes
  const session: FishingSession = {
    mapId,
    x: tile.x,
    y: tile.y,
    phase: 'waiting',
    castDay: state.world.dayCount,
    castAt: now,
    biteAt: now + biteOffset,
    hookAt: 0,
    fishId: picked.id,
  };
  deps.bus.emit('fishing:cast', { tile: { ...tile, mapId }, toolId, fishId: picked.id });
  return writeFishingExt(state, { session });
}

export function reelFishing(state: GameState, rng: Rng, deps: FishingDeps): GameState {
  const ext = readFishingExt(state);
  const s = ext.session;
  if (!s) return state;
  const tile = { mapId: s.mapId, x: s.x, y: s.y };
  if (s.phase === 'waiting') {
    deps.bus.emit('fishing:reel-cancel', { tile });
    return writeFishingExt(state, { session: null });
  }
  const fish = deps.content.fish.get(s.fishId);
  if (!fish) {
    deps.bus.emit('fishing:escaped', { tile, fishId: s.fishId, reason: 'no-fish' });
    return writeFishingExt(state, { session: null });
  }
  const quality = rollCatchQuality(rng);
  const added = addStackToInventory(state, { id: fish.itemId, qty: 1, quality });
  if (!added.added) {
    deps.bus.emit('inventory:full', { tile, itemId: fish.itemId });
    deps.bus.emit('fishing:escaped', { tile, fishId: fish.id, reason: 'inventory-full' });
    return writeFishingExt(state, { session: null });
  }
  let next = bumpStat(added.state, 'day:xp:fishing', fish.xp);
  next = bumpStat(next, `day:caught:${fish.itemId}`, 1);
  deps.bus.emit('fishing:caught', { tile, fishId: fish.id, quality, xp: fish.xp });
  return writeFishingExt(next, { session: null });
}

export function tickFishing(state: GameState, deps: FishingDeps): GameState {
  const ext = readFishingExt(state);
  const s = ext.session;
  if (!s) return state;
  const tile = { mapId: s.mapId, x: s.x, y: s.y };
  if (s.castDay !== state.world.dayCount) {
    deps.bus.emit('fishing:escaped', { tile, fishId: s.fishId, reason: 'day-end' });
    return writeFishingExt(state, { session: null });
  }
  const now = absoluteMinutes(state);
  if (s.phase === 'waiting') {
    if (now >= s.biteAt) {
      deps.bus.emit('fishing:bite', { tile, fishId: s.fishId });
      return writeFishingExt(state, { session: { ...s, phase: 'hook', hookAt: now } });
    }
    return state;
  }
  if (now >= s.hookAt + 30) {
    deps.bus.emit('fishing:escaped', { tile, fishId: s.fishId, reason: 'too-slow' });
    return writeFishingExt(state, { session: null });
  }
  return state;
}

export const fishingSim: FeatureModule = defineFeature({
  id: 'fishing:sim',
  lane: 'sim',
  setup(ctx: FeatureContext) {
    ctx.store.replaceState(ensureFishingExt(ctx.store.state));
    const deps: FishingDeps = { bus: ctx.bus, content: ctx.content };

    ctx.store.registerReducer('fishing:cast', (st, action, rng) => {
      const payload = action.payload as { tile?: WorldPos; toolId?: unknown } | null;
      const tile = payload?.tile;
      if (!tile || typeof tile.mapId !== 'string') return st;
      const toolId = typeof payload.toolId === 'string' ? payload.toolId : 'fishing-rod-t0';
      return castFishing(st, tile, toolId, rng, deps);
    });
    ctx.store.registerReducer('fishing:reel', (st, _action, rng) => reelFishing(st, rng, deps));
    ctx.store.registerReducer('time:tick', (st) => tickFishing(st, deps));
    ctx.store.registerReducer('player:sleep', (st) => {
      const ext = readFishingExt(st);
      const s = ext.session;
      if (!s) return st;
      deps.bus.emit('fishing:escaped', {
        tile: { mapId: s.mapId, x: s.x, y: s.y },
        fishId: s.fishId,
        reason: 'day-end',
      });
      return writeFishingExt(st, { session: null });
    });

    // Claim rod interactions from the shared tool-use event. With a session
    // already running the rod press is a reel (cancel while waiting, catch on
    // the hook); otherwise it is a cast.
    // The bus is loosely typed, so this handler must not assume it received
    // anything: `payload.toolId` used to be read off a possibly-null payload,
    // and `payload.tile` is a WorldPos because that is what the emitter sends
    // (the cast reducer drops a payload with no mapId rather than guessing).
    ctx.bus.on('tool:use-requested', (payload: { tile?: WorldPos; toolId?: string | null } | null) => {
      const tile = payload?.tile;
      if (!tile || typeof tile.mapId !== 'string') return;
      if (!isRod(payload.toolId, ctx.content)) return;
      if (readFishingExt(ctx.store.state).session) {
        ctx.store.dispatch({ type: 'fishing:reel', payload: { tile } });
      } else {
        ctx.store.dispatch({ type: 'fishing:cast', payload: { tile, toolId: payload.toolId as string } });
      }
    });
  },
});