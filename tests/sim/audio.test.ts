/**
 * ADDENDUM B (D) — WebAudio cues. The feature is harmless off-DOM (no
 * AudioContext is ever created in Node), the tone specs are pure data, and the
 * mapping of game events to cues is fixed here so the feel cannot regress.
 */
import { describe, expect, it } from 'vitest';
import {
  audioUi,
  AudioEngine,
  successTone,
  failTone,
  footstepTone,
  coinTone,
  type ToneSpec,
} from '@game/features/audio/audio';

function assertWellFormed(specs: readonly ToneSpec[]): void {
  for (const s of specs) {
    expect(s.freq).toBeGreaterThan(20);
    expect(s.freq).toBeLessThan(20000);
    expect(s.dur).toBeGreaterThan(0);
    expect(s.gain).toBeGreaterThan(0);
    expect(s.gain).toBeLessThanOrEqual(1);
  }
}

describe('audio:ui tone specs', () => {
  it('success is a quick ascending two-note blip', () => {
    const specs = successTone();
    assertWellFormed(specs);
    expect(specs).toHaveLength(2);
    expect(specs[1]!.freq).toBeGreaterThan(specs[0]!.freq);
  });

  it('failure is a single low buzz, distinct from success', () => {
    const specs = failTone();
    assertWellFormed(specs);
    expect(specs[0]!.freq).toBeLessThan(successTone()[0]!.freq);
  });

  it('footsteps are very short and quiet', () => {
    assertWellFormed(footstepTone());
    expect(footstepTone()[0]!.dur).toBeLessThan(0.05);
  });

  it('coins register an upward arpeggio', () => {
    const specs = coinTone();
    assertWellFormed(specs);
    const freqs = specs.map((s) => s.freq);
    expect([...freqs].sort((a, b) => a - b)).toEqual(freqs);
  });

  it('is headless-safe: no context is created and ensure() returns false', () => {
    const engine = new AudioEngine();
    expect(engine.ensure()).toBe(false);
    expect(() => engine.play('tool:failure', failTone())).not.toThrow();
    expect(() => engine.stepTick()).not.toThrow();
  });

  it('registers with the shared registry under the ui lane', async () => {
    await import('@game/features/auto-import');
    const { getFeatures } = await import('@game/core/registry');
    const registered = getFeatures().find((f) => f.id === audioUi.id);
    expect(registered).toBeDefined();
    expect(audioUi.id).toBe('audio:ui');
    expect(audioUi.lane).toBe('ui');
  });
});