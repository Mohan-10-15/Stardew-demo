/**
 * Weather feature module (WORKER-2 lane, contract m1-contracts.md section 7).
 *
 * The roll itself lives in weather.ts as a guarded pure function so it can be
 * invoked from either rollover path (core time:tick or player:sleep) without
 * double-firing; this module owns the id + registers defensive reducers for
 * both paths so weather keeps working even when the other farming modules are
 * not mounted (e.g. isolated tests).
 */
import type { FeatureContext, FeatureModule } from '@game/core/feature';
import { defineFeature } from '@game/core/feature';
import { ensureWeatherExt } from './ext';
import { applyWeatherRoll } from './weather';

export const seedWeatherSim: FeatureModule = defineFeature({
  id: 'farming:weather',
  lane: 'sim',
  setup(ctx: FeatureContext) {
    ctx.store.replaceState(ensureWeatherExt(ctx.store.state));
    ctx.store.registerReducer('time:tick', (st, _action, rng) =>
      applyWeatherRoll(st, rng, ctx.bus),
    );
    ctx.store.registerReducer('player:sleep', (st, _action, rng) =>
      applyWeatherRoll(st, rng, ctx.bus),
    );
  },
});
