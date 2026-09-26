/**
 * Hermetic sim harness for the WORKER-2 test lane. Builds a Store directly
 * (mirroring tests/sim/core.test.ts), registers core's `time:tick` reducer,
 * then runs the feature modules' setup(ctx) so every reducer + bus subscriber
 * is wired exactly like the real runtime — without createGameRuntime.
 */
import { EventBus } from '@game/core/events';
import { Rng } from '@game/core/rng';
import { Store } from '@game/core/store';
import { createInitialState, mapStateFromDef } from '@game/core/state';
import { loadContent, type ContentDb } from '@game/core/content';
import { MemorySaveStore, wrapSave, type SaveFile } from '@game/core/save';
import {
  TICK_MINUTES,
  type GameState,
  type ItemStack,
  type MapState,
  type Weather,
  type WorldPos,
} from '@game/core/types';
import { advanceClock } from '@game/core/time';
import type { FeatureContext, FeatureModule } from '@game/core/feature';
import { engineSim, type ToolUseRequest } from '@game/features/engine/sim/PlayerPosition';
import { farmingSim } from '@game/features/farming/sim/FarmingSim';
import { shippingSim } from '@game/features/farming/sim/ShippingSim';
import { seedWeatherSim } from '@game/features/farming/sim/SeedWeatherSim';
import { inventorySim } from '@game/features/inventory/sim/InventorySim';
import { shopSim } from '@game/features/shop/sim/ShopSim';
import { tileKey } from '@game/features/farming/sim/utils';
import type { Facing } from '@game/core/types';

// engineSim comes first on purpose: it owns `player:interact`, the action every
// real player gesture goes through. Without it a test cannot reach the bus the
// way the running game does, which is exactly how the missing-mapId bug hid
// behind 300+ green assertions.
export const DEFAULT_MODULES: readonly FeatureModule[] = [
  engineSim,
  farmingSim,
  shippingSim,
  seedWeatherSim,
  inventorySim,
  shopSim,
];

/** A small, fully-tillable farm grid (matches content legend code `g`). */
export function testFarmMap(): MapState {
  return {
    id: 'farm',
    grid: { tiles: new Array(32 * 24).fill('g'), width: 32, height: 24 },
    placed: {
      [tileKey(10, 10)]: { id: 'shipping-bin', x: 10, y: 10, data: {} },
      [tileKey(20, 6)]: { id: 'weed', x: 20, y: 6, data: {} },
      [tileKey(21, 6)]: { id: 'branch', x: 21, y: 6, data: {} },
      [tileKey(22, 6)]: { id: 'rock', x: 22, y: 6, data: {} },
      [tileKey(23, 6)]: { id: 'stump', x: 23, y: 6, data: {} },
    },
    npcs: {},
    version: 1,
  };
}

export interface SimOptions {
  seed?: number;
  saveName?: string;
  modules?: readonly FeatureModule[];
}

export class SimFixture {
  readonly store: Store;
  readonly bus: EventBus;
  readonly rng: Rng;
  readonly content: ContentDb;
  readonly saveStore: MemorySaveStore;
  readonly seed: number;

  constructor(
    store: Store,
    bus: EventBus,
    rng: Rng,
    content: ContentDb,
    saveStore: MemorySaveStore,
    seed: number,
  ) {
    this.store = store;
    this.bus = bus;
    this.rng = rng;
    this.content = content;
    this.saveStore = saveStore;
    this.seed = seed;
  }

  get state(): GameState {
    return this.store.state;
  }

  dispatch(type: string, payload: unknown): void {
    this.store.dispatch({ type, payload });
  }

  /** Advance the clock by one core 10-minute tick. */
  tickStep(): void {
    this.dispatch('time:tick', null);
  }

  /** Advance the clock by `minutes` (multiples of TICK_MINUTES). */
  tickMinutes(minutes: number): void {
    const steps = Math.floor(minutes / TICK_MINUTES);
    for (let i = 0; i < steps; i++) this.tickStep();
  }

  /** End the current day: rollover + payout + next 06:00. */
  sleep(): void {
    this.dispatch('player:sleep', null);
  }

  /** Use the selected tool/item on a tile (direct sim action). */
  useTool(tile: WorldPos, toolId: string): void {
    this.dispatch('farming:tool-use', { tile, toolId });
  }

  /**
   * DEPRECATED — do not use in new tests. Emits `tool:use-requested` with a
   * hand-built WorldPos, skipping the whole input layer.
   *
   * It cannot detect the class of bug this harness exists to catch: the running
   * game never constructs the payload, `player:interact` does, and that emitter
   * once shipped a tile with no `mapId` so every tool swing died with
   * 'no-map' while all of these assertions stayed green. Kept only for the
   * tests that specifically probe the bus handler's own tolerance of a hostile
   * payload. New coverage belongs in `interactFront()`.
   */
  requestTool(tile: WorldPos, toolId: string): void {
    this.bus.emit('tool:use-requested', { tile, toolId });
  }

  // ---------------------------------------------------------------------
  // The REAL input path. Everything below goes through `player:interact`
  // exactly as pressing Space / E / clicking the world does, so these helpers
  // exercise the emitter, the bus and every subscriber.
  // ---------------------------------------------------------------------

  /** Put the player on a tile facing a direction (not a walk — see faceTile). */
  standAt(mapId: string, x: number, y: number, facing: Facing): void {
    const player = this.store.state.player;
    this.store.replaceState({
      ...this.store.state,
      player: { ...player, position: { mapId, x, y }, facing },
    });
  }

  /**
   * Select a hotbar slot holding `itemId`, creating a 1-stack if the bag has
   * none. Returns the slot index. Mirrors a player clicking the hotbar.
   */
  holdItem(itemId: string, qty = 1, quality: 0 | 1 | 2 = 0): number {
    const existing = this.store.state.player.inventory.slots.findIndex(
      (s) => s !== null && s.id === itemId && s.quality === quality,
    );
    const slot = existing === -1 ? this.giveItem(itemId, qty, quality) : existing;
    this.selectSlot(slot);
    return slot;
  }

  /**
   * Select an EMPTY hotbar slot, so `player:interact` sends toolId 'hand'.
   * Crops and forage are only pickable with bare hands (farming:sim routes
   * every named tool to its own effect), so a real player harvesting a crop has
   * nothing in hand — reaching for that state is the point of this helper.
   */
  holdHands(): number {
    const slots = this.store.state.player.inventory.slots;
    const empty = slots.findIndex((s) => s === null);
    if (empty === -1) throw new Error('no free slot for holdHands (clear one first)');
    this.selectSlot(empty);
    return empty;
  }

  /** The payload `player:interact` actually put on the bus, read back verbatim. */
  interactPayload(): ToolUseRequest {
    const expectedMap = this.store.state.player.position.mapId;
    const captured: ToolUseRequest[] = [];
    const off = this.bus.on<ToolUseRequest>('tool:use-requested', (p) => captured.push(p));
    // EventBus replays its buffer to late subscribers, so everything captured
    // before the dispatch is history, not this interaction.
    const baseline = captured.length;
    this.dispatch('player:interact', {});
    off();
    const fresh = captured.slice(baseline);
    if (fresh.length === 0) throw new Error('player:interact emitted no tool:use-requested');
    const payload = fresh[0]!;
    if (payload.tile?.mapId !== expectedMap) {
      throw new Error(
        `tool:use-requested tile is missing mapId (got ${String(payload.tile?.mapId)}, want ${expectedMap})`,
      );
    }
    return payload;
  }

  /**
   * THE input path: dispatch `player:interact` with the player standing where
   * `standAt` put them. Returns the tile the game computed as "in front" — read
   * off the actual `tool:use-requested` payload, not recomputed by the test, so
   * a test can assert the resolved coordinates rather than the ones it hoped
   * for. Throws if the payload arrived without a `mapId`: that is the exact
   * defect that made every tool swing fail in the running game while the
   * hand-built-payload tests stayed green.
   */
  interactFront(): WorldPos {
    return this.interactPayload().tile;
  }

  plant(tile: WorldPos, seedId: string): void {
    this.dispatch('farming:plant', { tile, seedId });
  }

  selectSlot(slot: number): void {
    this.dispatch('player:select-slot', { slot });
  }

  moveSlot(from: number, to: number): void {
    this.dispatch('inventory:move', { from, to });
  }

  insertSlot(slot: number): void {
    this.dispatch('shipping:insert', { slot });
  }

  buy(shopId: string, itemId: string, qty: number): void {
    this.dispatch('shop:buy', { shopId, itemId, qty });
  }

  sell(shopId: string, itemId: string, qty: number): void {
    this.dispatch('shop:sell', { shopId, itemId, qty });
  }

  /**
   * Sleep with a forced, non-rolling weather: sets world.weather + forecast an
   * and marks the weather ext rolled through this night, so the night's roll
   * is skipped and effects run exactly on the pinned weather.
   */
  sleepWithWeather(weather: Weather): void {
    const w = this.store.state.world;
    this.store.state.extensions['weather'] = { lastRolledDay: w.dayCount + 1 };
    this.store.state.world.weather = weather;
    this.store.state.world.forecast = [weather];
    this.dispatch('player:sleep', null);
  }

  placed(mapId: string, x: number, y: number) {
    return this.store.state.maps[mapId]?.placed[tileKey(x, y)];
  }

  /**
   * Install a REAL authored map (legend, water, warps, initial placed objects)
   * into the live state, the way a new game builds its maps from content. Use
   * this whenever a test needs a tile the synthetic testFarmMap does not have —
   * water in particular, since fishing reads `legend[code].water` off the map
   * the player is standing on.
   */
  installMap(mapId: string): MapState {
    const def = this.content.maps.get(mapId);
    if (!def) throw new Error(`no map '${mapId}' in content`);
    const map = mapStateFromDef(def);
    this.store.state.maps[mapId] = map;
    return map;
  }

  cropData(mapId: string, x: number, y: number): Record<string, unknown> | undefined {
    return this.placed(mapId, x, y)?.data;
  }

  /** Test-only direct slot write (setup before dispatches). */
  setSlot(slot: number, stack: ItemStack | null): void {
    this.store.state.player.inventory.slots[slot] = stack;
  }

  /** Test-only: put a stack into the first free slot. */
  giveItem(id: string, qty: number, quality: 0 | 1 | 2 = 0): number {
    const slots = this.store.state.player.inventory.slots;
    let idx = slots.findIndex((s) => s === null);
    if (idx === -1) {
      const existing = slots.findIndex((s) => s !== null && s.id === id && s.quality === quality);
      idx = existing;
      if (idx === -1) throw new Error('no free inventory slot for giveItem');
      const cur = slots[idx];
      if (!cur) throw new Error('slot vanished');
      slots[idx] = { ...cur, qty: cur.qty + qty };
      return idx;
    }
    slots[idx] = { id, qty, quality };
    return idx;
  }

  money(): number {
    return this.store.state.player.money;
  }

  energy(): number {
    return this.store.state.player.energy;
  }

  shippingBox(): ItemStack[] {
    const raw = this.store.state.extensions['farming'];
    if (raw && Array.isArray((raw as { shippingBox?: unknown }).shippingBox)) {
      return (raw as unknown as { shippingBox: ItemStack[] }).shippingBox;
    }
    return [];
  }

  /** Wait for the async ctx.persist() kicked off by player:sleep. */
  async flushPersist(): Promise<SaveFile | null> {
    await new Promise((resolve) => setTimeout(resolve, 0));
    return this.saveStore.load('slot1');
  }

  /** Record every event of `type` emitted after this call returns. */
  capture<T>(type: string): T[] {
    const seen: T[] = [];
    this.bus.on<T>(type, (payload) => seen.push(payload));
    return seen;
  }
}

export async function createSim(opts: SimOptions = {}): Promise<SimFixture> {
  const seed = opts.seed ?? 20260924;
  const saveName = opts.saveName ?? 'sim-test';
  const modules = opts.modules ?? DEFAULT_MODULES;

  const rng = new Rng(seed);
  const bus = new EventBus();
  let state = createInitialState(seed, saveName);
  state = { ...state, maps: { ...state.maps, farm: testFarmMap() } };

  const store = new Store(state, rng, bus);
  store.registerReducer('time:tick', (st) => {
    const transition = advanceClock(st.world, TICK_MINUTES);
    return { ...st, world: transition.world };
  });

  const content = await loadContent();
  const saveStore = new MemorySaveStore();
  const persist = async (): Promise<void> => {
    await saveStore.save('slot1', wrapSave(store.state));
  };

  const ctx: FeatureContext = {
    store,
    bus,
    rng,
    content,
    headless: true,
    getRenderer: () => undefined,
    getConfig: () => ({}),
    persist,
  };
  for (const m of modules) m.setup?.(ctx);

  return new SimFixture(store, bus, rng, content, saveStore, seed);
}
