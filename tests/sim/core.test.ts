import { describe, expect, it } from 'vitest';
import { Rng, hashSeed } from '@game/core/rng';
import { advanceClock, startNewDay, weekOf } from '@game/core/time';
import { Store } from '@game/core/store';
import { MemorySaveStore, migrateSave, slotName, wrapSave } from '@game/core/save';
import { createInitialState } from '@game/core/state';
import { EventBus } from '@game/core/events';
import type { GameState, SimAction, WorldState } from '@game/core/types';
import { PASS_OUT_HOUR } from '@game/core/types';

describe('Rng', () => {
  it('is deterministic for equal seeds and diverges for different seeds', () => {
    const a = new Rng(1234);
    const b = new Rng(1234);
    const c = new Rng(9999);
    const seqA = Array.from({ length: 20 }, () => a.next());
    const seqB = Array.from({ length: 20 }, () => b.next());
    const seqC = Array.from({ length: 20 }, () => c.next());
    expect(seqA).toEqual(seqB);
    expect(seqA).not.toEqual(seqC);
  });

  it('draws ints, weighted picks and stable forks', () => {
    const r = new Rng(42);
    for (let i = 0; i < 100; i++) {
      const v = r.int(1, 6);
      expect(v).toBeGreaterThanOrEqual(1);
      expect(v).toBeLessThanOrEqual(6);
    }
    const r2 = new Rng(7);
    const pick = r2.weighted([
      { value: 'a', weight: 1 },
      { value: 'b', weight: 1000 },
    ]);
    expect(pick).toBe('b');
    const f1 = new Rng(7).fork('farm');
    const f2 = new Rng(7).fork('farm');
    expect(f1.next()).toBe(f2.next());
  });

  it('hashSeed is stable and spread out', () => {
    expect(hashSeed('parsnip')).toBe(hashSeed('parsnip'));
    expect(hashSeed('parsnip')).not.toBe(hashSeed('potato'));
    expect(hashSeed('potato-seed')).not.toBe(hashSeed('seed-potato'));
  });
});

describe('clock + calendar', () => {
  function baseWorld(): WorldState {
    return {
      calendar: { year: 1, seasonIndex: 0, dayOfMonth: 1 },
      clock: { hour: 6, minute: 0 },
      weather: 'sun',
      forecast: ['sun', 'sun', 'sun'],
      dayCount: 1,
      passedOut: false,
      playSeconds: 0,
    };
  }

  it('advances 10-minute ticks', () => {
    const w = baseWorld();
    const t = advanceClock(w, 10);
    expect(t.world.clock).toEqual({ hour: 6, minute: 10 });
    expect(t.dayRolled).toBe(false);
  });

  it('rolls the day and season/year correctly', () => {
    let w: WorldState = { ...baseWorld(), calendar: { year: 1, seasonIndex: 0, dayOfMonth: 28 }, clock: { hour: 23, minute: 40 } };
    let t = advanceClock(w, 30);
    expect(t.dayRolled).toBe(true);
    expect(t.world.calendar).toEqual({ year: 1, seasonIndex: 1, dayOfMonth: 1 });
    expect(t.world.dayCount).toBe(2);
    w = { ...t.world, calendar: { year: 1, seasonIndex: 3, dayOfMonth: 28 } };
    t = advanceClock(w, 10);
    expect(t.seasonRolled).toBe(true);
    expect(t.world.calendar).toEqual({ year: 2, seasonIndex: 0, dayOfMonth: 1 });
  });

  it('passes out at 2:00 AM', () => {
    const w = { ...baseWorld(), clock: { hour: 1, minute: 50 } };
    const t = advanceClock(w, 10);
    expect(t.passedOut).toBe(true);
    expect(t.world.clock.hour).toBe(PASS_OUT_HOUR);
  });

  it('startNewDay resets to 6:00', () => {
    const w = { ...baseWorld(), clock: { hour: 22, minute: 30 }, passedOut: true };
    const next = startNewDay(w);
    expect(next.clock).toEqual({ hour: 6, minute: 0 });
    expect(next.passedOut).toBe(false);
  });

  it('weekOf groups days', () => {
    expect(weekOf(1)).toBe(0);
    expect(weekOf(7)).toBe(0);
    expect(weekOf(8)).toBe(1);
  });
});

describe('Store', () => {
  it('applies registered reducers and broadcasts changes', () => {
    const state = createInitialState(1, 'test');
    const store = new Store(state, new Rng(1));
    const events: number[] = [];
    store.bus.on<GameState>('state:changed', (s) => events.push(s.player.money));
    store.registerReducer('test:set-money', (st: GameState, action: SimAction<any, unknown>) => ({
      ...st,
      player: { ...st.player, money: (action.payload as { amount: number }).amount },
    }));
    store.dispatch({ type: 'test:set-money', payload: { amount: 999 } });
    expect(store.state.player.money).toBe(999);
    expect(events).toEqual([999]);
  });

  it('rejects duplicate reducer ids', () => {
    const store = new Store(createInitialState(2, 'test2'), new Rng(2));
    store.registerReducer('dup', () => store.state);
    expect(() => store.registerReducer('dup', () => store.state)).not.toThrow();
  });
});

describe('EventBus', () => {
  it('buffers for late subscribers', () => {
    const bus = new EventBus();
    bus.emit('thing', 42);
    const seen: number[] = [];
    bus.on('thing', (n: number) => seen.push(n));
    expect(seen).toEqual([42]);
    bus.emit('thing', 7);
    expect(seen).toEqual([42, 7]);
  });

  it('unsubscribes cleanly', () => {
    const bus = new EventBus();
    let count = 0;
    const off = bus.on('x', () => count++);
    bus.emit('x', null);
    off();
    bus.emit('x', null);
    expect(count).toBe(1);
  });
});

describe('save roundtrip', () => {
  it('wrap + migrate survives and preserves intent', () => {
    const state = createInitialState(77, 'roundtrip');
    state.player.money = 12345;
    state.player.inventory.slots[0] = { id: 'parsnip', qty: 4, quality: 0 };
    const file = wrapSave(state);
    const restored = migrateSave(JSON.parse(JSON.stringify(file)) as Parameters<typeof migrateSave>[0]);
    expect(restored.player.money).toBe(12345);
    expect(restored.player.inventory.slots[0]).toEqual({ id: 'parsnip', qty: 4, quality: 0 });
    expect(restored.version).toBe(1);
  });

  it('sanitizeState backfills missing nested fields', () => {
    const raw = {
      format: 'ember-hollow',
      version: 1,
      savedAt: 0,
      state: { player: { name: 'X', energyMax: 270 } },
    } as unknown as Parameters<typeof migrateSave>[0];
    const fixed = migrateSave(raw);
    expect(fixed.player.energyMax).toBe(270);
    expect(fixed.player.energy).toBe(270);
  });

  it('slot names are bounded', () => {
    expect(slotName(0)).toBe('slot1');
    expect(slotName(2)).toBe('slot3');
    expect(() => slotName(3)).toThrow();
  });

  it('memory store persists across saves', async () => {
    const store = new MemorySaveStore();
    const s1 = wrapSave(createInitialState(5, 'a'));
    await store.save('slot1', s1);
    expect(await store.has('slot1')).toBe(true);
    const loaded = await store.load('slot1');
    expect(loaded?.state.rngSeed).toBe(5);
    await store.remove('slot1');
    expect(await store.load('slot1')).toBeNull();
  });
});