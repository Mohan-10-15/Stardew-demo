/**
 * Type-safe synchronous event bus. The light-weight communication backbone
 * between simulation, view and UI modules. All events are namespaced by
 * feature prefix, e.g. minigame:fishing:catch.
 */
export type EventHandler<T = unknown> = (payload: T) => void;
export type Unsubscribe = () => void;

export interface GameEvent<T = unknown> {
  type: string;
  payload: T;
}

/** Emits events and forwards buffer to late subscribers (for UI boot). */
export class EventBus {
  private handlers = new Map<string, Set<EventHandler>>();
  private buffer: GameEvent[] = [];
  private bufferSize: number;

  constructor(bufferSize = 200) {
    this.bufferSize = bufferSize;
  }

  on<T>(type: string, handler: EventHandler<T>): Unsubscribe {
    let set = this.handlers.get(type);
    if (!set) {
      set = new Set();
      this.handlers.set(type, set);
    }
    set.add(handler as EventHandler);
    for (const ev of this.buffer) {
      if (ev.type === type) (handler as EventHandler)(ev.payload);
    }
    return () => {
      set!.delete(handler as EventHandler);
    };
  }

  once<T>(type: string, handler: EventHandler<T>): Unsubscribe {
    const off = this.on<T>(type, (payload) => {
      off();
      handler(payload);
    });
    return off;
  }

  emit<T>(type: string, payload: T): void {
    if (!this.handlers.has(type) && this.bufferSize === 0) return;
    this.buffer.push({ type, payload });
    if (this.buffer.length > this.bufferSize) this.buffer.shift();
    const set = this.handlers.get(type);
    if (!set) return;
    for (const handler of [...set]) {
      handler(payload);
    }
  }

  clear(): void {
    this.handlers.clear();
    this.buffer.length = 0;
  }

  get eventCount(): number {
    let n = 0;
    for (const s of this.handlers.values()) n += s.size;
    return n;
  }
}

export const globalBus = new EventBus();