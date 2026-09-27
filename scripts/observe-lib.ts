/**
 * Browser observation harness (ORCHESTRATOR, core lane - test infra).
 *
 * "The tests pass" is not the same as "the game feels right", so everything
 * here boots the real game in a real Chromium, drives it with real key events,
 * and reports what actually happened: positions sampled every animation frame,
 * colours read back out of the WebGL canvas, and an audio transcript of every
 * oscillator the game scheduled.
 *
 * No assertions live here - this module observes and prints. The pass/fail
 * judgement belongs in docs/ACCEPTANCE.md, checked on top of this.
 */
import { chromium, type Page } from 'playwright';

export interface ConsoleLine {
  type: string;
  text: string;
}

export interface Observed {
  page: Page;
  console: ConsoleLine[];
  errors: ConsoleLine[];
  /** Boot ok: the dev hook appeared, i.e. the game finished booting. */
  booted: boolean;
  close: () => Promise<void>;
}

const BOOT_TIMEOUT_MS = 25_000;

export interface DevHook {
  runtime: {
    content: { maps: Map<string, { legend: Record<string, { walkable?: boolean }> }> };
  };
  store: {
    state: {
      player: {
        position: { mapId: string; x: number; y: number };
        facing: string;
        energy: number;
        inventory: { slots: Array<{ id: string; qty: number } | null>; selected: number };
      };
      world: { weather: string; clock: { hour: number; minute: number }; dayCount: number };
      maps: Record<
        string,
        { grid: { width: number; height: number; tiles: string[] }; placed: Record<string, { id: string; data?: unknown }> }
      >;
    };
    replaceState: (s: unknown) => void;
  };
  bus: {
    on: (t: string, fn: (p: unknown) => void) => () => void;
    emit: (t: string, p?: unknown) => void;
  };
  player: () => DevHook['store']['state']['player'];
}

interface WindowWithHook extends Window {
  __EH__?: DevHook;
  __EH_SAMPLE__?: boolean;
  __EH_SAMPLES__?: Array<{ t: number; x: number; y: number }>;
  __EH_EVENTS__?: Array<{ type: string; payload: unknown; at: number }>;
  __EH_AUDIO__?: Array<Record<string, unknown>>;
  __EH_AUDIO_CTX_COUNT__?: number;
  __EH_CTX__?: { state: string };
}

/**
 * Installed before any page script runs. Wraps createOscillator/createGain so
 * the transcript records the actual synthesis calls - the frequency, the
 * waveform, the envelope peak - instead of guessing from the source.
 */
const PAGE_TAP = `
(() => {
  const w = window;
  w.__EH_EVENTS__ = [];
  w.__EH_SAMPLES__ = [];
  w.__EH_AUDIO__ = [];
  w.__EH_AUDIO_CTX_COUNT__ = 0;
  const NativeCtx = w.AudioContext || w.webkitAudioContext;
  if (!NativeCtx) return;
  const origOsc = NativeCtx.prototype.createOscillator;
  const origGain = NativeCtx.prototype.createGain;
  NativeCtx.prototype.createOscillator = function () {
    const osc = origOsc.call(this);
    const rec = { kind: 'osc', type: 'sine', freqStart: null, freqEnd: null, at: performance.now() };
    const f = osc.frequency;
    const fSet = f.setValueAtTime.bind(f);
    const fRamp = f.exponentialRampToValueAtTime.bind(f);
    f.setValueAtTime = (v, t) => { rec.freqStart = v; return fSet(v, t); };
    f.exponentialRampToValueAtTime = (v, t) => { rec.freqEnd = v; return fRamp(v, t); };
    const typeDesc = Object.getOwnPropertyDescriptor(Object.getPrototypeOf(osc), 'type');
    Object.defineProperty(osc, 'type', {
      configurable: true,
      get() { return typeDesc ? typeDesc.value : 'sine'; },
      set(v) { rec.type = v; if (typeDesc) typeDesc.set.call(osc, v); },
    });
    rec.freqStart = f.value;
    osc.addEventListener('ended', () => { w.__EH_AUDIO__.push(rec); }, { once: true });
    return osc;
  };
  NativeCtx.prototype.createGain = function () {
    const g = origGain.call(this);
    const rec = { kind: 'gain', peak: 0, at: performance.now() };
    const gSet = g.gain.setValueAtTime.bind(g.gain);
    const gLin = g.gain.linearRampToValueAtTime.bind(g.gain);
    g.gain.setValueAtTime = (v, t) => { rec.peak = Math.max(rec.peak, v); return gSet(v, t); };
    g.gain.linearRampToValueAtTime = (v, t) => { rec.peak = Math.max(rec.peak, v); return gLin(v, t); };
    rec.peak = g.gain.value;
    g.addEventListener('ended', () => { w.__EH_AUDIO__.push(rec); }, { once: true });
    return g;
  };
  const OrigCtx = NativeCtx;
  function PatchedCtx(...args) {
    w.__EH_AUDIO_CTX_COUNT__++;
    const c = new OrigCtx(...args);
    w.__EH_CTX__ = c;
    return c;
  }
  PatchedCtx.prototype = OrigCtx.prototype;
  w.AudioContext = PatchedCtx;
})();
`;

export async function observe(
  opts: { url?: string; width?: number; height?: number } = {},
): Promise<Observed> {
  const url = opts.url ?? process.env['EH_URL'] ?? 'http://localhost:2026/';
  const browser = await chromium.launch({ args: ['--autoplay-policy=no-user-gesture-required'] });
  const page = await browser.newPage({ viewport: { width: opts.width ?? 1280, height: opts.height ?? 800 } });
  const lines: ConsoleLine[] = [];
  page.on('console', (m) => lines.push({ type: m.type(), text: m.text() }));
  page.on('pageerror', (e) => lines.push({ type: 'pageerror', text: e.message }));
  await page.addInitScript(PAGE_TAP);
  await page.goto(url, { waitUntil: 'load' });
  let booted = false;
  try {
    await page.waitForFunction(() => Boolean((window as WindowWithHook).__EH__), undefined, {
      timeout: BOOT_TIMEOUT_MS,
    });
    booted = true;
  } catch {
    booted = false;
  }
  // Tap the bus as soon as the hook exists so no sim event is missed.
  if (booted) await tapBus(page);
  await page.waitForTimeout(800);
  return {
    page,
    console: lines,
    errors: lines.filter((l) => l.type === 'error' || l.type === 'pageerror'),
    booted,
    close: () => browser.close(),
  };
}

/** Mirror every sim/bus event into a page-side log the harness can read back. */
export async function tapBus(page: Page): Promise<void> {
  await page.evaluate(() => {
    const w = window as WindowWithHook;
    if (!w.__EH__ || (w as unknown as { __EH_TAPPED__?: boolean }).__EH_TAPPED__) return;
    (w as unknown as { __EH_TAPPED__?: boolean }).__EH_TAPPED__ = true;
    const emit = w.__EH__!.bus.emit.bind(w.__EH__!.bus);
    (w.__EH__!.bus as unknown as { emit: (t: string, p?: unknown) => void }).emit = (t, p) => {
      w.__EH_EVENTS__!.push({ type: t, payload: p ?? null, at: performance.now() });
      return emit(t, p);
    };
  });
}

export interface PlayerSnapshot {
  mapId: string;
  x: number;
  y: number;
  facing: string;
  energy: number;
  selected: number;
  heldItem: string | null;
  weather: string;
  hour: number;
  minute: number;
  dayCount: number;
}

export async function playerState(page: Page): Promise<PlayerSnapshot> {
  return page.evaluate(() => {
    const st = (window as WindowWithHook).__EH__!.store.state;
    const stack = st.player.inventory.slots[st.player.inventory.selected];
    return {
      mapId: st.player.position.mapId,
      x: st.player.position.x,
      y: st.player.position.y,
      facing: st.player.facing,
      energy: st.player.energy,
      selected: st.player.inventory.selected,
      heldItem: stack ? `${stack.id} x${stack.qty}` : null,
      weather: st.world.weather,
      hour: st.world.clock.hour,
      minute: st.world.clock.minute,
      dayCount: st.world.dayCount,
    };
  });
}

export interface WalkTrace {
  from: { x: number; y: number };
  to: { x: number; y: number };
  distance: number;
  frames: number;
  movingFrames: number;
  maxStep: number;
  minStep: number;
  /** Moving frames that advanced less than 90% of the full step. The collision
   *  sampler legitimately leaves a partial sub-step when a frame clips geometry,
   *  so a couple of these are not a stutter; a majority of them would be. */
  partialSteps: number;
  integerPositions: number;
  elapsedMs: number;
  speedPerSec: number;
}

/**
 * Hold keys for `ms` while sampling the player position every animation frame.
 * The samples are the point: "arrived 8 tiles away" and "glided there" are
 * different results, and only the curve tells them apart.
 */
export async function holdAndSample(page: Page, keys: string[], ms: number): Promise<WalkTrace> {
  const before = await playerState(page);
  await page.evaluate(() => {
    const w = window as WindowWithHook;
    w.__EH_SAMPLE__ = true;
    w.__EH_SAMPLES__ = [];
    const tick = (): void => {
      const pos = w.__EH__!.store.state.player.position;
      w.__EH_SAMPLES__!.push({ t: performance.now(), x: pos.x, y: pos.y });
      if (w.__EH_SAMPLE__) requestAnimationFrame(tick);
    };
    requestAnimationFrame(tick);
  });
  for (const k of keys) await page.keyboard.down(k);
  await page.waitForTimeout(ms);
  for (const k of keys) await page.keyboard.up(k);
  const samples = await page.evaluate(() => {
    (window as WindowWithHook).__EH_SAMPLE__ = false;
    return (window as WindowWithHook).__EH_SAMPLES__ ?? [];
  });
  const after = await playerState(page);
  let movingFrames = 0;
  let maxStep = 0;
  let minStep = Number.POSITIVE_INFINITY;
  let integerPositions = 0;
  // Frames that advanced less than the full step. The collision sampler splits a
  // frame into MAX_STEP sub-steps and the last one can be a remainder, so a
  // frame that clips geometry legitimately shows a partial step. What would be a
  // stutter is a frame that is short for any other reason.
  let partialSteps = 0;
  const perFrame: number[] = [];
  for (let i = 1; i < samples.length; i++) {
    const a = samples[i - 1]!;
    const b = samples[i]!;
    const step = Math.hypot(b.x - a.x, b.y - a.y);
    if (step > 1e-6) movingFrames++;
    if (step > maxStep) maxStep = step;
    if (step > 0 && step < minStep) minStep = step;
    perFrame.push(step);
  }
  for (const step of perFrame) {
    if (step > 0 && step < maxStep * 0.9) partialSteps++;
  }
  for (const s of samples) {
    if (Number.isInteger(s.x) && Number.isInteger(s.y)) integerPositions++;
  }
  const elapsedMs = samples.length > 1 ? samples[samples.length - 1]!.t - samples[0]!.t : 0;
  const distance = Math.hypot(after.x - before.x, after.y - before.y);
  return {
    from: { x: before.x, y: before.y },
    to: { x: after.x, y: after.y },
    distance,
    frames: samples.length,
    movingFrames,
    maxStep: round(maxStep),
    minStep: Number.isFinite(minStep) ? round(minStep) : 0,
    partialSteps,
    integerPositions,
    elapsedMs: Math.round(elapsedMs),
    speedPerSec: elapsedMs > 0 ? round((distance / elapsedMs) * 1000) : 0,
  };
}

function round(n: number): number {
  return Math.round(n * 1000) / 1000;
}

export interface CanvasStats {
  width: number;
  height: number;
  meanRGB: [number, number, number];
  redFraction: number;
  uniqueColors: number;
}

/** Read the live WebGL canvas back as pixels: mean colour, how much of the
 *  frame is red, and how many distinct colours are on screen. */
export async function canvasStats(page: Page): Promise<CanvasStats> {
  const buf = await page.locator('#game-root canvas').screenshot();
  return page.evaluate(async (b64) => {
    const blob = await fetch(`data:image/png;base64,${b64}`).then((r) => r.blob());
    const bmp = await createImageBitmap(blob);
    const cv = new OffscreenCanvas(bmp.width, bmp.height);
    const g = cv.getContext('2d');
    if (!g) throw new Error('no 2d canvas');
    g.drawImage(bmp, 0, 0);
    const { data, width, height } = g.getImageData(0, 0, bmp.width, bmp.height);
    let r = 0;
    let gg = 0;
    let b = 0;
    let red = 0;
    const seen = new Set<number>();
    const n = width * height;
    for (let i = 0; i < n; i++) {
      const R = data[i * 4] ?? 0;
      const G = data[i * 4 + 1] ?? 0;
      const B = data[i * 4 + 2] ?? 0;
      r += R;
      gg += G;
      b += B;
      if (R > 140 && R > G * 1.5 && R > B * 1.5) red++;
      if (seen.size < 6000) seen.add(((R >> 3) << 10) | ((G >> 3) << 5) | (B >> 3));
    }
    return {
      width,
      height,
      meanRGB: [Math.round(r / n), Math.round(gg / n), Math.round(b / n)],
      redFraction: Math.round((red / n) * 1000) / 1000,
      uniqueColors: seen.size,
    };
  }, buf.toString('base64'));
}

/** Mean colour of one rectangle of the canvas, so a single tile's highlight or
 *  a tilled-soil decal can be checked precisely instead of eyeballed. */
export async function regionColor(
  page: Page,
  x: number,
  y: number,
  w: number,
  h: number,
): Promise<[number, number, number]> {
  const buf = await page.locator('#game-root canvas').screenshot();
  return page.evaluate(
    async ({ b64, x, y, w, h }) => {
      const blob = await fetch(`data:image/png;base64,${b64}`).then((r) => r.blob());
      const bmp = await createImageBitmap(blob);
      const cv = new OffscreenCanvas(bmp.width, bmp.height);
      const g = cv.getContext('2d');
      if (!g) throw new Error('no 2d canvas');
      g.drawImage(bmp, 0, 0);
      const d = g.getImageData(x, y, w, h).data;
      let r = 0;
      let gg = 0;
      let b = 0;
      const n = d.length / 4;
      for (let i = 0; i < n; i++) {
        r += d[i * 4] ?? 0;
        gg += d[i * 4 + 1] ?? 0;
        b += d[i * 4 + 2] ?? 0;
      }
      return [Math.round(r / n), Math.round(gg / n), Math.round(b / n)];
    },
    { b64: buf.toString('base64'), x, y, w, h },
  );
}

export interface AudioNote {
  type: string | null;
  freqStart: number | null;
  freqEnd: number | null;
  peak: number;
  at: number;
}

export interface AudioTranscript {
  contexts: number;
  state: string;
  notes: AudioNote[];
}

export async function audioTranscript(page: Page): Promise<AudioTranscript> {
  return page.evaluate(() => {
    const w = window as WindowWithHook;
    const raw = w.__EH_AUDIO__ ?? [];
    return {
      contexts: w.__EH_AUDIO_CTX_COUNT__ ?? 0,
      state: w.__EH_CTX__?.state ?? 'none',
      notes: raw
        .filter((r) => r['kind'] === 'osc')
        .map((r) => ({
          type: (r['type'] as string) ?? null,
          freqStart: typeof r['freqStart'] === 'number' ? r['freqStart'] : null,
          freqEnd: typeof r['freqEnd'] === 'number' ? r['freqEnd'] : null,
          peak: typeof r['peak'] === 'number' ? r['peak'] : 0,
          at: Math.round(r['at'] as number),
        })),
    };
  });
}

export interface AudioSince {
  count: number;
  notes: Array<{ type: string | null; freqStart: number | null; freqEnd: number | null; at: number }>;
}

/** Drain the transcript: call right before an action, read the result after. */
export async function audioSince(page: Page, from: number): Promise<AudioSince> {
  const t = await audioTranscript(page);
  return {
    count: t.notes.length - from,
    notes: t.notes.slice(from).map((n) => ({
      type: n.type,
      freqStart: n.freqStart === null ? null : Math.round(n.freqStart),
      freqEnd: n.freqEnd === null ? null : Math.round(n.freqEnd),
      at: n.at,
    })),
  };
}

/**
 * Per-axis movement, measured against the time the SIM was actually commanded
 * to move for, rather than against wall-clock or frame count.
 *
 * Why this is the only trustworthy way to measure speed here: this environment
 * has no GPU, so the renderer runs at 2-11fps under SwiftShader and the frame
 * delta is clamped (`Math.min(0.1, dt)`). Two time-boxed holds therefore
 * integrate wildly different amounts of simulated time, wall-clock tiles/sec
 * swings ~3x between runs on identical code, and a hold that runs into a wall
 * reports a nonsense average. Neither is a property of the movement code.
 *
 * `player:walk` carries `{dx, dy, dt, speed}`, so tapping the store's dispatch
 * gives the exact commanded time per axis. Displacement divided by commanded
 * time on the same axis is collision-independent and frame-rate independent.
 */
export interface AxisRate {
  /** Tiles ACTUALLY travelled along each axis, summed over dispatches. */
  movedX: number;
  movedY: number;
  /** Seconds the sim was commanded to move along each axis. */
  secX: number;
  secY: number;
  /** movedX/secX and movedY/secY: the effective per-axis speed. A correct
   *  diagonal gives the same number on both axes and the same number as a
   *  single axis. Zero on an axis that was never commanded. */
  rateX: number;
  rateY: number;
  dispatches: number;
}

/** Wrap the store's dispatch so a subsequent hold can be measured exactly. */
export async function startAxisRateProbe(page: Page): Promise<void> {
  await page.evaluate(() => {
    const w = window as unknown as {
      __EH__?: {
        store: {
          dispatch: (a: unknown) => unknown;
          state: { player: { position: { x: number; y: number } } };
        };
      };
      __EH_AXIS__?: { movedX: number; movedY: number; secX: number; secY: number; n: number };
    };
    const store = w.__EH__!.store;
    const tally = { movedX: 0, movedY: 0, secX: 0, secY: 0, n: 0 };
    w.__EH_AXIS__ = tally;
    const original = store.dispatch.bind(store);
    store.dispatch = (action: unknown): unknown => {
      const a = action as { type?: string; payload?: { dx?: number; dy?: number; dt?: number } };
      if (a?.type !== 'player:walk') return original(action);
      const dx = a.payload?.dx ?? 0;
      const dy = a.payload?.dy ?? 0;
      const dt = a.payload?.dt ?? 0;
      // Measure what the sim ACTUALLY did, not what it was asked to do: read the
      // position either side of the real dispatch. Summing the unit direction
      // vector instead would make the ratio 1.0 by construction and prove
      // nothing, and ignoring walls would credit distance never travelled.
      const before = store.state.player.position;
      const result = original(action);
      const after = store.state.player.position;
      tally.movedX += Math.abs(after.x - before.x);
      tally.movedY += Math.abs(after.y - before.y);
      // Command time accrues per axis actually being driven. Magnitudes, not
      // signed values: 'up' is dy = -1, and a signed sum would report a
      // negative speed for a correctly working north walk.
      if (dx !== 0) tally.secX += dt;
      if (dy !== 0) tally.secY += dt;
      tally.n += 1;
      return result;
    };
  });
}

/** Stop probing and report the per-axis rates. */
export async function stopAxisRateProbe(page: Page): Promise<AxisRate> {
  const t = await page.evaluate(() => {
    const w = window as unknown as {
      __EH_AXIS__?: { movedX: number; movedY: number; secX: number; secY: number; n: number };
    };
    const tally = w.__EH_AXIS__ ?? { movedX: 0, movedY: 0, secX: 0, secY: 0, n: 0 };
    delete w.__EH_AXIS__;
    return tally;
  });
  return {
    movedX: t.movedX,
    movedY: t.movedY,
    secX: t.secX,
    secY: t.secY,
    rateX: t.secX > 0 ? t.movedX / t.secX : 0,
    rateY: t.secY > 0 ? t.movedY / t.secY : 0,
    dispatches: t.n,
  };
}

export async function audioMark(page: Page): Promise<number> {
  return page.evaluate(() => (window as WindowWithHook).__EH_AUDIO__?.length ?? 0);
}

/** One SFX cue as recorded by the audio lane's dev-only recorder. Unlike the
 *  raw oscillator transcript this is per-cue, named and sfx-only, so it can be
 *  told apart from the continuously playing music. */
export interface SfxCueTone {
  freq: number;
  glide: number | null;
  type: string;
  dur: number;
  gain: number;
  delay: number;
}

export interface SfxCue {
  cue: string;
  bus: string;
  source: string;
  voices: number;
  tones: SfxCueTone[];
}

export interface SfxCueLog {
  count: number;
  cues: SfxCue[];
  music: { bars: number; buffered: number; notes: number; lastMood: string | null };
  audio: { bus: string | null; state: string; contexts: number };
  oscillators: number;
}

/** `__EH_SFX__` is method-based (see the audio lane's DevSfxHandle), so every
 *  read goes through the handle rather than touching fields directly. */
async function readSfxCueLog(page: Page): Promise<SfxCueLog> {
  return page.evaluate(() => {
    const w = window as unknown as {
      __EH_SFX__?: {
        cues: () => unknown[];
        count: () => number;
        music: () => { bars: number; buffered: number; notes: number; lastMood: string | null };
        audio: () => { bus: string | null; state: string; contexts: number };
      };
      __EH_AUDIO__?: unknown[];
    };
    const h = w.__EH_SFX__;
    return {
      count: h?.count() ?? 0,
      cues: (h?.cues() ?? []) as SfxCue[],
      music: h?.music() ?? { bars: 0, buffered: 0, notes: 0, lastMood: null },
      audio: h?.audio() ?? { bus: null, state: 'none', contexts: 0 },
      oscillators: w.__EH_AUDIO__?.length ?? 0,
    };
  });
}

/** The SFX cues recorded since `from`. */
export async function sfxCuesSince(page: Page, from: number): Promise<SfxCue[]> {
  return (await readSfxCueLog(page)).cues.slice(from);
}

export async function sfxCueMark(page: Page): Promise<number> {
  return (await readSfxCueLog(page)).count;
}

/**
 * The control that makes the audio verdicts honest: sit completely idle for
 * `ms` and report what the game scheduled anyway. The music track plays
 * continuously, so the raw oscillator count always rises during an idle
 * window; only the SFX cue count must stay flat. Without this, "we heard
 * something" is indistinguishable from "the soundtrack was playing".
 */
export async function audioIdleControl(page: Page, ms = 4000): Promise<SfxCueLog> {
  const before = await readSfxCueLog(page);
  await page.waitForTimeout(ms);
  const after = await readSfxCueLog(page);
  return {
    count: after.count - before.count,
    cues: after.cues.slice(before.count),
    music: after.music,
    audio: after.audio,
    oscillators: after.oscillators - before.oscillators,
  };
}

export async function eventMark(page: Page): Promise<number> {
  return page.evaluate(() => (window as WindowWithHook).__EH_EVENTS__?.length ?? 0);
}

export interface EventsSince {
  count: number;
  types: string[];
  payloads: Array<{ type: string; payload: unknown }>;
}

export async function eventsSince(page: Page, from: number): Promise<EventsSince> {
  return page.evaluate((f) => {
    const all = (window as WindowWithHook).__EH_EVENTS__ ?? [];
    const slice = all.slice(f);
    return { count: slice.length, types: slice.map((e) => e.type), payloads: slice };
  }, from);
}

export async function placedObjects(page: Page): Promise<Record<string, { id: string; data?: unknown }>> {
  return page.evaluate(() => {
    const st = (window as WindowWithHook).__EH__!.store.state;
    return st.maps[st.player.position.mapId]?.placed ?? {};
  });
}

export interface Neighbourhood {
  origin: { x: number; y: number };
  cells: Array<{ x: number; y: number; code: string; walkable: boolean }>;
}

/** Legend codes around the player, for picking a real target tile. */
export async function neighbourhood(page: Page, radius = 5): Promise<Neighbourhood> {
  return page.evaluate((r) => {
    const w = window as WindowWithHook;
    const st = w.__EH__!.store.state;
    const pos = st.player.position;
    const map = st.maps[pos.mapId]!;
    const legend = w.__EH__!.runtime.content.maps.get(pos.mapId)?.legend ?? {};
    const cx = Math.floor(pos.x);
    const cy = Math.floor(pos.y);
    const cells: Array<{ x: number; y: number; code: string; walkable: boolean }> = [];
    for (let y = cy - r; y <= cy + r; y++) {
      for (let x = cx - r; x <= cx + r; x++) {
        if (x < 0 || y < 0 || x >= map.grid.width || y >= map.grid.height) continue;
        const code = map.grid.tiles[y * map.grid.width + x] ?? '?';
        cells.push({ x, y, code, walkable: legend[code]?.walkable !== false });
      }
    }
    return { origin: { x: cx, y: cy }, cells };
  }, radius);
}

/** Put the player on a tile facing a direction. Not a walk - the render, the
 *  sim and the bus are all real, we just skip the approach. */
export async function faceTile(
  page: Page,
  x: number,
  y: number,
  facing: 'up' | 'down' | 'left' | 'right',
): Promise<void> {
  await page.evaluate(
    ({ x, y, facing }) => {
      const eh = (window as WindowWithHook).__EH__!;
      const st = eh.store.state;
      st.player.position.x = x;
      st.player.position.y = y;
      st.player.facing = facing;
      eh.store.replaceState({ ...st });
    },
    { x, y, facing },
  );
  await page.waitForTimeout(120);
}

export async function shot(page: Page, path: string): Promise<void> {
  await page.screenshot({ path });
}

export interface SceneMetrics {
  particles: number;
  swinging: boolean;
  failFlash: boolean;
  firstPerson: boolean;
}

/** The renderer's own view of what is on screen right now: live particle count,
 *  whether the swing animation is running, whether the fail flash is showing.
 *  Object-state facts, not pixel guesses. */
export async function sceneMetrics(page: Page): Promise<SceneMetrics | 'no-handle'> {
  return page.evaluate(() => {
    const h = (window as unknown as { __EH_SCENE__?: { metrics: () => SceneMetrics } }).__EH_SCENE__;
    if (!h) return 'no-handle' as const;
    return h.metrics();
  });
}

/** Poll sceneMetrics until `pred` holds or the budget runs out. Returns every
 *  sample taken, so a fast flash cannot be missed by a slow poll. */
export async function waitForScene(
  page: Page,
  pred: (m: SceneMetrics) => boolean,
  budgetMs = 1500,
): Promise<{ matched: boolean; samples: SceneMetrics[] }> {
  const samples: SceneMetrics[] = [];
  const deadline = Date.now() + budgetMs;
  let matched = false;
  while (Date.now() < deadline) {
    const m = await sceneMetrics(page);
    if (m !== 'no-handle') {
      samples.push(m);
      if (pred(m)) {
        matched = true;
        break;
      }
    }
    await page.waitForTimeout(16);
  }
  return { matched, samples };
}

/** Project a map tile to canvas pixel coordinates, so a probe can sample the
 *  exact block the player is targeting instead of the whole frame. */
export async function projectTile(
  page: Page,
  col: number,
  row: number,
  mapId: string,
): Promise<{ x: number; y: number; onScreen: boolean } | null> {
  return page.evaluate(
    ({ col, row, mapId }) => {
      const w = window as unknown as {
        __EH_SCENE__?: { scene: unknown; camera: unknown };
        __EH__?: DevHook;
      };
      const h = w.__EH_SCENE__;
      if (!h) return null;
      const st = w.__EH__!.store.state;
      const map = st.maps[mapId];
      if (!map) return null;
      const cell = 1;
      const wx = (col - (map.grid.width - 1) / 2) * cell;
      const wz = (row - (map.grid.height - 1) / 2) * cell;
      const cam = h.camera as {
        projectionMatrix: { elements: number[] };
        matrixWorldInverse: { elements: number[] };
      };
      // Column-major 4x4 multiply, then the perspective divide.
      const mul = (m: number[], v: number[]): number[] => [
        m[0]! * v[0]! + m[4]! * v[1]! + m[8]! * v[2]! + m[12]! * v[3]!,
        m[1]! * v[0]! + m[5]! * v[1]! + m[9]! * v[2]! + m[13]! * v[3]!,
        m[2]! * v[0]! + m[6]! * v[1]! + m[10]! * v[2]! + m[14]! * v[3]!,
        m[3]! * v[0]! + m[7]! * v[1]! + m[11]! * v[2]! + m[15]! * v[3]!,
      ];
      const view = mul(cam.matrixWorldInverse.elements, [wx, 0.5, wz, 1]);
      const clip = mul(cam.projectionMatrix.elements, view);
      if (clip[3] === 0) return null;
      const ndcX = clip[0]! / clip[3]!;
      const ndcY = clip[1]! / clip[3]!;
      const cv = document.querySelector('#game-root canvas') as HTMLCanvasElement | null;
      if (!cv) return null;
      const rect = cv.getBoundingClientRect();
      return {
        x: Math.round(((ndcX + 1) / 2) * rect.width),
        y: Math.round(((1 - ndcY) / 2) * rect.height),
        onScreen: ndcX >= -1 && ndcX <= 1 && ndcY >= -1 && ndcY <= 1,
      };
    },
    { col, row, mapId },
  );
}
