import { describe, expect, it } from 'vitest';
import { createSim } from './harness';
import { WEATHERS, type Weather } from '@game/core/types';
import { applyWeatherEffects } from '@game/features/farming/sim/rollover';
import { Rng } from '@game/core/rng';
import { tileKey } from '@game/features/farming/sim/utils';

function isAllowedInSeason(w: Weather, seasonIndex: number): boolean {
  if (w === 'snow') return seasonIndex === 3;
  if (w === 'rain') return seasonIndex !== 3;
  if (w === 'storm') return seasonIndex !== 3;
  return true;
}

describe('weather sim', () => {
  it('is deterministic for equal seeds over the same day sequence', async () => {
    const run = async (): Promise<Weather[]> => {
      const sim = await createSim({ seed: 4242 });
      const seq: Weather[] = [sim.state.world.weather];
      for (let i = 0; i < 14; i++) {
        sim.sleep();
        seq.push(sim.state.world.weather);
      }
      return seq;
    };
    const a = await run();
    const b = await run();
    expect(a).toEqual(b);
    expect(a.length).toBe(15);
  });

  it('rolls a new same-day weather and shifts the 3-day forecast', async () => {
    const sim = await createSim({ seed: 99 });
    const days: { weather: Weather; forecast: Weather[] }[] = [];
    days.push({
      weather: sim.state.world.weather,
      forecast: [...sim.state.world.forecast],
    });
    for (let i = 0; i < 14; i++) {
      sim.sleep();
      days.push({
        weather: sim.state.world.weather,
        forecast: [...sim.state.world.forecast],
      });
    }

    for (let i = 1; i < days.length; i++) {
      const cur = days[i] ?? { weather: 'sun', forecast: [] };
      const prev = days[i - 1] ?? { weather: 'sun', forecast: [] };
      expect(cur.forecast).toHaveLength(3);
      expect(cur.forecast[0]).toBe(cur.weather);
      expect(cur.forecast[1]).toBe(prev.weather);
      expect(cur.forecast[2]).toBe(prev.forecast[1]);
      for (const w of cur.forecast) {
        expect(WEATHERS).toContain(w);
      }
    }
  });

  it('varies weather over a season instead of locking one value', async () => {
    const sim = await createSim({ seed: 31415 });
    const seq: Weather[] = [];
    for (let i = 0; i < 28 && seq.length < 28; i++) {
      seq.push(sim.state.world.weather);
      sim.sleep();
    }
    expect(new Set(seq).size).toBeGreaterThanOrEqual(2);
    const spring = seq;
    for (const w of spring) {
      expect(isAllowedInSeason(w, 0)).toBe(true);
    }
  });

  it('winter never rolls rain or storm, and snow appears', async () => {
    const sim = await createSim({ seed: 9001 });
    sim.store.state.world.calendar.seasonIndex = 3;
    sim.store.state.world.calendar.dayOfMonth = 1;
    sim.sleep(); // first roll under winter weights
    expect(sim.state.world.calendar.seasonIndex).toBe(3);

    const winterSeq: Weather[] = [sim.state.world.weather];
    for (let i = 0; i < 27; i++) {
      sim.sleep();
      winterSeq.push(sim.state.world.weather);
    }
    expect(winterSeq).toHaveLength(28);
    for (const w of winterSeq) {
      expect(w).not.toBe('rain');
      expect(w).not.toBe('storm');
      expect(['sun', 'snow', 'wind']).toContain(w);
    }
    expect(winterSeq).toContain('snow');
  });

  it('winter never rolls storm/rain even right at the season swap', async () => {
    const sim = await createSim({ seed: 42 });
    sim.store.state.world.calendar.seasonIndex = 3;
    sim.store.state.world.calendar.dayOfMonth = 27;
    sim.sleep(); // last winter day (28); weather rolls before the season turns
    expect(sim.state.world.calendar.seasonIndex).toBe(3);
    expect(['sun', 'snow', 'wind']).toContain(sim.state.world.weather);
  });
});

describe('weather effects (m2 §4)', () => {
  const TILE = { mapId: 'farm', x: 3, y: 3 };

  it('rain waters an unwatered crop through the night', async () => {
    const sim = await createSim();
    sim.useTool(TILE, 'hoe-t0');
    sim.useTool(TILE, 'parsnip-seed');
    expect(sim.cropData('farm', 3, 3)?.watered).toBe(false);

    sim.sleepWithWeather('rain');
    expect(sim.cropData('farm', 3, 3)?.stage).toBe(1); // rain counted as the day's watering
    expect(sim.cropData('farm', 3, 3)?.missedWater).toBe(0);
  });

  it('storm destroys crops deterministically by seed (pure)', async () => {
    const sim = await createSim();
    const farm = sim.store.state.maps['farm'];
    expect(farm).toBeDefined();
    if (!farm) throw new Error('farm map missing');
    for (let i = 0; i < 6; i++) {
      farm.placed[tileKey(1 + i, 1)] = {
        id: 'crop:parsnip',
        x: 1 + i,
        y: 1,
        data: { stage: 0, grownDays: 0, watered: false, missedWater: 0 },
      };
    }
    sim.store.state.world.weather = 'storm';
    const { lost } = applyWeatherEffects(sim.state, new Rng(7));
    expect(lost).toHaveLength(2);
    expect(lost.map((l) => `${l.x},${l.y}`)).toEqual(['5,1', '6,1']);
    for (const l of lost) {
      expect(l.cause).toBe('storm');
      expect(l.cropId).toBe('parsnip');
    }
  });

  it('storm through the sleep path removes crops and reports crop:lost', async () => {
    const sim = await createSim({ seed: 99 });
    const lost = sim.capture<{ cropId: string; cause: string; x: number; y: number }>('crop:lost');
    const farm = sim.store.state.maps['farm'];
    expect(farm).toBeDefined();
    if (!farm) throw new Error('farm map missing');
    for (let i = 0; i < 6; i++) {
      farm.placed[tileKey(1 + i, 1)] = {
        id: 'crop:parsnip',
        x: 1 + i,
        y: 1,
        data: { stage: 0, grownDays: 0, watered: false, missedWater: 0 },
      };
    }
    sim.sleepWithWeather('storm');
    expect(lost.length).toBeGreaterThanOrEqual(1);
    expect(lost.length).toBeLessThanOrEqual(6);
    for (const l of lost) {
      expect(sim.placed('farm', l.x, l.y)).toBeUndefined();
    }
    // Read the CURRENT (post-rollover) farm map, not the pre-sleep reference.
    const farmAfter = sim.state.maps['farm']?.placed ?? {};
    const remaining = Object.values(farmAfter).filter((o) => o.id.startsWith('crop:')).length;
    expect(remaining).toBe(6 - lost.length);
  });

  it('rejects tilling in winter as frozen', async () => {
    const sim = await createSim();
    const blocked = sim.capture<{ reason: string; tile: unknown }>('farming:blocked');
    sim.store.state.world.calendar.seasonIndex = 3;
    sim.store.state.world.calendar.dayOfMonth = 1;
    const energyBefore = sim.energy();

    sim.useTool(TILE, 'hoe-t0');
    expect(blocked).toEqual([{ reason: 'frozen', tile: TILE }]);
    expect(sim.placed('farm', 3, 3)).toBeUndefined();
    expect(sim.energy()).toBe(energyBefore); // no drain on a rejected action
  });
});
