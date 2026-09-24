import { describe, expect, it } from 'vitest';
import { createSim } from './harness';
import { WEATHERS, type Weather } from '@game/core/types';

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
