/**
 * audio:ui — minimal WebAudio-synthesized sound (WORKER-3 lane).
 * No audio files: every cue is a short synthesized blip so core-loop feedback
 * lands cheaply (ADDENDUM B). Full music stays in M7; the ambient loop
 * (wind/hum) is a stretch goal, not implemented here yet.
 *
 * Registered by src/features/audio/index.ts. Headless-safe: in Node the
 * AudioEngine never creates an AudioContext and all event hooks become no-ops,
 * so the sim/test lanes are untouched.
 */
import { defineFeature, type UiHandle } from '../../core/feature';

export interface ToneSpec {
  freq: number;
  dur: number;
  type: OscillatorType;
  gain: number;
  /** Seconds to delay this note, for short arpeggios. */
  delay?: number;
}

export function successTone(): ToneSpec[] {
  return [
    { freq: 523.25, dur: 0.09, type: 'square', gain: 0.45 },
    { freq: 783.99, dur: 0.14, type: 'square', gain: 0.45, delay: 0.055 },
  ];
}

export function failTone(): ToneSpec[] {
  return [{ freq: 196, dur: 0.12, type: 'sawtooth', gain: 0.35 }];
}

export function footstepTone(): ToneSpec[] {
  return [{ freq: 132, dur: 0.035, type: 'triangle', gain: 0.22 }];
}

export function coinTone(): ToneSpec[] {
  return [
    { freq: 659.25, dur: 0.07, type: 'sine', gain: 0.5 },
    { freq: 880, dur: 0.07, type: 'sine', gain: 0.5, delay: 0.07 },
    { freq: 1318.5, dur: 0.12, type: 'sine', gain: 0.5, delay: 0.14 },
  ];
}

export class AudioEngine {
  private ctx: AudioContext | null = null;
  private master: GainNode | null = null;
  private lastStepAt = -1;

  /** Lazily create/resume the AudioContext. Returns false off-DOM or muted. */
  ensure(): boolean {
    if (typeof window === 'undefined') return false;
    if (!this.ctx) {
      const w = window as unknown as { AudioContext?: new () => AudioContext; webkitAudioContext?: new () => AudioContext };
      const Ctor = w.AudioContext ?? w.webkitAudioContext;
      if (!Ctor) return false;
      this.ctx = new Ctor();
      this.master = this.ctx.createGain();
      this.master.gain.value = 0.55;
      this.master.connect(this.ctx.destination);
    }
    if (this.ctx.state === 'suspended') void this.ctx.resume();
    return this.ctx.state === 'running';
  }

  /** Schedule one or more envelope-shaped oscillators starting 'now'. */
  play(specs: readonly ToneSpec[]): void {
    if (!this.ensure()) return;
    const ctx = this.ctx!;
    const master = this.master!;
    const now = ctx.currentTime;
    for (const spec of specs) {
      const t0 = now + (spec.delay ?? 0);
      const osc = ctx.createOscillator();
      osc.type = spec.type;
      osc.frequency.setValueAtTime(spec.freq, t0);
      const gain = ctx.createGain();
      gain.gain.setValueAtTime(0, t0);
      gain.gain.linearRampToValueAtTime(spec.gain, t0 + 0.008);
      gain.gain.exponentialRampToValueAtTime(0.0001, t0 + spec.dur);
      osc.connect(gain);
      gain.connect(master);
      osc.start(t0);
      osc.stop(t0 + spec.dur + 0.02);
    }
  }

  /** Footstep tick while moving, throttled so tile crossings don't pile up. */
  stepTick(): void {
    if (!this.ensure()) return;
    const now = this.ctx!.currentTime;
    if (now - this.lastStepAt < 0.11) return;
    this.lastStepAt = now;
    this.play(footstepTone());
  }
}

export const audioUi = defineFeature({
  id: 'audio:ui',
  lane: 'ui',
  setup(ctx): void {
    const engine = new AudioEngine();
    ctx.bus.on('tool:used', () => {
      if (engine.ensure()) engine.play(successTone());
    });
    ctx.bus.on('tool:failed', () => {
      if (engine.ensure()) engine.play(failTone());
    });
    ctx.bus.on('player:moved', () => engine.stepTick());
    ctx.bus.on('shipping:report', (report: { sold: readonly unknown[]; total: number }) => {
      if (engine.ensure() && report.sold.length > 0) engine.play(coinTone());
    });
  },
  ui(): UiHandle {
    return {
      mount(): void {},
      dispose(): void {},
    };
  },
});