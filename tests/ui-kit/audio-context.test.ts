/**
 * T-0503 (WORKER-3 lane) — the shared, gesture-gated AudioContext.
 *
 * The regression this pins is the one from the brief: "creating more than one
 * AudioContext" and "starting audio before a user gesture". Both are invisible
 * in a normal unit test because vitest runs off-DOM, so this file stands up a
 * minimal fake `window`/`AudioContext` and counts constructions while the real
 * `AudioEngine` and `MusicEngine` run their normal `ensure()`/`play()` paths.
 */
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

interface FakeParam {
  value: number;
  setValueAtTime(v: number, t: number): void;
  linearRampToValueAtTime(v: number, t: number): void;
  exponentialRampToValueAtTime(v: number, t: number): void;
}

interface FakeNode {
  kind: string;
  gain: FakeParam;
  /** Oscillators only. */
  frequency: FakeParam;
  type: string;
  start(t: number): void;
  stop(t: number): void;
  /** Only this fake's `connect` target, so the test can walk the graph. */
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
    start(_t: number): void {
      /* scheduled */
    },
    stop(_t: number): void {
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

class FakeAudioContext {
  state: 'running' | 'suspended' = 'suspended';
  currentTime = 0;
  destination: FakeNode = fakeNode('destination');
  resumes = 0;
  oscillators: FakeNode[] = [];
  constructor() {
    contexts.push(this);
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
    this.resumes += 1;
    this.state = 'running';
    return Promise.resolve();
  }
}

interface FakeWindow {
  listeners: Map<string, Set<(e: unknown) => void>>;
  AudioContext: unknown;
}

const contexts: FakeAudioContext[] = [];
const windows: FakeWindow[] = [];

function makeWindow(): FakeWindow {
  const listeners = new Map<string, Set<(e: unknown) => void>>();
  const w = {
    listeners,
    AudioContext: FakeAudioContext,
    addEventListener(type: string, fn: (e: unknown) => void): void {
      const set = listeners.get(type) ?? new Set<(e: unknown) => void>();
      set.add(fn);
      listeners.set(type, set);
    },
    removeEventListener(type: string, fn: (e: unknown) => void): void {
      listeners.get(type)?.delete(fn);
    },
    setInterval: (): number => 1,
    clearInterval: (): void => undefined,
  } as unknown as FakeWindow;
  windows.push(w);
  return w;
}

function fire(type: 'keydown' | 'pointerdown'): void {
  for (const w of windows) {
    for (const fn of [...(w.listeners.get(type) ?? [])]) fn({ type });
  }
}

type ContextModule = typeof import('@game/features/audio/context');
type AudioModule = typeof import('@game/features/audio/audio');
type MusicModule = typeof import('@game/features/audio/music');

/** Put a fake window in place and return the freshly imported audio lane. */
async function withFakeDom(): Promise<{
  context: ContextModule;
  audio: AudioModule;
  music: MusicModule;
}> {
  makeWindow();
  vi.stubGlobal('window', windows[windows.length - 1]);
  const [context, audio, music] = await Promise.all([
    import('@game/features/audio/context'),
    import('@game/features/audio/audio'),
    import('@game/features/audio/music'),
  ]);
  return { context, audio, music };
}

function themeOf(music: MusicModule) {
  return music.resolveMusicTheme({
    hour: 12,
    weather: 'sun',
    seasonIndex: 0,
    mapId: 'farm',
    healthPct: 1,
  });
}

beforeEach(() => {
  vi.resetModules();
  contexts.length = 0;
  windows.length = 0;
});

afterEach(() => {
  vi.unstubAllGlobals();
});

describe('the single shared context', () => {
  it('builds nothing before a real gesture', async () => {
    const { context, audio, music } = await withFakeDom();
    context.installAudioUnlock();
    expect(context.audioGestureSeen()).toBe(false);
    expect(context.audioBuses()).toBeNull();
    expect(new audio.AudioEngine().ensure()).toBe(false);
    expect(new music.MusicEngine().ensure()).toBe(false);
    // Asking repeatedly must not "warm up" the context.
    expect(context.audioBuses()).toBeNull();
    expect(contexts).toHaveLength(0);
    expect(context.audioContextCount()).toBe(0);
  });

  it('is created once on keydown and shared by the sfx + music engines', async () => {
    const { context, audio, music } = await withFakeDom();
    context.installAudioUnlock();
    fire('keydown');
    expect(context.audioGestureSeen()).toBe(true);
    const buses = context.audioBuses();
    expect(buses).not.toBeNull();
    expect(contexts).toHaveLength(1);
    expect(context.audioContextCount()).toBe(1);

    const sfx = new audio.AudioEngine();
    const song = new music.MusicEngine();
    expect(sfx.ensure()).toBe(true);
    expect(song.ensure()).toBe(true);
    sfx.play(audio.coinTone());
    expect(contexts[0]!.oscillators.length).toBe(audio.coinTone().length);
    // ...and a second gesture must not mint a second context.
    fire('pointerdown');
    expect(context.audioBuses()).toBe(buses);
    expect(context.audioContextCount()).toBe(1);
    expect(contexts).toHaveLength(1);
    song.dispose();
  });

  it('resumes a suspended context instead of building a new one', async () => {
    const { context, audio } = await withFakeDom();
    context.installAudioUnlock();
    fire('keydown');
    const buses = context.audioBuses()!;
    const ctx = contexts[0]!;
    expect(buses.ctx.state).toBe('running');
    expect(ctx.resumes).toBeGreaterThan(0);
    const resumes = ctx.resumes;
    new audio.AudioEngine().ensure();
    expect(ctx.resumes).toBe(resumes);
    expect(contexts).toHaveLength(1);
  });

  it('stacks only one pair of gesture listeners however many features install', async () => {
    const { context } = await withFakeDom();
    const first = context.installAudioUnlock();
    const second = context.installAudioUnlock();
    expect(second).toBe(first);
    expect(windows[0]!.listeners.get('keydown')!.size).toBe(1);
    expect(context.audioGestureSeen()).toBe(false);
    fire('keydown');
    expect(context.audioContextCount()).toBe(1);
    first();
    expect(windows[0]!.listeners.get('keydown')!.size).toBe(0);
  });
});

describe('bus staging', () => {
  it('keeps music audibly under sfx and the whole graph under master', async () => {
    const { context } = await withFakeDom();
    expect(context.SFX_BUS_GAIN).toBe(1);
    expect(context.MUSIC_BUS_GAIN).toBeLessThan(context.SFX_BUS_GAIN * 0.5);
    expect(context.MASTER_GAIN).toBe(1);
    context.installAudioUnlock();
    fire('keydown');
    const buses = context.audioBuses()!;
    const sfx = buses.sfx as unknown as FakeNode;
    const song = buses.music as unknown as FakeNode;
    const master = buses.master as unknown as FakeNode;
    expect(sfx.gain.value).toBe(context.SFX_BUS_GAIN);
    expect(song.gain.value).toBe(context.MUSIC_BUS_GAIN);
    expect(master.gain.value).toBe(context.MASTER_GAIN);
    expect(sfx.linked).toBe(master);
    expect(song.linked).toBe(master);
    expect(master.linked).toBe(buses.ctx.destination as unknown as FakeNode);
  });

  it('routes music through a per-engine volume node, leaving the staging intact', async () => {
    const { context, music } = await withFakeDom();
    context.installAudioUnlock();
    fire('keydown');
    const buses = context.audioBuses()!;
    const staging = (buses.music as unknown as FakeNode).gain.value;
    const song = new music.MusicEngine();
    song.setTheme(themeOf(music));
    song.setEnabled(true);
    expect(song.ensure()).toBe(true);
    song.setVolume(1);
    // The player's volume must not stomp MUSIC_BUS_GAIN, otherwise a loud
    // preference would lift the soundtrack on top of the cues.
    expect((buses.music as unknown as FakeNode).gain.value).toBe(context.MUSIC_BUS_GAIN);
    expect((buses.music as unknown as FakeNode).gain.value).toBe(staging);
    song.setVolume(0.25);
    expect(song.getVolume()).toBe(0.25);
    expect((buses.music as unknown as FakeNode).gain.value).toBe(context.MUSIC_BUS_GAIN);
    song.dispose();
    expect((buses.music as unknown as FakeNode).gain.value).toBe(context.MUSIC_BUS_GAIN);
  });
});

describe('off-DOM safety', () => {
  it('degrades to silence with no window at all', async () => {
    vi.stubGlobal('window', undefined);
    const context = await import('@game/features/audio/context');
    expect(typeof window).toBe('undefined');
    const teardown = context.installAudioUnlock();
    expect(teardown).toBeTypeOf('function');
    teardown();
    expect(context.audioBuses()).toBeNull();
    expect(context.sharedAudioContext()).toBeNull();
    expect(context.audioContextCount()).toBe(0);
  });
});
