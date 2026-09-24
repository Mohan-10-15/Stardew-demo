/**
 * The central state store. Owns the authoritative GameState plus the Rng that
 * the simulation uses. Features contribute deterministic reducers keyed by
 * action type; the store applies them in registration order and emits
 * 'state:changed' on every commit.
 *
 * Nested dispatches (a reducer or a bus listener dispatching another action)
 * are queued and flushed synchronously AFTER the outer dispatch finishes, so
 * the simulation stays deterministic and reentrancy never throws.
 */
import { EventBus } from './events';
import type { Rng } from './rng';
import type { GameState, SimAction } from './types';

export type Reducer = (state: GameState, action: SimAction<string, unknown>, rng: Rng) => GameState;

interface RegisteredReducer {
  type: string;
  order: number;
  fn: Reducer;
}

let nextOrder = 0;

export class Store {
  readonly bus: EventBus;
  private _state: GameState;
  private rng: Rng;
  private reducers: RegisteredReducer[] = [];
  private processing = false;
  private pending: SimAction<string, unknown>[] = [];

  constructor(state: GameState, rng: Rng, bus?: EventBus) {
    this._state = state;
    this.rng = rng;
    this.bus = bus ?? new EventBus();
  }

  get state(): GameState {
    return this._state;
  }

  get worldRng(): Rng {
    return this.rng;
  }

  /** Register a reducer for an action type. Called during feature setup. */
  registerReducer(type: string, fn: Reducer): void {
    this.reducers.push({ type, order: nextOrder++, fn });
  }

  /** Dispatch an action through every registered reducer for its type. */
  dispatch<T extends string, P>(action: SimAction<T, P>): void {
    if (this.processing) {
      // Defer nested dispatches until the in-flight action commits, keeping
      // the sim deterministic and free of reentrant-dispatch throws.
      this.pending.push(action as SimAction<string, unknown>);
      return;
    }
    this.processing = true;
    try {
      this.runAction(action);
      while (this.pending.length > 0) {
        const queued = this.pending.shift();
        if (queued) this.runAction(queued);
      }
    } finally {
      this.processing = false;
    }
  }

  private runAction<T extends string, P>(action: SimAction<T, P>): void {
    const matches = this.reducers
      .filter((r) => r.type === action.type)
      .sort((a, b) => a.order - b.order);
    if (matches.length === 0) {
      this.bus.emit('store:unknown-action', action);
      return;
    }
    for (const r of matches) {
      this._state = r.fn(this._state, action as SimAction, this.rng);
    }
    this.bus.emit('state:changed', this._state);
  }

  /** Direct, intentional mutation for save-load and controlled bootstrap only. */
  replaceState(state: GameState): void {
    this._state = state;
    this.bus.emit('state:changed', this._state);
  }
}