/**
 * T-0460 — music:ui specs. The soundtrack is original + procedural, so the
 * "game music" failsafe is logic: theme resolution, deterministic bar
 * generation and headless safety are pinned here. Nothing on this page can
 * regress without a reviewer seeing it.
 */
import { describe, expect, it } from 'vitest';
import {
  buildBar,
  midiToFreq,
  moodForHour,
  MusicEngine,
  musicUi,
  resolveMusicTheme,
} from '@game/features/audio/music';
import type { MusicContext, MusicPlan } from '@game/features/audio/music';
import type { SeasonIndex } from '@game/core/types';
import { Rng } from '@game/core/rng';

const FARM_NOON: MusicContext = { hour: 12, weather: 'sun', seasonIndex: 0, mapId: 'farm', healthPct: 1 };
const FARM_NIGHT: MusicContext = { hour: 23, weather: 'sun', seasonIndex: 0, mapId: 'farm', healthPct: 1 };

function assertAudible(plan: MusicPlan): void {
  for (const n of plan.notes) {
    expect(n.freq).toBeGreaterThan(20);
    expect(n.freq).toBeLessThan(20000);
    expect(n.dur).toBeGreaterThan(0);
    expect(n.gain).toBeGreaterThan(0);
    expect(n.gain).toBeLessThanOrEqual(1);
  }
}

function bassMin(plan: MusicPlan): number {
  return plan.bass.map((n) => n.freq).reduce((a, b) => Math.min(a, b), Infinity);
}

function leadMin(plan: MusicPlan): number {
  return plan.lead.map((n) => n.freq).reduce((a, b) => Math.min(a, b), Infinity);
}

describe('music:ui theme resolution', () => {
  it('noon on the farm is a bright, percussive day theme', () => {
    const t = resolveMusicTheme(FARM_NOON);
    expect(t.mood).toBe('day');
    expect(t.perc).toBe(true);
    expect(t.pad).toBe(false);
    expect(t.bpm).toBeGreaterThanOrEqual(90);
    expect(t.density).toBeGreaterThanOrEqual(0.8);
  });

  it('night is sparse and percussion-free', () => {
    const t = resolveMusicTheme(FARM_NIGHT);
    expect(t.mood).toBe('night');
    expect(t.perc).toBe(false);
    expect(t.pad).toBe(true);
    expect(t.bpm).toBeLessThan(75);
  });

  it('dawn and dusk sit between day and night', () => {
    expect(resolveMusicTheme({ ...FARM_NOON, hour: 7 }).mood).toBe('dawn');
    expect(resolveMusicTheme({ ...FARM_NOON, hour: 18 }).mood).toBe('dusk');
  });

  it('the home interior switches to the home lullaby regardless of hour', () => {
    const t = resolveMusicTheme({ ...FARM_NOON, mapId: 'home' });
    expect(t.mood).toBe('home');
    expect(t.bpm).toBeLessThan(80);
  });

  it('mine/cave maps pick the cavern drone', () => {
    expect(resolveMusicTheme({ ...FARM_NOON, mapId: 'mines-3' }).mood).toBe('cave');
    expect(resolveMusicTheme({ ...FARM_NOON, mapId: 'cave-falls' }).mood).toBe('cave');
  });

  it('low health flips to the danger ostinato with a faster pulse', () => {
    const calm = resolveMusicTheme(FARM_NOON);
    const danger = resolveMusicTheme({ ...FARM_NOON, healthPct: 0.25 });
    expect(danger.mood).toBe('danger');
    expect(danger.bpm).toBeGreaterThan(calm.bpm);
    expect(danger.leadWave).toBe('sawtooth');
  });

  it('rain, snow and wind mute percussion and air the lead up', () => {
    const rain = resolveMusicTheme({ ...FARM_NOON, weather: 'rain' });
    expect(rain.perc).toBe(false);
    expect(rain.bright).toBe(12);
    const snow = resolveMusicTheme({ ...FARM_NOON, weather: 'snow' });
    expect(snow.perc).toBe(false);
    expect(snow.leadWave).toBe('sine');
    const wind = resolveMusicTheme({ ...FARM_NOON, weather: 'wind' });
    expect(wind.perc).toBe(false);
  });

  it('storm adds drive: keeps percussion and sharpens the lead', () => {
    const storm = resolveMusicTheme({ ...FARM_NOON, weather: 'storm' });
    expect(storm.perc).toBe(true);
    expect(storm.leadWave).toBe('sawtooth');
  });

  it('seasons transpose the key and winter shrinks to a pentatonic', () => {
    const spr = resolveMusicTheme(FARM_NOON);
    const win = resolveMusicTheme({ ...FARM_NOON, seasonIndex: 3 });
    expect(win.root).toBeLessThan(spr.root);
    expect(win.steps).toHaveLength(5);
  });

  it('same context resolves to the same theme id (stable signature)', () => {
    expect(resolveMusicTheme(FARM_NOON).id).toBe(resolveMusicTheme(FARM_NOON).id);
    expect(resolveMusicTheme(FARM_NOON).id).not.toBe(resolveMusicTheme(FARM_NIGHT).id);
  });

  it('moodForHour covers the full clock', () => {
    expect(moodForHour(6)).toBe('dawn');
    expect(moodForHour(12)).toBe('day');
    expect(moodForHour(18)).toBe('dusk');
    expect(moodForHour(0)).toBe('night');
    expect(moodForHour(4)).toBe('late');
    expect(moodForHour(26)).toBe('night');
  });
});

describe('music:ui bar generation', () => {
  it('is deterministic for the same seed, theme and bar index', () => {
    const theme = resolveMusicTheme(FARM_NOON);
    const a = buildBar(theme, new Rng(42), 3);
    const b = buildBar(theme, new Rng(42), 3);
    expect(JSON.stringify(a)).toBe(JSON.stringify(b));
    const c = buildBar(theme, new Rng(99), 3);
    expect(JSON.stringify(c)).not.toBe(JSON.stringify(a));
  });

  it('bar length matches the tempo: 4 beats of 4/4', () => {
    const theme = resolveMusicTheme(FARM_NOON);
    const plan = buildBar(theme, new Rng(1), 0);
    expect(plan.duration).toBeCloseTo((60 / theme.bpm) * 4, 5);
  });

  it('all scheduled notes are audible and shaped', () => {
    for (const seasonIndex of [0, 1, 2, 3] as SeasonIndex[]) {
      const plan = buildBar(resolveMusicTheme({ ...FARM_NOON, seasonIndex }), new Rng(7), 0);
      assertAudible(plan);
    }
  });

  it('the bass sits below the lead voice', () => {
    const plan = buildBar(resolveMusicTheme(FARM_NOON), new Rng(3), 0);
    expect(bassMin(plan)).toBeLessThan(leadMin(plan));
  });

  it('percussion only exists when the theme wants it', () => {
    const day = buildBar(resolveMusicTheme(FARM_NOON), new Rng(5), 0);
    const night = buildBar(resolveMusicTheme(FARM_NIGHT), new Rng(5), 0);
    expect(day.perc.length).toBeGreaterThan(0);
    expect(night.perc).toHaveLength(0);
    const roles = new Set(day.perc.map((n) => n.role));
    expect(roles).toEqual(new Set(['perc']));
  });

  it('denser themes arrange more lead notes', () => {
    const theme = resolveMusicTheme(FARM_NOON);
    const plan = buildBar(theme, new Rng(9), 0);
    const sparse = buildBar(resolveMusicTheme(FARM_NIGHT), new Rng(9), 0);
    expect(plan.lead.length).toBeGreaterThan(sparse.lead.length);
  });

  it('progressions stay inside the key (chord midis land on scale degrees)', () => {
    const theme = resolveMusicTheme(FARM_NOON);
    for (let b = 0; b < 4; b++) {
      const plan = buildBar(theme, new Rng(b), b);
      for (const n of [...plan.bass, ...plan.pad, ...plan.lead]) {
        const stepsBase = n.midi - theme.root - theme.bright;
        const inScale = theme.steps.some((s) => (stepsBase + 120) % 12 === (s + 120) % 12);
        expect(inScale).toBe(true);
      }
    }
  });

  it('midiToFreq anchors A4 at 440 Hz', () => {
    expect(midiToFreq(69)).toBeCloseTo(440, 3);
    expect(midiToFreq(81)).toBeCloseTo(880, 3);
  });
});

describe('music:ui engine (headless-safe)', () => {
  it('never creates a context or timer off-DOM', () => {
    const engine = new MusicEngine(7);
    expect(engine.ensure()).toBe(false);
    expect(() => engine.setTheme(resolveMusicTheme(FARM_NOON))).not.toThrow();
    expect(engine.currentTheme()).toContain('day');
    expect(() => engine.setEnabled(true)).not.toThrow();
    expect(() => engine.setVolume(0.3)).not.toThrow();
    expect(() => engine.stop()).not.toThrow();
  });

  it('keeps the theme id current but skips no-op updates', () => {
    const engine = new MusicEngine(7);
    const theme = resolveMusicTheme(FARM_NOON);
    engine.setTheme(theme);
    expect(engine.currentTheme()).toBe(theme.id);
    engine.setTheme(theme);
    expect(engine.currentTheme()).toBe(theme.id);
    engine.setTheme(null);
    expect(engine.currentTheme()).toBeNull();
  });

  it('registers with the shared registry under the ui lane', async () => {
    await import('@game/features/auto-import');
    const { getFeatures } = await import('@game/core/registry');
    const registered = getFeatures().find((f) => f.id === musicUi.id);
    expect(registered).toBeDefined();
    expect(musicUi.id).toBe('music:ui');
    expect(musicUi.lane).toBe('ui');
  });
});