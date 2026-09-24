/**
 * Hermetic sim harness for the WORKER-2 test lane. Builds a Store directly
 * (mirroring tests/sim/core.test.ts), registers core's `time:tick` reducer,
 * then runs the feature modules' setup(ctx) so every reducer + bus subscriber
 * is wired exactly like the real runtime — without createGameRuntime.
 */
import { EventBus } from '@game/core/events';
import { Rng } from '@game/core/rng';
import { Store } from '@game/core/store';
import { createInitialState } from '@game/core/state';
import { loadContent, type ContentDb } from '@game/core/content';
import { MemorySaveStore, wrapSave, type SaveFile } from '@game/core/save';
import {
  TICK_MINUTES,
  type GameState,
  type ItemStack,
  type MapState,
  type WorldPos,
} from '@game/core/types';
import { advanceClock } from '@game/core/time';
import type { FeatureContext, FeatureModule } from '@game/core/feature';
import { farmingSim } from '@game/features/farming/sim/FarmingSim';
import { shippingSim } from '@game/features/farming/sim/ShippingSim';
import { seedWeatherSim } from '@game/features/farming/sim/SeedWeatherSim';
import { inventorySim } from '@game/features/inventory/sim/InventorySim';
import { tileKey } from '@game/features/farming/sim/utils';

export const DEFAULT_MODULES: readonly FeatureModule[] = [
  farmingSim,
  shippingSim,
  seedWeatherSim,
  inventorySim,
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

  /** What WORKER-1's player:interact reducer emits; exercises the bus path. */
  requestTool(tile: WorldPos, toolId: string): void {
    this.bus.emit('tool:use-requested', { tile, toolId });
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

  placed(mapId: string, x: number, y: number) {
    return this.store.state.maps[mapId]?.placed[tileKey(x, y)];
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
