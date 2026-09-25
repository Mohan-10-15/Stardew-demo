/**
 * ADDENDUM B (A) — interaction feedback contract. Every tool outcome must emit
 * a DISTINCT event: successes fire `tool:used` (with a concrete effect), every
 * failure fires `tool:failed` (with a reason) so the view can flash red and
 * the audio lane can pick a different blip. No failure shares the success bus.
 */
import { describe, expect, it } from 'vitest';
import { createSim } from './harness';

const TILE = { mapId: 'farm', x: 3, y: 3 };

interface UsedEvent {
  toolId: string;
  effect: string;
}

interface FailedEvent {
  tile: unknown;
  toolId: string | null;
  reason: string;
}

describe('ADDENDUM B-A: distinct tool success/failure events', () => {
  it('fires tool:used only on success and tool:failed on a blocked hoe swing', async () => {
    const sim = await createSim();
    const used = sim.capture<UsedEvent>('tool:used');
    const failed = sim.capture<FailedEvent>('tool:failed');

    sim.useTool(TILE, 'hoe-t0');
    expect(used.map((u) => u.effect)).toEqual(['tilled']);
    expect(failed).toHaveLength(0);

    sim.useTool({ mapId: 'farm', x: 22, y: 6 }, 'hoe-t0'); // rock occupies the tile

    expect(used).toHaveLength(1);
    expect(failed).toHaveLength(1);
    expect(failed[0]?.reason).toBe('occupied');
    expect(failed[0]?.toolId).toBe('hoe-t0');
  });

  it('fires tool:failed with reason nothing for a bare-hand swing on empty ground', async () => {
    const sim = await createSim();
    const used = sim.capture<UsedEvent>('tool:used');
    const failed = sim.capture<FailedEvent>('tool:failed');

    sim.useTool(TILE, '');

    expect(used).toHaveLength(0);
    expect(failed).toHaveLength(1);
    expect(failed[0]?.reason).toBe('nothing');
  });

  it('fires tool:failed with reason frozen when the soil is iced over (winter)', async () => {
    const sim = await createSim();
    const used = sim.capture<UsedEvent>('tool:used');
    const failed = sim.capture<FailedEvent>('tool:failed');
    const blocked = sim.capture<{ reason: string }>('farming:blocked');

    sim.state.world.calendar.seasonIndex = 3;
    sim.useTool(TILE, 'hoe-t0');

    expect(used).toHaveLength(0);
    expect(failed[0]?.reason).toBe('frozen');
    expect(blocked[0]?.reason).toBe('frozen');
  });

  it('fires tool:failed with reason exhausted when energy cannot cover the swing', async () => {
    const sim = await createSim();
    const failed = sim.capture<FailedEvent>('tool:failed');

    sim.store.state.player.energy = 4;
    sim.useTool(TILE, 'hoe-t0');

    expect(failed[0]?.reason).toBe('exhausted');
    expect(sim.placed('farm', 3, 3)).toBeUndefined();
  });

  it('does not double-fire: one outcome, exactly one feedback event', async () => {
    const sim = await createSim();
    const used = sim.capture<UsedEvent>('tool:used');
    const failed = sim.capture<FailedEvent>('tool:failed');

    sim.useTool(TILE, 'hoet0'); // unknown id -> hands kind
    const outcome = used.length + failed.length;
    expect(outcome).toBe(1);
  });
});