/**
 * Game bootstrap + deterministic sim loop. Pure Node usage (the headless bot,
 * tests) only ever touches createGameRuntime and tickSimStep — no DOM, no
 * Three.js. The browser entry additionally wires a renderer and UI host.
 */
import { EventBus } from './events';
import { Store } from './store';
import { Rng } from './rng';
import { createInitialState } from './state';
import { validateMapRefs, type ContentDb } from './content';
import type { FeatureContext, FeatureModule } from './feature';
import { registerAllFeatures } from './registry';
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

export function createGameRuntime(opts: GameBootOptions = {}): GameRuntime {
  const headless = typeof document === 'undefined';
  const seed = opts.seed ?? Math.floor(Math.random() * 0x7fffffff);
  const rng = new Rng(seed);
  const bus = new EventBus();
  const initial = createInitialState(seed, opts.saveName ?? 'ember-hollow-save');
  const store = new Store(initial, rng, bus);

  store.registerReducer('time:tick', (st) => advanceTimeReducer(st));

  const features = registerAllFeatures();
  const content = loadContentSyncOrThrow();
  validateMapRefs(content);

  let saveStore: SaveStore;
  try {
    saveStore = createDefaultSaveStore();
  } catch {
    saveStore = null as unknown as SaveStore;
  }

  const context: FeatureContext = {
    store,
    bus,
    rng,
    headless,
    getRenderer: () => undefined,
    getConfig: () => ({}),
  };

  for (const f of features) f.setup?.(context);

  const runtime: GameRuntime = {
    store,
    bus,
    content,
    features,
    headless,
    saveStore,
    tickSimStep: () => {
      store.dispatch({ type: 'time:tick', payload: null });
    },
  };

  if (opts.mountDom && !headless) {
    mountDomModules(runtime);
  }
  return runtime;
}

function loadContentSyncOrThrow(): ContentDb {
  // The browser path calls validateContent() ahead of boot in main.ts; here we
  // serve the preloaded copy.
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

export { migrateSave, wrapSave };

export type { SaveStore };

/** Load a save file into a fresh runtime (browser boot path). */
export async function loadRuntimeFromSave(saveName: string, store: SaveStore = createDefaultSaveStore()): Promise<GameRuntime> {
  const file = await store.load(saveName);
  if (!file) throw new Error(`no save named ${saveName}`);
  const state = migrateSave(file.state);
  const seed = state.rngSeed;
  const rng = new Rng(seed);
  const bus = new EventBus();
  const s = new Store(state, rng, bus);
  s.registerReducer('time:tick', (st) => advanceTimeReducer(st));
  const features = registerAllFeatures();
  const context: FeatureContext = { store: s, bus, rng, headless: typeof document === 'undefined', getRenderer: () => undefined, getConfig: () => ({}) };
  for (const f of features) f.setup?.(context);
  return {
    store: s,
    bus,
    content: loadContentSyncOrThrow(),
    features,
    headless: typeof document === 'undefined',
    saveStore: store,
    tickSimStep: () => s.dispatch({ type: 'time:tick', payload: null }),
  };
}