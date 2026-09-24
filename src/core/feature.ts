/**
 * Feature-module contract. A feature is a self-contained module under
 * src/features/<name>/ with optional sim/, view/ and ui/ subfolders. One
 * feature may register any number of FeatureModule instances (one per
 * subfolder) but owns exactly one lane across all of them.
 *
 * Lane ownership:
 *   'world'  -> WORKER-1 (rendering, camera, maps, particles, asset pipeline)
 *   'sim'    -> WORKER-2 (deterministic simulation logic)
 *   'people' -> WORKER-3 (NPCs, dialogue, quests, events, festivals)
 *   'ui'     -> WORKER-3 (DOM UI)
 *   'core'   -> Orchestrator only
 */
import type { EventBus } from './events';
import type { Store } from './store';
import type { Rng } from './rng';
import type { GameState } from './types';
import type { ContentDb } from './content';

export type FeatureLane = 'world' | 'sim' | 'people' | 'ui' | 'core';

export interface FeatureContext {
  store: Store;
  bus: EventBus;
  rng: Rng;
  /** Validated content database (items, crops, npcs, maps). */
  content: ContentDb;
  /** Headless mode: true when running under vitest/Node without a DOM. */
  headless: boolean;
  /** Renderer handle (filled by the world/engine module before setup of others). */
  getRenderer: () => unknown;
  getConfig: () => unknown;
  /** Persist the current state to the active save slot. */
  persist: () => Promise<void>;
}

export interface ViewHandle {
  /** One frame of the game loop; dt in seconds, t clamped. */
  render(dt: number, time: number): void;
}

export interface UiHandle {
  mount(root: HTMLElement): void;
  dispose(): void;
}

export interface FeatureModule<H extends ViewHandle | UiHandle = ViewHandle> {
  /** Stable unique id, e.g. 'farming:sim'. Empty to auto-derive. */
  id: string;
  lane: FeatureLane;
  /** Called once on boot after all reducers from previous lanes are ready. */
  setup?(ctx: FeatureContext): void;
  /** Called once per fixed sim step (10 in-game minutes) in headless order. */
  onTick?(ctx: FeatureContext, step: number): void;
  /** Called by the engine to obtain the view module (world lanes). */
  view?(): H;
  /** Called by the UI host to mount DOM (ui/people lanes). */
  ui?(): UiHandle;
  dispose?(): void;
}

export function defineFeature(mod: FeatureModule): FeatureModule {
  if (!mod.id || !/^[a-z0-9][a-z0-9-]*:[a-z0-9-]+$/.test(mod.id)) {
    throw new Error(`invalid feature id: ${mod.id}`);
  }
  return mod;
}

/** Reducer context split out so sim modules stay DOM-free. */
export interface SimContext {
  store: Store;
  bus: EventBus;
  rng: Rng;
  getState: () => GameState;
}