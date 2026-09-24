import { describe, expect, it } from 'vitest';
import { createSim } from './harness';

const TILE = { mapId: 'farm', x: 3, y: 3 };

interface StartedEvent {
  dayCount: number;
}
interface ReportEvent {
  total: number;
}

describe('day loop (headless bot)', () => {
  it('advances 7 days through sleep without throwing and lands the calendar', async () => {
    const sim = await createSim({ seed: 31337 });
    const started = sim.capture<StartedEvent>('day:started');
    const reports = sim.capture<ReportEvent>('shipping:report');
    const rolled = sim.capture('day:rollover');
    const weather = sim.capture<{ weather: string }>('weather:changed');

    for (let day = 0; day < 7; day++) {
      sim.tickMinutes(60);
      sim.sleep();
    }

    expect(started).toHaveLength(7);
    expect(reports).toHaveLength(7);
    expect(rolled).toHaveLength(7);
    expect(weather).toHaveLength(7);
    expect(sim.state.world.dayCount).toBe(8);
    expect(sim.state.world.calendar).toEqual({ year: 1, seasonIndex: 0, dayOfMonth: 8 });
    expect(sim.state.world.clock).toEqual({ hour: 6, minute: 0 });
    expect(sim.state.world.passedOut).toBe(false);
    expect(sim.energy()).toBe(270);
  });

  it('grows a crop to maturity across a 7-day bot run', async () => {
    const sim = await createSim({ seed: 8 });
    sim.useTool(TILE, 'hoe-t0');
    sim.useTool(TILE, 'parsnip-seed');

    let waterings = 0;
    for (let day = 0; day < 7; day++) {
      const stage = Number(sim.cropData('farm', 3, 3)?.stage ?? 0);
      if (stage < 4) {
        sim.useTool(TILE, 'watering-can-t0');
        waterings += 1;
      }
      sim.sleep();
    }

    expect(waterings).toBe(4);
    expect(sim.cropData('farm', 3, 3)?.stage).toBe(4);
    expect(sim.placed('farm', 3, 3)?.id).toBe('crop:parsnip');
    expect(sim.energy()).toBe(270);
  });

  it('rolls the day via the core time:tick pass-out path', async () => {
    const sim = await createSim();
    const started = sim.capture<StartedEvent>('day:started');
    sim.useTool(TILE, 'hoe-t0');
    sim.useTool(TILE, 'parsnip-seed');
    sim.useTool(TILE, 'watering-can-t0');

    sim.store.state.world.clock = { hour: 1, minute: 50 };
    sim.tickStep();

    expect(sim.state.world.dayCount).toBe(2);
    expect(sim.state.world.passedOut).toBe(true);
    expect(sim.state.world.clock).toEqual({ hour: 2, minute: 0 });
    expect(sim.state.world.calendar.dayOfMonth).toBe(2);
    expect(sim.cropData('farm', 3, 3)?.stage).toBe(1);
    // no day:started from the tick path (WORKER-3 owns morning hand-off)
    expect(started).toHaveLength(0);
  });

  it('clock ticks from 06:00 and sleep always lands on the next morning', async () => {
    const sim = await createSim();
    expect(sim.state.world.clock).toEqual({ hour: 6, minute: 0 });
    sim.tickMinutes(130); // 06:00 -> 08:10
    expect(sim.state.world.clock).toEqual({ hour: 8, minute: 10 });
    sim.tickMinutes(100); // 08:10 -> 09:50
    sim.sleep(); // sleeping at 09:50 lands next day 06:00
    expect(sim.state.world.clock).toEqual({ hour: 6, minute: 0 });
    expect(sim.state.world.dayCount).toBe(2);
  });

  it('a fresh sleep loop does not double-apply day rollover within the same day', async () => {
    const sim = await createSim();
    sim.useTool(TILE, 'hoe-t0');
    sim.useTool(TILE, 'parsnip-seed');
    sim.useTool(TILE, 'watering-can-t0');

    sim.sleep();
    const afterFirstStage = Number(sim.cropData('farm', 3, 3)?.stage ?? 0);
    expect(afterFirstStage).toBe(1);

    // more ticks on the SAME morning must not grow/crumble again
    sim.tickMinutes(120);
    expect(sim.cropData('farm', 3, 3)?.stage).toBe(1);
    expect(sim.state.world.weather).toBe(sim.state.world.forecast[0]);
  });
});
