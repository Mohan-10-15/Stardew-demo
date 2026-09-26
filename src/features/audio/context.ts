/**
 * audio/context.ts — the ONE AudioContext for the whole game (WORKER-3 lane,
 * T-0503).
 *
 * Before this module `AudioEngine` and `MusicEngine` each built their own
 * context, so a fresh page created two. Browsers cap live contexts (Chromium
 * refuses the 7th) and every extra context costs a thread and a buffer set, so
 * the fix is a module-owned singleton with a fixed gain graph:
 *
 *   osc -> voice gain -> sfx bus  --\
 *                                  +-> master -> destination
 *   osc -> note gain -> music bus -/
 *
 * The bus gains are the staging that makes cues readable: `SFX_BUS_GAIN` keeps
 * feedback at full level while `MUSIC_BUS_GAIN` tucks the soundtrack ~9 dB
 * underneath it, so a footstep or a coin is never buried by a pad chord.
 *
 * Autoplay policy: no context may exist before a real user gesture, so
 * `installAudioUnlock()` listens for the first `keydown`/`pointerdown` and only
 * then is the context constructed. Every cue path asks for the buses and
 * degrades to a silent no-op until that has happened, which is also what makes
 * the whole audio lane safe under Node/vitest.
 */

export interface AudioBuses {
  readonly ctx: AudioContext;
  readonly master: GainNode;
  /** Cues: tools, footsteps, coins. */
  readonly sfx: GainNode;
  /** The procedural soundtrack bed. */
  readonly music: GainNode;
}

/** Ceiling for the whole graph. */
export const MASTER_GAIN = 1;
/** Cues sit at full level on the master bus. */
export const SFX_BUS_GAIN = 1;
/** Music is mixed well under the cues (~-9 dB) and never rides over them. */
export const MUSIC_BUS_GAIN = 0.35;

type AudioContextCtor = new () => AudioContext;

let createdCount = 0;
let context: AudioContext | null = null;
let buses: AudioBuses | null = null;
let gestureSeen = false;
let removeUnlock: (() => void) | null = null;

function audioWindow(): Window | null {
  return typeof window === 'undefined' ? null : window;
}

function ctorFrom(w: Window): AudioContextCtor | null {
  const holder = w as unknown as { AudioContext?: AudioContextCtor; webkitAudioContext?: AudioContextCtor };
  return holder.AudioContext ?? holder.webkitAudioContext ?? null;
}

/** True once a real keydown/pointerdown has been seen. */
export function audioGestureSeen(): boolean {
  return gestureSeen;
}

/** How many AudioContexts this module has constructed. Must stay at 1. */
export function audioContextCount(): number {
  return createdCount;
}

/** The live context, or null before the first gesture / off-DOM. */
export function sharedAudioContext(): AudioContext | null {
  return context;
}

/**
 * Get the shared buses, creating the context on first use. Returns null until a
 * user gesture has been observed, and resumes a suspended context after that.
 */
export function audioBuses(): AudioBuses | null {
  if (buses) {
    if (buses.ctx.state === 'suspended') void buses.ctx.resume();
    return buses;
  }
  if (!gestureSeen) return null;
  const w = audioWindow();
  if (!w) return null;
  const Ctor = ctorFrom(w);
  if (!Ctor) return null;
  const ctx = new Ctor();
  createdCount += 1;
  const master = ctx.createGain();
  master.gain.value = MASTER_GAIN;
  const sfx = ctx.createGain();
  sfx.gain.value = SFX_BUS_GAIN;
  const music = ctx.createGain();
  music.gain.value = MUSIC_BUS_GAIN;
  sfx.connect(master);
  music.connect(master);
  master.connect(ctx.destination);
  context = ctx;
  buses = { ctx, master, sfx, music };
  if (ctx.state === 'suspended') void ctx.resume();
  return buses;
}

/** Mark the gesture and build the context. Called from the unlock listeners. */
export function unlockAudio(): AudioBuses | null {
  gestureSeen = true;
  return audioBuses();
}

/**
 * Arm the one-shot gesture hook. Idempotent: repeated calls return the same
 * teardown instead of stacking listeners. The teardown only removes the
 * listeners — an already-created context is intentionally kept alive so a
 * feature remount cannot re-enter the autoplay-blocked state.
 */
export function installAudioUnlock(): () => void {
  const w = audioWindow();
  if (!w) return () => undefined;
  if (removeUnlock) return removeUnlock;
  const onGesture = (): void => {
    unlockAudio();
  };
  w.addEventListener('keydown', onGesture, true);
  w.addEventListener('pointerdown', onGesture, true);
  removeUnlock = (): void => {
    w.removeEventListener('keydown', onGesture, true);
    w.removeEventListener('pointerdown', onGesture, true);
    removeUnlock = null;
  };
  return removeUnlock;
}
