/**
 * The central state store. Owns the authoritative GameState plus the Rng that
 * the simulation uses. Features contribute deterministic reducers keyed by
 * action type; the store applies them in registration order and emits
 * 'state:changed' on every commit.
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
    if (this.processing) throw new Error('reentrant dispatch');
    const matches = this.reducers
      .filter((r) => r.type === action.type)
      .sort((a, b) => a.order - b.order);
    if (matches.length === 0) {
      this.bus.emit('store:unknown-action', action);
      return;
    }
    this.processing = true;
    try {
      for (const r of matches) {
        this._state = r.fn(this._state, action as SimAction, this.rng);
      }
      this.bus.emit('state:changed', this._state);
    } finally {
      this.processing = false;
    }
  }

  /** Direct, intentional mutation for save-load and controlled bootstrap only. */
  replaceState(state: GameState): void {
    this._state = state;
    this.bus.emit('state:changed', this._state);
  }
}