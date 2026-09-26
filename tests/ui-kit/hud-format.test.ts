/**
 * HUD format helpers for T-0405 (WORKER-3 lane): the food-buff line draining
 * over time and the interaction hint describing the tile in front of the
 * player. Both are pure view-models driven by live sim state.
 */
import { describe, expect, it } from 'vitest';
import { craftingSim } from '@game/features/crafting';
import { machinesSim } from '@game/features/machines';
import {
  activeBuffRows,
  buffMinutesLeft,
  formatBuffDuration,
  interactionHint,
} from '@game/features/hud/format';
import { tileInFront } from '@game/features/engine/sim/PlayerPosition';
import { createSim, DEFAULT_MODULES } from '../../tests/sim/harness';

async function buffFixture() {
  const fx = await createSim({ modules: [...DEFAULT_MODULES, craftingSim] });
  fx.giveItem('ember-bloom', 1);
  fx.giveItem('fiber', 3);
  return fx;
}

async function machineFixture() {
  const fx = await createSim({ modules: [...DEFAULT_MODULES, machinesSim] });
  fx.giveItem('mayonnaise-machine', 1);
  fx.giveItem('egg', 3);
  return fx;
}

describe('hud buff line', () => {
  it('renders an eaten tea as a timed Luck buff', async () => {
    const fx = await buffFixture();
    fx.dispatch('crafting:craft', { recipeId: 'ember-bloom-tea' });
    const slot = fx.state.player.inventory.slots.findIndex((s) => s?.id === 'ember-bloom-tea');
    fx.dispatch('player:eat', { slot });
    const rows = activeBuffRows(fx.state, undefined);
    expect(rows).toEqual([{ statLabel: 'Luck', amount: 1, remaining: '3h' }]);
  });

  it('counts the buff down over time and prunes it when spent', async () => {
    const fx = await buffFixture();
    fx.dispatch('crafting:craft', { recipeId: 'ember-bloom-tea' });
    const slot = fx.state.player.inventory.slots.findIndex((s) => s?.id === 'ember-bloom-tea');
    fx.dispatch('player:eat', { slot });
    fx.tickMinutes(30);
    expect(activeBuffRows(fx.state)[0]?.remaining).toBe('2h 30m');
    fx.tickMinutes(2 * 60 + 30);
    expect(activeBuffRows(fx.state)).toEqual([]);
  });

  it('returns no rows on a fresh game', async () => {
    const fx = await buffFixture();
    expect(activeBuffRows(fx.state)).toEqual([]);
  });

  it('snaps remaining time up to whole ten-minute ticks', () => {
    expect(buffMinutesLeft({ expiresAt: 1000 }, 1000)).toBe(0);
    expect(buffMinutesLeft({ expiresAt: 1000 }, 985)).toBe(20);
    expect(formatBuffDuration(150)).toBe('2h 30m');
    expect(formatBuffDuration(120)).toBe('2h');
    expect(formatBuffDuration(45)).toBe('45m');
  });
});

describe('hud interaction hint', () => {
  it('hints Load for an empty machine, busy then collect otherwise', async () => {
    const fx = await machineFixture();
    const tile = { mapId: 'farm', x: 5, y: 5 };
    fx.dispatch('machines:place', { tile, itemId: 'mayonnaise-machine' });

    expect(interactionHint(fx.state, fx.content, tile)).toEqual({ name: 'Mayonnaise Machine', action: 'load' });

    const eggSlot = fx.state.player.inventory.slots.findIndex((s) => s?.id === 'egg');
    fx.dispatch('machines:insert', { tile, slot: eggSlot });
    expect(interactionHint(fx.state, fx.content, tile)).toEqual({ name: 'Mayonnaise Machine', action: 'busy' });

    fx.tickMinutes(3 * 60);
    expect(interactionHint(fx.state, fx.content, tile)).toEqual({ name: 'Mayonnaise Machine', action: 'collect' });
  });

  it('computes the player-facing tile via the real interact route', async () => {
    const fx = await machineFixture();
    const front = { ...tileInFront(fx.state.player.position, fx.state.player.facing), mapId: fx.state.player.position.mapId };
    expect(front).toEqual({ mapId: 'farm', x: 24, y: 21 });
    expect(interactionHint(fx.state, fx.content, front)).toBeNull();
  });

  it('returns null on empty tiles and a generic interact otherwise', async () => {
    const fx = await machineFixture();
    expect(interactionHint(fx.state, fx.content, { mapId: 'farm', x: 30, y: 30 })).toBeNull();
    const hint = interactionHint(fx.state, fx.content, { mapId: 'farm', x: 20, y: 6 }); // weed debris
    expect(hint?.action).toBe('interact');
    expect(hint?.name.length).toBeGreaterThan(0);
  });
});