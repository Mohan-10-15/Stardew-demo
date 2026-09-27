/**
 * T-0505 (WORKER-3 lane) — the dev-only SFX cue recorder.
 *
 * The regression this pins: the acceptance harness used to count every
 * oscillator the page created and call that proof that a cue played. The
 * soundtrack synthesises continuously, so a three-second window containing no
 * feedback at all still reported "27 notes" — and a *failed* tool action got a
 * passing verdict purely from background music. These tests make that
 * impossible to re-introduce: cues are named, the SFX log is fed only by
 * `AudioEngine.play()`, and the music path is proven not to touch it.
 */
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import type { DevSfxHandle } from '@game/features/audio/cues';

interface FakeParam {
  value: number;
  setValueAtTime(v: number, t: number): void;
  linearRampToValueAtTime(v: number, t: number): void;
  exponentialRampToValueAtTime(v: number, t: number): void;
}

interface FakeNode {
  kind: string;
  gain: FakeParam;
  frequency: FakeParam;
  type: string;
  start(t: number): void;
  stop(t: number): void;
  linked: FakeNode | null;
  connect(target: FakeNode): void;
  disconnect(): void;
}

function param(initial: number): FakeParam {
  return {
    value: initial,
    setValueAtTime(v: number): void {
      this.value = v;
    },
    linearRampToValueAtTime(v: number): void {
      this.value = v;
    },
    exponentialRampToValueAtTime(v: number): void {
      this.value = v;
    },
  };
}

function fakeNode(kind: string, gain = 1): FakeNode {
  const self: FakeNode = {
    kind,
    gain: param(gain),
    frequency: param(0),
    type: 'sine',
    start(): void {
      /* scheduled */
    },
    stop(): void {
      /* scheduled */
    },
    linked: null,
    connect(target: FakeNode): void {
      self.linked = target;
    },
    disconnect(): void {
      self.linked = null;
    },
  };
  return self;
}

/** The fake context's clock, so the probe can let the bar scheduler advance. */
let fakeNow = 12.5;

class FakeAudioContext {
  state: 'running' | 'suspended' = 'suspended';
  destination: FakeNode = fakeNode('destination');
  oscillators: FakeNode[] = [];
  get currentTime(): number {
    return fakeNow;
  }
  createGain(): FakeNode {
    return fakeNode('gain');
  }
  createOscillator(): FakeNode {
    const osc = fakeNode('oscillator');
    this.oscillators.push(osc);
    return osc;
  }
  resume(): Promise<void> {
    this.state = 'running';
    return Promise.resolve();
  }
}

interface FakeWindow {
  listeners: Map<string, Set<(e: unknown) => void>>;
  AudioContext: unknown;
  setInterval: (fn: () => void, ms: number) => number;
  clearInterval: (id: number) => void;
  timers: Array<() => void>;
}

function makeWindow(): FakeWindow {
  const listeners = new Map<string, Set<(e: unknown) => void>>();
  const timers: Array<() => void> = [];
  const w = {
    listeners,
    timers,
    AudioContext: FakeAudioContext,
    addEventListener(type: string, fn: (e: unknown) => void): void {
      const set = listeners.get(type) ?? new Set<(e: unknown) => void>();
      set.add(fn);
      listeners.set(type, set);
    },
    removeEventListener(type: string, fn: (e: unknown) => void): void {
      listeners.get(type)?.delete(fn);
    },
    setInterval(fn: () => void): number {
      timers.push(fn);
      return timers.length;
    },
    clearInterval(): void {
      /* the probe drives the scheduler by hand */
    },
  } as unknown as FakeWindow;
  return w;
}

type CuesModule = typeof import('@game/features/audio/cues');
type AudioModule = typeof import('@game/features/audio/audio');
type MusicModule = typeof import('@game/features/audio/music');

/** Fresh fake DOM + freshly imported audio lane, so the recorder singleton is new. */
async function withFakeDom(): Promise<{
  cues: CuesModule;
  audio: AudioModule;
  music: MusicModule;
  win: FakeWindow;
  fire: (type: 'keydown' | 'pointerdown') => void;
  /** Run every interval the music scheduler armed. */
  tickMusic: () => void;
}> {
  const win = makeWindow();
  vi.stubGlobal('window', win);
  const [cues, audio, music, context] = await Promise.all([
    import('@game/features/audio/cues'),
    import('@game/features/audio/audio'),
    import('@game/features/audio/music'),
    import('@game/features/audio/context'),
  ]);
  // The gesture hook the real feature installs; without it no context may exist.
  context.installAudioUnlock();
  return {
    cues,
    audio,
    music,
    win,
    fire(type): void {
      for (const fn of [...(win.listeners.get(type) ?? [])]) fn({ type });
    },
    tickMusic(): void {
      // Advance the clock by one 4/4 bar at 96bpm so each run schedules a new
      // bar, the way a real page's interval would.
      fakeNow += 2.5;
      for (const tick of win.timers) tick();
    },
  };
}

beforeEach(() => {
  vi.resetModules();
  fakeNow = 12.5;
});

afterEach(() => {
  vi.unstubAllGlobals();
  vi.unstubAllEnvs();
});

describe('the SFX cue recorder', () => {
  it('records one entry per play() call, carrying the label and the resolved tones', async () => {
    const { audio, cues, fire } = await withFakeDom();
    cues.sfxCueRecorder().clear();
    fire('keydown');

    const engine = new audio.AudioEngine();
    engine.play('tool:success', audio.successTone(), 'tool:used hoe->tilled');

    const entries = cues.sfxCueRecorder().entries();
    expect(entries).toHaveLength(1);
    const entry = entries[0]!;
    expect(entry.cue).toBe('tool:success');
    expect(entry.bus).toBe('sfx');
    expect(entry.source).toBe('tool:used hoe->tilled');
    // The oscillators the call really created, not a re-derivation of the specs.
    expect(entry.voices).toBe(2);
    expect(entry.ctxTime).toBe(12.5);
    expect(entry.at).toBeGreaterThanOrEqual(0);
    expect(entry.tones.map((t) => t.freq)).toEqual([494, 587]);
    expect(entry.tones.map((t) => t.type)).toEqual(['square', 'square']);
    expect(entry.tones.map((t) => t.glide)).toEqual([587, 784]);
    expect(entry.tones[0]!.delay).toBe(0);
    expect(entry.tones[1]!.delay).toBe(0.05);
    // Absolute start times honour the per-note delay, so a probe can time-align
    // the log against a raw oscillator tap.
    expect(entry.tones[0]!.startAt).toBeCloseTo(12.5, 6);
    expect(entry.tones[1]!.startAt).toBeCloseTo(12.55, 6);
  });

  it('separates a success cue from a failure cue by name, not by frequency', async () => {
    const { audio, cues, fire } = await withFakeDom();
    const rec = cues.sfxCueRecorder();
    rec.clear();
    fire('keydown');
    const engine = new audio.AudioEngine();

    engine.play('tool:success', audio.successTone(), 'tool:used hoe->tilled');
    engine.play('tool:failure', audio.failTone(), 'tool:failed hoe:occupied');

    const names = rec.entries().map((e) => e.cue);
    expect(names).toEqual(['tool:success', 'tool:failure']);
    const [ok, bad] = rec.entries();
    // Same bus, different name and different voices: a probe can assert on the
    // name alone and still be right.
    expect(ok!.bus).toBe(bad!.bus);
    expect(ok!.voices).toBe(2);
    expect(bad!.voices).toBe(1);
    expect(bad!.source).toContain('tool:failed');
  });

  it('copies the specs so a later mutation cannot rewrite the log', async () => {
    const { audio, cues, fire } = await withFakeDom();
    const rec = cues.sfxCueRecorder();
    rec.clear();
    fire('keydown');
    const specs = audio.failTone();
    new audio.AudioEngine().play('tool:failure', specs, 'tool:failed hoe:occupied');
    specs[0]!.freq = 9999;
    specs.push({ freq: 12345, dur: 1, type: 'square', gain: 1 });
    const entry = rec.entries()[0]!;
    expect(entry.tones).toHaveLength(1);
    expect(entry.tones[0]!.freq).toBe(233);
  });

  it('exposes a delta helper and a lifetime total that survives the ring dropping entries', async () => {
    const { cues } = await withFakeDom();
    const rec = new cues.SfxCueRecorder();
    const spec = [{ freq: 440, dur: 0.1, type: 'sine' as const, gain: 0.2 }];
    for (let i = 0; i < cues.SfxCueRecorder.RING_CAPACITY + 40; i += 1) {
      rec.recordCue('sale:coin', 'sfx', `shipping:report ${i}`, i, spec, [i]);
    }
    expect(rec.count()).toBe(cues.SfxCueRecorder.RING_CAPACITY);
    expect(rec.total()).toBe(cues.SfxCueRecorder.RING_CAPACITY + 40);
    // A mark taken inside the ring is the offset a probe uses; anything older
    // has already been evicted, which the lifetime total makes visible.
    const mark = rec.count() - 3;
    expect(rec.since(mark)).toHaveLength(3);
    expect(rec.voices()).toBe(cues.SfxCueRecorder.RING_CAPACITY + 40);
    rec.clear();
    expect(rec.count()).toBe(0);
    expect(rec.total()).toBe(0);
  });

  it('records nothing when no AudioContext exists yet', async () => {
    const { audio, cues } = await withFakeDom();
    const rec = cues.sfxCueRecorder();
    rec.clear();
    new audio.AudioEngine().play('tool:success', audio.successTone());
    new audio.AudioEngine().stepTick();
    expect(rec.entries()).toHaveLength(0);
  });

  it('is inert outside a dev build', async () => {
    vi.stubEnv('DEV', false);
    const { cues } = await withFakeDom();
    const rec = new cues.SfxCueRecorder();
    cues.recordSfxCue('tool:success', 'sfx', 'tool:used hoe->tilled', 0, [{ freq: 494, dur: 0.08, type: 'square', gain: 0.3 }], [0]);
    cues.recordMusicBar(3, 'day', 9, 0);
    expect(rec.entries()).toHaveLength(0);
    expect(cues.sfxCueRecorder().barCount()).toBe(0);
    const published: unknown = (globalThis as { __EH_SFX__?: unknown }).__EH_SFX__;
    expect(published).toBeUndefined();
  });
});

describe('the music path stays out of the SFX cue log', () => {
  it('schedules bars and notes without recording a single SFX cue', async () => {
    const { music, cues, fire, tickMusic } = await withFakeDom();
    const rec = cues.sfxCueRecorder();
    rec.clear();
    fire('keydown');

    const song = new music.MusicEngine(12345);
    song.setTheme(
      music.resolveMusicTheme({ hour: 12, weather: 'sun', seasonIndex: 0, mapId: 'farm', healthPct: 1 }),
    );
    song.setEnabled(true);
    for (let i = 0; i < 4; i += 1) tickMusic();
    song.dispose();

    const totals = rec.barTotals();
    expect(totals.bars).toBeGreaterThan(0);
    expect(totals.notes).toBeGreaterThan(0);
    expect(rec.barEntries().every((b) => b.mood === 'day')).toBe(true);
    // The whole point: the soundtrack was genuinely playing, and the SFX cue log
    // is still empty because music never goes through AudioEngine.play().
    expect(rec.entries()).toHaveLength(0);
    expect(rec.total()).toBe(0);
  });

  it('records music and cues side by side without mixing them', async () => {
    const { audio, music, cues, fire, tickMusic } = await withFakeDom();
    const rec = cues.sfxCueRecorder();
    rec.clear();
    fire('keydown');

    const song = new music.MusicEngine(7);
    song.setTheme(
      music.resolveMusicTheme({ hour: 12, weather: 'sun', seasonIndex: 0, mapId: 'farm', healthPct: 1 }),
    );
    song.setEnabled(true);
    tickMusic();
    new audio.AudioEngine().play('tool:success', audio.successTone(), 'tool:used hoe->tilled');
    tickMusic();
    song.dispose();

    expect(rec.entries().map((e) => e.cue)).toEqual(['tool:success']);
    expect(rec.entries().every((e) => e.bus === 'sfx')).toBe(true);
    expect(rec.barTotals().bars).toBeGreaterThanOrEqual(2);
  });
});

describe('the published dev handle', () => {
  it('exposes cues, deltas, music bars and the live bus state', async () => {
    const { audio, fire } = await withFakeDom();
    const { audioUi } = audio;
    const { EventBus } = await import('@game/core/events');
    const { audioContextCount } = await import('@game/features/audio/context');
    const bus = new EventBus();
    audioUi.setup!({
      store: { state: null, dispatch: () => undefined },
      bus,
      rng: null,
      content: null,
      headless: true,
      getRenderer: () => undefined,
      getConfig: () => ({}),
      persist: async () => undefined,
    } as unknown as Parameters<NonNullable<typeof audioUi.setup>>[0]);

    const handle = (globalThis as { __EH_SFX__?: DevSfxHandle }).__EH_SFX__;
    expect(handle).toBeDefined();
    expect(handle!.cues()).toHaveLength(0);
    expect(handle!.audio()).toEqual({ bus: null, state: 'none', contexts: 0 });

    fire('keydown');
    expect(handle!.audio()).toEqual({ bus: 'sfx', state: 'running', contexts: audioContextCount() });

    handle!.clear();
    const mark = handle!.count();
    bus.emit('tool:used', { tile: { mapId: 'farm', x: 3, y: 4 }, toolId: 'hoe', effect: 'tilled' });
    const delta = handle!.since(mark);
    expect(delta).toHaveLength(1);
    expect(delta[0]!.cue).toBe('tool:success');
    expect(delta[0]!.source).toBe('tool:used hoe->tilled');
    expect(handle!.totals().voices).toBe(2);
  });
});

describe('the feature maps every game event to a named cue', () => {
  it('names the success and the failure of the same tool differently', async () => {
    const { audio, fire } = await withFakeDom();
    const { EventBus } = await import('@game/core/events');
    const { sfxCueRecorder } = await import('@game/features/audio/cues');
    const bus = new EventBus();
    audio.audioUi.setup!({
      store: { state: null, dispatch: () => undefined },
      bus,
      rng: null,
      content: null,
      headless: true,
      getRenderer: () => undefined,
      getConfig: () => ({}),
      persist: async () => undefined,
    } as unknown as Parameters<NonNullable<typeof audio.audioUi.setup>>[0]);

    const rec = sfxCueRecorder();
    rec.clear();
    fire('keydown');

    const tile = { mapId: 'farm', x: 3, y: 4 };
    bus.emit('tool:used', { tile, toolId: 'hoe', effect: 'tilled' });
    bus.emit('tool:failed', { tile, toolId: 'hoe', reason: 'occupied' });

    const entries = rec.entries();
    expect(entries.map((e) => e.cue)).toEqual(['tool:success', 'tool:failure']);
    expect(entries.map((e) => e.source)).toEqual([
      'tool:used hoe->tilled',
      'tool:failed hoe:occupied',
    ]);
    // Same event shape, opposite feedback: the two recorded tone sets differ.
    expect(entries[0]!.tones.map((t) => t.freq)).toEqual([494, 587]);
    expect(entries[1]!.tones.map((t) => t.freq)).toEqual([233]);
    expect(entries.every((e) => e.bus === 'sfx')).toBe(true);
  });

  it('names shipping and footsteps too', async () => {
    const { audio, fire } = await withFakeDom();
    const { EventBus } = await import('@game/core/events');
    const { sfxCueRecorder } = await import('@game/features/audio/cues');
    const bus = new EventBus();
    audio.audioUi.setup!({
      store: { state: null, dispatch: () => undefined },
      bus,
      rng: null,
      content: null,
      headless: true,
      getRenderer: () => undefined,
      getConfig: () => ({}),
      persist: async () => undefined,
    } as unknown as Parameters<NonNullable<typeof audio.audioUi.setup>>[0]);
    const rec = sfxCueRecorder();
    rec.clear();
    fire('keydown');

    bus.emit('shipping:report', { sold: [{ id: 'parsnip', qty: 2, quality: 0 }], total: 70 });
    bus.emit('shipping:report', { sold: [], total: 0 });
    bus.emit('player:moved', { x: 1, y: 0 });

    expect(rec.entries().map((e) => e.cue)).toEqual(['sale:coin', 'player:footstep']);
    expect(rec.entries()[0]!.source).toBe('shipping:report 1 lines 70g');
  });
});
