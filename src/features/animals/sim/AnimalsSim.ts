/**
 * animals:sim — barn & coop creatures (WORKER-2 lane).
 *
 * Animals are bought with gold, fed one feed unit a day (default: hay), and
 * bond over time. Every morning the farm rolls each animal (idempotent per
 * world day): fed animals gain happy/hearts and recover their hunger streak,
 * unfed animals get hungrier and lose a little bond, and any mature,
 * hearts-qualified animal whose `nextProductAt` day has arrived becomes ready
 * to yield its product (inventory quality rolled from happy + hearts). The
 * player pets once a day, feeds once a day, and collects ready products.
 *
 * The whole herd lives in `extensions.animals` (saved with the game). The
 * day roll is guarded on `lastRolledDay` exactly like the farming weather, and
 * hooks BOTH rollover paths: the forced pass-out `time:tick` (core advances
 * time first) and `player:sleep`, whose morning is dispatched as a nested
 * `animals:roll-day` after shipping has advanced the world — so a slept day
 * always rolls exactly once regardless of feature registration order.
 */
import { defineFeature, type FeatureContext, type FeatureModule } from '@game/core/feature';
import type { EventBus } from '@game/core/events';
import type { ContentDb } from '@game/core/content';
import type { Rng } from '@game/core/rng';
import { addStackToInventory } from '../../inventory/sim/InventorySim';
import { removeStackFromInventory } from '../../inventory/sim/InventorySim';
import type { GameState, QualityTier } from '@game/core/types';

export const ANIMALS_EXT_ID = 'animals';
export const ANIMAL_CAP = 24;
/** Hearts needed before an animal will produce its daily product. */
export const MIN_HEARTS_TO_PRODUCE = 2;
export const HAPPY_MAX = 100;

export interface AnimalState {
  id: string;
  species: string;
  bornDay: number;
  mature: boolean;
  /** 0..100 daily contentment; drives product quality. */
  happy: number;
  /** 0..heartsMax (float); bond grows with feeding/petting. */
  hearts: number;
  fedToday: boolean;
  petToday: boolean;
  /** Consecutive mornings without food; escalates the happiness penalty. */
  hungerStreak: number;
  /** True when a product is waiting at the barn door. */
  productReady: boolean;
  /** World day the next product becomes ready (gated by hearts + mature). */
  nextProductAt: number;
}

export interface AnimalsExt {
  animals: AnimalState[];
  lastRolledDay: number;
  /** Monotonic id generator so uids stay unique across species buys. */
  seq: number;
}

export interface AnimalsDeps {
  bus: EventBus;
  content: ContentDb;
}

export function readAnimalsExt(state: GameState): AnimalsExt {
  const raw = state.extensions[ANIMALS_EXT_ID];
  if (raw && typeof raw === 'object' && 'animals' in raw) return raw as unknown as AnimalsExt;
  return { animals: [], lastRolledDay: 0, seq: 0 };
}

export function ensureAnimalsExt(state: GameState): GameState {
  if (state.extensions[ANIMALS_EXT_ID] !== undefined) return state;
  return {
    ...state,
    extensions: { ...state.extensions, [ANIMALS_EXT_ID]: { animals: [], lastRolledDay: 0, seq: 0 } },
  };
}

export function writeAnimalsExt(state: GameState, ext: AnimalsExt): GameState {
  return { ...state, extensions: { ...state.extensions, [ANIMALS_EXT_ID]: { ...ext } } };
}

export function animalsOf(state: GameState): AnimalState[] {
  return readAnimalsExt(state).animals;
}

/** Quality roll driven by happiness + bond: gold needs both, silver less. */
export function rollAnimalQuality(
  rng: Rng,
  happy: number,
  hearts: number,
  heartsMax: number,
): QualityTier {
  const r = rng.fork('animals:quality').next();
  const bond = heartsMax > 0 ? hearts / heartsMax : 0;
  if (happy >= 70 && bond >= 0.3 && r >= 0.85) return 2;
  if (happy >= 45 && hearts >= 2 && r >= 0.6) return 1;
  return 0;
}

export interface BuyAnimalsResult {
  state: GameState;
  ok: boolean;
  reason?: string;
}

export function buyAnimals(state: GameState, species: string, qty: number, deps: AnimalsDeps): BuyAnimalsResult {
  const def = deps.content.animals.get(species);
  if (!def) {
    deps.bus.emit('animals:denied', { reason: 'unknown-species', species });
    return { state, ok: false, reason: 'unknown-species' };
  }
  const n = Number.isFinite(qty) ? Math.max(1, Math.floor(qty)) : 1;
  const ext = readAnimalsExt(state);
  if (ext.animals.length + n > ANIMAL_CAP) {
    deps.bus.emit('animals:denied', { reason: 'full' });
    return { state, ok: false, reason: 'full' };
  }
  const cost = def.buy * n;
  if (state.player.money < cost) {
    deps.bus.emit('animals:denied', { reason: 'no-gold', gold: cost });
    return { state, ok: false, reason: 'no-gold' };
  }

  const uids: string[] = [];
  const animals = [...ext.animals];
  let seq = ext.seq;
  for (let i = 0; i < n; i++) {
    const uid = `${species}-${++seq}`;
    uids.push(uid);
    const mature = def.maturityDays === 0;
    animals.push({
      id: uid,
      species,
      bornDay: state.world.dayCount,
      mature,
      happy: 50,
      hearts: 0,
      fedToday: false,
      petToday: false,
      hungerStreak: 0,
      productReady: false,
      nextProductAt: state.world.dayCount + def.maturityDays + def.produceEveryDays,
    });
  }
  const money = state.player.money - cost;
  deps.bus.emit('animals:bought', { species, qty: n, uids, gold: cost });
  return {
    state: writeAnimalsExt({ ...state, player: { ...state.player, money } }, { ...ext, animals, seq }),
    ok: true,
  };
}

/**
 * One farm morning. Idempotent per `forDay`: both rollover paths supply the
 * world day about to be entered (already advanced by core/shipping when this
 * runs), so `forDay` defaults to the current `world.dayCount` and the
 * `lastRolledDay` guard keeps a night from double-firing.
 */
export function rollAnimalsDay(
  state: GameState,
  rng: Rng,
  deps: AnimalsDeps,
  forDay = state.world.dayCount,
): GameState {
  const ext = readAnimalsExt(state);
  if (ext.lastRolledDay >= forDay) return state;
  const animals = ext.animals.map((a) => {
    const def = deps.content.animals.get(a.species);
    if (!def) return a;
    const heartsMax = def.heartsMax;
    let happy = a.happy;
    let hearts = a.hearts;
    let hungerStreak = a.hungerStreak;
    const mature = a.mature || forDay >= a.bornDay + def.maturityDays;
    let productReady = a.productReady;
    if (mature) {
      if (a.fedToday) {
        happy = Math.min(HAPPY_MAX, happy + 12);
        hearts = Math.min(heartsMax, hearts + 0.35);
        hungerStreak = 0;
      } else {
        hungerStreak += 1;
        happy = Math.max(0, happy - 16 - hungerStreak * 5);
        hearts = Math.max(0, hearts - 0.1);
      }
      if (!productReady && forDay >= a.nextProductAt && hearts >= MIN_HEARTS_TO_PRODUCE) {
        productReady = true;
      }
    }
    return {
      ...a,
      mature,
      happy,
      hearts,
      hungerStreak,
      productReady,
      fedToday: false,
      petToday: false,
    };
  });
  const produced = animals.filter((a) => a.productReady).length;
  deps.bus.emit('animals:day', { day: forDay, count: animals.length, produced });
  return writeAnimalsExt(state, { ...ext, animals, lastRolledDay: forDay });
}

function denyState<G extends GameState>(state: G, deps: AnimalsDeps, reason: string, extra?: Record<string, unknown>): FeedResult {
  deps.bus.emit('animals:denied', { reason, ...extra });
  return { state, ok: false, reason };
}

export interface FeedResult {
  state: GameState;
  ok: boolean;
  reason?: string;
}

export function feedAnimal(state: GameState, animalId: string, deps: AnimalsDeps): FeedResult {
  const ext = readAnimalsExt(state);
  const idx = ext.animals.findIndex((a) => a.id === animalId);
  if (idx === -1) return denyState(state, deps, 'no-animal');
  if (ext.animals[idx]!.fedToday) return denyState(state, deps, 'already-fed');
  const def = deps.content.animals.get(ext.animals[idx]!.species);
  if (!def) return denyState(state, deps, 'unknown-species');
  const feed = def.feed;
  const res = removeStackFromInventory(state, feed.itemId, feed.qty);
  if (res.removed < feed.qty) return denyState(state, deps, 'no-feed');
  const animal = ext.animals[idx]!;
  const happy = Math.min(HAPPY_MAX, animal.happy + 8);
  const animals = ext.animals.map((a, i) =>
    i === idx ? { ...a, fedToday: true, happy } : a,
  );
  deps.bus.emit('animals:fed', { animalId, species: animal.species, itemId: feed.itemId });
  return { state: writeAnimalsExt(res.state, { ...ext, animals }), ok: true };
}

export function petAnimal(state: GameState, animalId: string, deps: AnimalsDeps): FeedResult {
  const ext = readAnimalsExt(state);
  const idx = ext.animals.findIndex((a) => a.id === animalId);
  if (idx === -1) return denyState(state, deps, 'no-animal');
  const animal = ext.animals[idx]!;
  if (animal.petToday) return denyState(state, deps, 'already-petted');
  const def = deps.content.animals.get(animal.species);
  const heartsMax = def?.heartsMax ?? 10;
  const happy = Math.min(HAPPY_MAX, animal.happy + 10);
  const hearts = Math.min(heartsMax, animal.hearts + 0.2);
  const animals = ext.animals.map((a, i) =>
    i === idx ? { ...a, petToday: true, happy, hearts } : a,
  );
  deps.bus.emit('animals:petted', { animalId, species: animal.species });
  return { state: writeAnimalsExt(state, { ...ext, animals }), ok: true };
}

export interface CollectResult {
  state: GameState;
  ok: boolean;
  reason?: string;
  quality?: QualityTier;
}

export function collectAnimal(
  state: GameState,
  animalId: string,
  rng: Rng,
  deps: AnimalsDeps,
): CollectResult {
  const ext = readAnimalsExt(state);
  const idx = ext.animals.findIndex((a) => a.id === animalId);
  if (idx === -1) return denyState(state, deps, 'no-animal');
  const animal = ext.animals[idx]!;
  if (!animal.productReady) return denyState(state, deps, 'not-ready');
  const def = deps.content.animals.get(animal.species);
  if (!def) return denyState(state, deps, 'unknown-species');
  const quality = rollAnimalQuality(rng, animal.happy, animal.hearts, def.heartsMax);
  const added = addStackToInventory(state, { id: def.productId, qty: 1, quality });
  if (!added.added) {
    deps.bus.emit('inventory:full', { animalId, itemId: def.productId });
    return { state, ok: false, reason: 'inventory-full' };
  }
  const happy = Math.min(HAPPY_MAX, animal.happy + 2);
  const animals = ext.animals.map((a, i) =>
    i === idx
      ? { ...a, productReady: false, nextProductAt: state.world.dayCount + def.produceEveryDays, happy }
      : a,
  );
  deps.bus.emit('animals:collected', {
    animalId,
    species: animal.species,
    itemId: def.productId,
    qty: 1,
    quality,
  });
  return { state: writeAnimalsExt(added.state, { ...ext, animals }), ok: true, quality };
}

export const animalsSim: FeatureModule = defineFeature({
  id: 'animals:sim',
  lane: 'sim',
  setup(ctx: FeatureContext) {
    ctx.store.replaceState(ensureAnimalsExt(ctx.store.state));
    const deps: AnimalsDeps = { bus: ctx.bus, content: ctx.content };

    ctx.store.registerReducer('animals:buy', (st, action, _rng) => {
      const p = action.payload as { species?: unknown; qty?: number } | null;
      if (!p || typeof p.species !== 'string') return st;
      const qty = typeof p.qty === 'number' ? p.qty : 1;
      return buyAnimals(st, p.species, qty, deps).state;
    });
    ctx.store.registerReducer('animals:feed', (st, action, _rng) => {
      const p = action.payload as { animalId?: unknown } | null;
      if (!p || typeof p.animalId !== 'string') return st;
      return feedAnimal(st, p.animalId, deps).state;
    });
    ctx.store.registerReducer('animals:pet', (st, action, _rng) => {
      const p = action.payload as { animalId?: unknown } | null;
      if (!p || typeof p.animalId !== 'string') return st;
      return petAnimal(st, p.animalId, deps).state;
    });
    ctx.store.registerReducer('animals:collect', (st, action, rng) => {
      const p = action.payload as { animalId?: unknown } | null;
      if (!p || typeof p.animalId !== 'string') return st;
      return collectAnimal(st, p.animalId, rng, deps).state;
    });
    // Forced pass-out morning: core advances time first, so world.dayCount is
    // already the new day; the lastRolledDay guard prevents double-firing.
    ctx.store.registerReducer('time:tick', (st, _action, rng) => rollAnimalsDay(st, rng, deps));
    // Voluntary sleep: shipping:sim advances the world inside the same action,
    // so dispatch our morning as a nested action — the store runs it AFTER
    // every player:sleep reducer, whichever order the features registered in,
    // and rollAnimalsDay then reads the already-advanced day.
    ctx.store.registerReducer('player:sleep', (st, _action, _rng) => {
      ctx.store.dispatch({ type: 'animals:roll-day', payload: null });
      return st;
    });
    ctx.store.registerReducer('animals:roll-day', (st, _action, rng) => rollAnimalsDay(st, rng, deps));
  },
});