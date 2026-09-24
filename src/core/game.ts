/**
 * Game bootstrap + deterministic sim loop. Pure Node usage (the headless bot,
 * tests) only ever touches createGameRuntime and tickSimStep — no DOM, no
 * Three.js. The browser entry additionally wires a renderer and UI host.
 */
import { EventBus } from './events';
import { Store } from './store';
import { Rng } from './rng';
import { buildInitialMaps, createInitialState, migrateAllMaps } from './state';
import { validateMapRefs, type ContentDb } from './content';
import type { FeatureContext, FeatureModule } from './feature';
import { registerAllFeatures } from './registry';
// Side-effect import AFTER the registry above: executing every feature entry
// self-registers submodules; the registry body must be fully initialized first
// (see the note in core/registry.ts about the ESM TDZ cycle).
import '../features/auto-import';
import type { GameState } from './types';
import { TICK_MINUTES } from './types';
import { advanceClock } from './time';
import { createDefaultSaveStore, migrateSave, wrapSave, type SaveStore } from './save';

export interface GameRuntime {
  store: Store;
  bus: EventBus;
  content: ContentDb;
  features: readonly FeatureModule[];
  /** Advance the sim by exactly one 10-minute step. */
  tickSimStep: () => void;
  /** True when the sim is deterministic (bot/test mode). */
  headless: boolean;
  saveStore: SaveStore;
  /** Active save slot name (e.g. slot1). */
  saveSlot: string;
  /** Persist current state into the active save slot. */
  persist: () => Promise<void>;
}

export interface GameBootOptions {
  /** Start fresh (vs load a save). */
  newGame?: boolean;
  saveName?: string;
  /** Seeded deterministic initial state. */
  seed?: number;
  /** Mount view/UI modules (browser only). */
  mountDom?: boolean;
}

function advanceTimeReducer(state: GameState): GameState {
  const transition = advanceClock(state.world, TICK_MINUTES);
  return { ...state, world: transition.world };
}

function buildContext(
  store: Store,
  bus: EventBus,
  rng: Rng,
  headless: boolean,
  content: ContentDb,
  saveStore: SaveStore,
  saveSlot: string,
): FeatureContext {
  return {
    store,
    bus,
    rng,
    content,
    headless,
    getRenderer: () => undefined,
    getConfig: () => ({}),
    persist: async () => {
      const file = wrapSave(store.state);
      await saveStore.save(saveSlot, file);
      const stamped = { ...store.state.meta, updatedAt: Date.now() };
      store.replaceState({ ...store.state, meta: stamped });
      bus.emit('save:done', { slot: saveSlot, savedAt: file.savedAt });
    },
  };
}

function loadContentSyncOrThrow(): ContentDb {
  // The browser path calls loadContent() ahead of boot in main.ts; here we
  // serve the preloaded copy, or an empty DB in headless tests.
  return (globalThis as unknown as { __EH_CONTENT?: ContentDb }).__EH_CONTENT ?? {
    items: new Map(),
    crops: new Map(),
    npcs: new Map(),
    maps: new Map(),
    byId() {
      return undefined;
    },
  };
}

function logDone(features: readonly FeatureModule[]): void {
  for (const f of features) {
    if (f.lane === 'sim' || f.lane === 'core') continue;
    console.info(`[ember-hollow] feature ${f.id} registered (${f.lane})`);
  }
}

export function createGameRuntime(
  opts: GameBootOptions = {},
  saveStore: SaveStore = createDefaultSaveStore(),
  saveSlot = 'slot1',
): GameRuntime {
  const headless = typeof document === 'undefined';
  const seed = opts.seed ?? Math.floor(Math.random() * 0x7fffffff);
  const rng = new Rng(seed);
  const bus = new EventBus();
  const content = loadContentSyncOrThrow();
  const maps = buildInitialMaps(content.maps);
  const initial = createInitialState(seed, opts.saveName ?? 'ember-hollow-save', { maps });
  const farmDef = content.maps.get('farm');
  if (farmDef) {
    initial.player.position = { mapId: 'farm', x: farmDef.spawn.x, y: farmDef.spawn.y };
  }
  const store = new Store(initial, rng, bus);
  store.registerReducer('time:tick', (st) => advanceTimeReducer(st));
  const features = registerAllFeatures();
  validateMapRefs(content);
  const context = buildContext(store, bus, rng, headless, content, saveStore, saveSlot);
  for (const f of features) f.setup?.(context);
  logDone(features);

  const runtime: GameRuntime = {
    store,
    bus,
    content,
    features,
    headless,
    saveStore,
    saveSlot,
    tickSimStep: () => {
      const before = store.state.world.dayCount;
      store.dispatch({ type: 'time:tick', payload: null });
      const after = store.state.world.dayCount;
      if (after !== before) bus.emit('day:rollover', store.state.world);
      bus.emit('time:ticked', store.state.world);
    },
    persist: context.persist,
  };

  if (opts.mountDom && !headless) {
    mountDomModules(runtime);
  }
  return runtime;
}

/** Load a save file into a fresh runtime (browser boot path). */
export async function loadRuntimeFromSave(
  saveName: string,
  saveStore: SaveStore = createDefaultSaveStore(),
  saveSlot = saveName,
): Promise<GameRuntime> {
  const file = await saveStore.load(saveName);
  if (!file) throw new Error(`no save named ${saveName}`);
  const state = migrateSave(file.state);
  const content = loadContentSyncOrThrow();
  state.maps = migrateAllMaps(state.maps, content.maps);
  const seed = state.rngSeed;
  const rng = new Rng(seed);
  const bus = new EventBus();
  const s = new Store(state, rng, bus);
  s.registerReducer('time:tick', (st) => advanceTimeReducer(st));
  const features = registerAllFeatures();
  const context = buildContext(s, bus, rng, typeof document === 'undefined', content, saveStore, saveSlot);
  for (const f of features) f.setup?.(context);

  return {
    store: s,
    bus,
    content,
    features,
    headless: typeof document === 'undefined',
    saveStore,
    saveSlot,
    tickSimStep: () => {
      const before = s.state.world.dayCount;
      s.dispatch({ type: 'time:tick', payload: null });
      const after = s.state.world.dayCount;
      if (after !== before) bus.emit('day:rollover', s.state.world);
      bus.emit('time:ticked', s.state.world);
    },
    persist: context.persist,
  };
}

function mountDomModules(runtime: GameRuntime): void {
  const root = document.getElementById('ui-root');
  if (!root) return;
  for (const f of runtime.features) {
    if (f.ui) {
      const h = f.ui();
      h.mount(root);
    }
  }
}