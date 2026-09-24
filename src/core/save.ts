/**
 * Save/load skeleton with versioned, migrated, corruption-safe payloads.
 * Storage is behind a SaveStore interface so the headless sim can run on a
 * filesystem store while the browser uses IndexedDB. Export/import produce a
 * plain JSON file.
 */
import type { GameState } from './types';
import { createInitialState } from './state';
import { MAX_SAVE_SLOTS } from './types';

export const SAVE_FORMAT = 'ember-hollow';
export const SAVE_VERSION = 1;

export interface SaveFile {
  format: string;
  version: number;
  savedAt: number;
  state: GameState;
}

export interface SaveStore {
  readonly kind: string;
  list(): Promise<string[]>;
  has(name: string): Promise<boolean>;
  save(name: string, file: SaveFile): Promise<void>;
  load(name: string): Promise<SaveFile | null>;
  remove(name: string): Promise<void>;
  export(name: string): Promise<SaveFile | null>;
  import(name: string, file: SaveFile): Promise<void>;
}

/** Migration table: key = version the file was saved at, value = (s) -> s+1. */
export type RawState = Record<string, unknown>;
export const migrations: Record<number, (raw: RawState) => RawState> = {
  1: (raw) => raw,
};

export function migrateSave(raw: unknown): GameState {
  if (!raw || typeof raw !== 'object') throw new Error('save is not an object');
  const r = raw as { format?: unknown; version?: unknown; state?: unknown };
  if (r.format !== SAVE_FORMAT) throw new Error(`unrecognized save format: ${String(r.format)}`);
  let version = Number(r.version ?? 1);
  if (!Number.isInteger(version) || version < 1) throw new Error('invalid save version');
  let state: unknown = r.state;
  while (version < SAVE_VERSION) {
    const step = migrations[version];
    if (!step) throw new Error(`no migration path from version ${version}`);
    state = step(state as RawState);
    version += 1;
  }
  if (!state || typeof state !== 'object') throw new Error('save produced invalid state');
  const s = state as GameState;
  s.version = SAVE_VERSION;
  return sanitizeState(s);
}

/** Fill gaps with defaults and deep-freeze-protect nothing; returns copy. */
export function sanitizeState(state: GameState): GameState {
  const defaults = createInitialState(0, 'sanitized');
  const world = state.world ?? ({} as GameState['world']);
  const player = state.player ?? ({} as GameState['player']);
  const merged: GameState = JSON.parse(
    JSON.stringify({
      ...defaults,
      ...state,
      world: {
        ...defaults.world,
        ...world,
        calendar: { ...defaults.world.calendar, ...world.calendar },
        clock: { ...defaults.world.clock, ...world.clock },
      },
      player: {
        ...defaults.player,
        ...player,
        skills: { ...defaults.player.skills, ...player.skills },
        inventory: { ...defaults.player.inventory, ...player.inventory },
      },
      meta: { ...defaults.meta, ...state.meta },
      farm: { ...defaults.farm, ...state.farm },
      quests: { ...defaults.quests, ...state.quests },
      progression: { ...defaults.progression, ...state.progression },
    }),
  );
  return merged;
}

export function wrapSave(state: GameState): SaveFile {
  return {
    format: SAVE_FORMAT,
    version: SAVE_VERSION,
    savedAt: Date.now(),
    state: sanitizeState(state),
  };
}

export function slotName(slot: number): string {
  if (slot < 0 || slot >= MAX_SAVE_SLOTS) throw new Error(`slot out of range: ${slot}`);
  return `slot${slot + 1}`;
}

/**
 * In-memory store for tests.
 */
export class MemorySaveStore implements SaveStore {
  readonly kind = 'memory';
  private files = new Map<string, SaveFile>();

  async list(): Promise<string[]> {
    return [...this.files.keys()];
  }
  async has(name: string): Promise<boolean> {
    return this.files.has(name);
  }
  async save(name: string, file: SaveFile): Promise<void> {
    this.files.set(name, structuredClone(file));
  }
  async load(name: string): Promise<SaveFile | null> {
    const f = this.files.get(name);
    return f ? structuredClone(f) : null;
  }
  async remove(name: string): Promise<void> {
    this.files.delete(name);
  }
  async export(name: string): Promise<SaveFile | null> {
    const f = this.files.get(name);
    return f ? structuredClone(f) : null;
  }
  async import(name: string, file: SaveFile): Promise<void> {
    this.files.set(name, structuredClone(file));
  }
}

/**
 * IndexedDB-backed store for the browser. Lazily opens one DB named
 * 'ember-hollow'; object store 'saves' keyed by slot name.
 */
export class IdbSaveStore implements SaveStore {
  readonly kind = 'idb';
  private db: IDBDatabase | null = null;
  private openPromise: Promise<IDBDatabase> | null = null;

  private open(): Promise<IDBDatabase> {
    if (!this.openPromise) {
      this.openPromise = new Promise((resolve, reject) => {
        const req = indexedDB.open('ember-hollow', 1);
        req.onupgradeneeded = () => {
          const db = req.result;
          if (!db.objectStoreNames.contains('saves')) {
            db.createObjectStore('saves');
          }
        };
        req.onsuccess = () => {
          this.db = req.result;
          resolve(req.result);
        };
        req.onerror = () => reject(req.error);
      });
    }
    return this.openPromise;
  }

  private async tx(mode: IDBTransactionMode): Promise<IDBTransaction> {
    const db = await this.open();
    if (!db.objectStoreNames.contains('saves')) {
      throw new Error('saves store missing');
    }
    return db.transaction('saves', mode);
  }

  private async getAll(): Promise<SaveFile[]> {
    const t = await this.tx('readonly');
    return new Promise((resolve, reject) => {
      const req = t.objectStore('saves').getAll();
      req.onsuccess = () => resolve(req.result as SaveFile[]);
      req.onerror = () => reject(req.error);
    });
  }

  async list(): Promise<string[]> {
    const all = await this.getAll();
    return all.map((f) => (f.state?.meta?.saveName ?? '') as string).filter(Boolean);
  }
  async has(name: string): Promise<boolean> {
    const t = await this.tx('readonly');
    return new Promise((resolve, reject) => {
      const req = t.objectStore('saves').getKey(name);
      req.onsuccess = () => resolve(req.result != null);
      req.onerror = () => reject(req.error);
    });
  }
  async save(name: string, file: SaveFile): Promise<void> {
    const t = await this.tx('readwrite');
    return new Promise((resolve, reject) => {
      t.objectStore('saves').put(structuredClone(file), name);
      t.oncomplete = () => resolve();
      t.onerror = () => reject(t.error);
    });
  }
  async load(name: string): Promise<SaveFile | null> {
    const t = await this.tx('readonly');
    return new Promise((resolve, reject) => {
      const req = t.objectStore('saves').get(name);
      req.onsuccess = () => resolve((req.result as SaveFile) ?? null);
      req.onerror = () => reject(req.error);
    });
  }
  async remove(name: string): Promise<void> {
    const t = await this.tx('readwrite');
    return new Promise((resolve, reject) => {
      t.objectStore('saves').delete(name);
      t.oncomplete = () => resolve();
      t.onerror = () => reject(t.error);
    });
  }
  async export(name: string): Promise<SaveFile | null> {
    return this.load(name);
  }
  async import(name: string, file: SaveFile): Promise<void> {
    return this.save(name, file);
  }
}

/** Default store: IndexedDB when available, otherwise in-memory. */
export function createDefaultSaveStore(): SaveStore {
  if (typeof indexedDB !== 'undefined') return new IdbSaveStore();
  return new MemorySaveStore();
}

export function serializeToJson(file: SaveFile): string {
  return JSON.stringify(file, null, 2);
}

export function parseJson(b: string): SaveFile {
  const out = JSON.parse(b) as SaveFile;
  return { format: out.format, version: out.version, savedAt: out.savedAt, state: out.state };
}