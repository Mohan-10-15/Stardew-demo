/**
 * audio:ui — WebAudio-synthesized cues (WORKER-3 lane).
 *
 * No audio files: every cue is a short synthesized gesture so core-loop
 * feedback lands cheaply. The voices are deliberately *not* bare beeps — each
 * one glides (`glide`) and gets its own attack, which is what separates a
 * satisfying "chunk" from a click: the tool success lifts a fifth, the failure
 * sags a minor third, footsteps scuff downward, and the coin sparkles up three
 * steps. Cues ride the shared `sfx` bus, which sits at full level on the master
 * so they always read over the soundtrack (see ./context.ts).
 *
 * Registered by src/features/audio/index.ts. Headless-safe: in Node there is no
 * window, `audioBuses()` yields null, and every event hook degrades to a no-op
 * so the sim/test lanes are untouched.
 */
import { defineFeature, type UiHandle } from '../../core/feature';
import { audioBuses, installAudioUnlock, type AudioBuses } from './context';

export interface ToneSpec {
  freq: number;
  dur: number;
  type: OscillatorType;
  gain: number;
  /** Seconds to delay this note, for short arpeggios. */
  delay?: number;
  /** Frequency to glide to across `dur`. Omit for a steady tone. */
  glide?: number;
  /** Seconds to reach `gain`. Short attacks keep cues percussive. */
  attack?: number;
}

export function successTone(): ToneSpec[] {
  return [
    { freq: 494, dur: 0.08, type: 'square', gain: 0.34, glide: 587, attack: 0.004 },
    { freq: 587, dur: 0.15, type: 'square', gain: 0.3, glide: 784, attack: 0.004, delay: 0.05 },
  ];
}

export function failTone(): ToneSpec[] {
  return [{ freq: 233, dur: 0.16, type: 'sawtooth', gain: 0.26, glide: 175, attack: 0.006 }];
}

export function footstepTone(): ToneSpec[] {
  return [{ freq: 165, dur: 0.038, type: 'triangle', gain: 0.16, glide: 96, attack: 0.003 }];
}

export function coinTone(): ToneSpec[] {
  return [
    { freq: 659, dur: 0.07, type: 'sine', gain: 0.34, glide: 784, attack: 0.003 },
    { freq: 880, dur: 0.07, type: 'sine', gain: 0.32, glide: 988, attack: 0.003, delay: 0.065 },
    { freq: 1319, dur: 0.13, type: 'sine', gain: 0.3, glide: 1568, attack: 0.003, delay: 0.13 },
  ];
}

export class AudioEngine {
  private buses: AudioBuses | null = null;
  private lastStepAt = -1;

  /** Resolve the shared buses. False off-DOM or before the first gesture. */
  ensure(): boolean {
    const buses = audioBuses();
    this.buses = buses;
    if (!buses) return false;
    // A context still ramping out of 'suspended' will start the moment the
    // resume lands, and notes scheduled into it play in order, so anything but
    // a closed context counts as usable.
    return buses.ctx.state !== 'closed';
  }

  /** Schedule one or more envelope-shaped oscillators starting 'now'. */
  play(specs: readonly ToneSpec[]): void {
    if (!this.ensure()) return;
    const buses = this.buses;
    if (!buses) return;
    const { ctx, sfx } = buses;
    const now = ctx.currentTime;
    for (const spec of specs) {
      const t0 = now + (spec.delay ?? 0);
      const osc = ctx.createOscillator();
      osc.type = spec.type;
      osc.frequency.setValueAtTime(spec.freq, t0);
      if (spec.glide !== undefined) {
        osc.frequency.exponentialRampToValueAtTime(Math.max(20, spec.glide), t0 + spec.dur);
      }
      const attack = Math.min(spec.attack ?? 0.008, Math.max(0.001, spec.dur * 0.4));
      const gain = ctx.createGain();
      gain.gain.setValueAtTime(0, t0);
      gain.gain.linearRampToValueAtTime(spec.gain, t0 + attack);
      gain.gain.exponentialRampToValueAtTime(0.0001, t0 + spec.dur);
      osc.connect(gain);
      gain.connect(sfx);
      osc.start(t0);
      osc.stop(t0 + spec.dur + 0.02);
    }
  }

  /** Footstep tick while moving, throttled so tile crossings don't pile up. */
  stepTick(): void {
    if (!this.ensure()) return;
    const ctx = this.buses?.ctx;
    if (!ctx) return;
    const now = ctx.currentTime;
    if (now - this.lastStepAt < 0.11) return;
    this.lastStepAt = now;
    this.play(footstepTone());
  }
}

export const audioUi = defineFeature({
  id: 'audio:ui',
  lane: 'ui',
  setup(ctx): void {
    installAudioUnlock();
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
