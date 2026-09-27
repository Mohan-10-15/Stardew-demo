/**
 * audio/cues.ts — dev-only SFX cue recorder (WORKER-3 lane, T-0505).
 *
 * Why this exists: the acceptance harness can only prove audio exists by
 * counting oscillators. That is not evidence, because the procedural
 * soundtrack synthesises continuously — a three-second window during which the
 * game plays *no* cue at all still contains music notes, so "N notes were
 * created" is a YES verdict for both a successful and a failed tool action. The
 * count was measuring the soundtrack, not the feedback.
 *
 * So cues are recorded at the one point every SFX passes through:
 * `AudioEngine.play(cue, specs)`. The soundtrack never touches that method
 * (see ./music.ts — it schedules straight into the `music` bus), so the log
 * below is SFX-only by construction. Each entry carries the *named* cue, the bus
 * it was routed to, the resolved `ToneSpec[]` it scheduled and a timestamp, so
 * a harness can assert "the failed action produced cue `tool:failure` with one
 * 233Hz sawtooth" instead of guessing from hertz.
 *
 * Music is logged separately and at bar granularity (`recordMusicBar`). It is
 * the control: a probe can show the bed was genuinely playing while the SFX log
 * stayed empty, which is the falsifiable claim the old oscillator count could
 * not make.
 *
 * Inert in production: every recorder entry point is gated on
 * `import.meta.env.DEV`, the same guard `src/main.ts` and EngineView use for
 * `__EH__` / `__EH_SCENE__`, so a built bundle carries no log and no global.
 */
import type { ToneSpec } from './audio';

/** The two staged buses in the shared graph (see ./context.ts). */
export type AudioBusName = 'sfx' | 'music';

/**
 * Every named cue the game can play. The union is the whole point: a cue is
 * identified by which member it is, never by reverse-engineering frequencies,
 * and adding a sound without naming it is a type error rather than an
 * unlabelled blip in the log.
 */
export type SfxCue = 'tool:success' | 'tool:failure' | 'player:footstep' | 'sale:coin';

/** One oscillator's worth of detail, resolved at schedule time. */
export interface RecordedTone {
  freq: number;
  /** Frequency the glide ended on, or null for a steady tone. */
  glide: number | null;
  dur: number;
  type: OscillatorType;
  gain: number;
  /** Seconds after the call the oscillator starts. */
  delay: number;
  /** Seconds spent ramping to `gain` (the envelope the engine really used). */
  attack: number;
  /** Absolute AudioContext time the oscillator was started at. */
  startAt: number;
}

/** One call to `AudioEngine.play()`, captured whole. */
export interface SfxCueEntry {
  /** The named cue. This is what a harness matches on. */
  cue: SfxCue;
  /** The bus the tones were routed into. Cues only ever land on 'sfx'. */
  bus: AudioBusName;
  /** What triggered it, e.g. `tool:used hoe->tilled`. Empty when unnamed. */
  source: string;
  /** performance.now() at the call. */
  at: number;
  /** AudioContext.currentTime at the call: the scheduling origin. */
  ctxTime: number;
  /** Oscillators this call created. */
  voices: number;
  /** The resolved tones, copied so later mutation cannot rewrite history. */
  tones: RecordedTone[];
}

/** Bar-level proof the soundtrack was running, kept out of the SFX log. */
export interface MusicBarEntry {
  bar: number;
  mood: string;
  /** Notes in the bar that were scheduled onto the music bus. */
  notes: number;
  at: number;
  ctxTime: number;
}

/** Ring capacity. A cue log is read seconds after the fact, so this only has to
 *  outlast a probe window; `total` proves whether anything was ever dropped. */
const CUE_CAPACITY = 256;
const BAR_CAPACITY = 64;

function now(): number {
  return typeof performance === 'undefined' ? 0 : performance.now();
}

function push<T>(ring: T[], item: T, capacity: number): void {
  ring.push(item);
  if (ring.length > capacity) ring.shift();
}

/**
 * Bounded, oldest-first log of SFX cues. Plain data in, plain data out — it
 * holds no AudioContext, no OscillatorNode and no reference to the live spec
 * objects, so a recorded log stays readable after the nodes are gone.
 */
export class SfxCueRecorder {
  /** Ring capacity, exposed so a test can prove the eviction behaviour. */
  static readonly RING_CAPACITY = CUE_CAPACITY;

  private cues: SfxCueEntry[] = [];
  private bars: MusicBarEntry[] = [];
  private cueTotal = 0;
  private barTotal = 0;
  private barNotes = 0;
  /** Oscillators the recorded cues created, so the log can be cross-checked
   *  against an external oscillator tap. */
  private cueVoices = 0;

  /** Buffered cues, oldest first. */
  entries(): readonly SfxCueEntry[] {
    return this.cues;
  }

  /** Cues recorded from index `from` on — the harness's delta helper. */
  since(from: number): SfxCueEntry[] {
    return this.cues.slice(Math.max(0, from));
  }

  /** Cues currently buffered (not the lifetime total). */
  count(): number {
    return this.cues.length;
  }

  /** Lifetime cue count, so a reader can tell the ring dropped something. */
  total(): number {
    return this.cueTotal;
  }

  /** Oscillators the recorded cues created. */
  voices(): number {
    return this.cueVoices;
  }

  /** Buffered music bars, oldest first. Never mixed into the SFX log. */
  barEntries(): readonly MusicBarEntry[] {
    return this.bars;
  }

  /** Buffered music bar count. */
  barCount(): number {
    return this.bars.length;
  }

  /** Lifetime music bar count, and the notes every bar has scheduled. */
  barTotals(): { bars: number; notes: number } {
    return { bars: this.barTotal, notes: this.barNotes };
  }

  clear(): void {
    this.cues = [];
    this.bars = [];
    this.cueTotal = 0;
    this.barTotal = 0;
    this.barNotes = 0;
    this.cueVoices = 0;
  }

  recordCue(cue: SfxCue, bus: AudioBusName, source: string, ctxTime: number, tones: readonly ToneSpec[], scheduledAt: readonly number[]): void {
    const recorded: RecordedTone[] = tones.map((t, i) => ({
      freq: t.freq,
      glide: t.glide ?? null,
      dur: t.dur,
      type: t.type,
      gain: t.gain,
      delay: t.delay ?? 0,
      attack: Math.min(t.attack ?? 0.008, Math.max(0.001, t.dur * 0.4)),
      startAt: scheduledAt[i] ?? ctxTime,
    }));
    this.cueTotal += 1;
    this.cueVoices += recorded.length;
    push<SfxCueEntry>(
      this.cues,
      {
        cue,
        bus,
        source,
        at: now(),
        ctxTime,
        voices: recorded.length,
        tones: recorded,
      },
      CUE_CAPACITY,
    );
  }

  recordBar(entry: MusicBarEntry): void {
    this.barTotal += 1;
    this.barNotes += entry.notes;
    push<MusicBarEntry>(this.bars, entry, BAR_CAPACITY);
  }
}

let recorder: SfxCueRecorder | null = null;

/** The process-wide recorder. Headless-safe: pure data, no DOM, no context. */
export function sfxCueRecorder(): SfxCueRecorder {
  if (!recorder) recorder = new SfxCueRecorder();
  return recorder;
}

/**
 * Record a cue. Dev-only: a no-op in a production build, so the call sites in
 * audio.ts stay free of build-flag noise.
 */
export function recordSfxCue(
  cue: SfxCue,
  bus: AudioBusName,
  source: string,
  ctxTime: number,
  tones: readonly ToneSpec[],
  scheduledAt: readonly number[],
): void {
  if (!import.meta.env.DEV) return;
  sfxCueRecorder().recordCue(cue, bus, source, ctxTime, tones, scheduledAt);
}

/** Record one scheduled soundtrack bar. Dev-only, like recordSfxCue. */
export function recordMusicBar(bar: number, mood: string, notes: number, ctxTime: number): void {
  if (!import.meta.env.DEV) return;
  sfxCueRecorder().recordBar({ bar, mood, notes, at: now(), ctxTime });
}

/** Live bus/context facts, so a probe can confirm audio was really audible. */
export interface DevAudioState {
  /** The bus a cue routes to, or null before any gesture. */
  bus: AudioBusName | null;
  /** AudioContext.state, or 'none' when no context exists yet. */
  state: string;
  /** AudioContexts this module has ever constructed. Must stay at 1. */
  contexts: number;
}

/**
 * Dev-only inspection handle published to globalThis (see publishSfxCueHandle).
 * Mirrors the `__EH_SCENE__` convention: plain functions returning plain data.
 */
export interface DevSfxHandle {
  /** Every buffered SFX cue, oldest first. */
  cues: () => SfxCueEntry[];
  /** Cues recorded from index `from` on — the delta a probe needs. */
  since: (from: number) => SfxCueEntry[];
  /** Cues currently buffered. */
  count: () => number;
  /** Lifetime cue total, and the oscillators they created. */
  totals: () => { cues: number; voices: number };
  /** Drop the log. Used to start a measurement window clean. */
  clear: () => void;
  /** Music bars scheduled, kept out of `cues()`. */
  music: () => { bars: number; buffered: number; notes: number; lastMood: string | null };
  /** Bus + context facts. */
  audio: () => DevAudioState;
}

/** Publish `__EH_SFX__` for the browser observation harness. Never in a build. */
export function publishSfxCueHandle(audio: () => DevAudioState): void {
  if (!import.meta.env.DEV) return;
  const rec = sfxCueRecorder();
  const handle: DevSfxHandle = {
    cues: () => rec.entries().map((e) => ({ ...e, tones: e.tones.map((t) => ({ ...t })) })),
    since: (from: number) =>
      rec.since(from).map((e) => ({ ...e, tones: e.tones.map((t) => ({ ...t })) })),
    count: () => rec.count(),
    totals: () => ({ cues: rec.total(), voices: rec.voices() }),
    clear: () => rec.clear(),
    music: () => {
      const t = rec.barTotals();
      const bars = rec.barEntries();
      return { bars: t.bars, buffered: bars.length, notes: t.notes, lastMood: bars.at(-1)?.mood ?? null };
    },
    audio: () => audio(),
  };
  (globalThis as unknown as { __EH_SFX__?: DevSfxHandle }).__EH_SFX__ = handle;
}
