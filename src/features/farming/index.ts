/**
 * Farming feature entry point (WORKER-2 lane). Exports the sim submodules and
 * self-registers them (the registry TDZ was fixed core-side in M1 by moving
 * the eager feature glob to src/features/auto-import.ts — see that file).
 */
import { registerFeature } from '../../core/registry';
import { farmingSim } from './sim/FarmingSim';
import { shippingSim } from './sim/ShippingSim';
import { seedWeatherSim } from './sim/SeedWeatherSim';

registerFeature(farmingSim);
registerFeature(shippingSim);
registerFeature(seedWeatherSim);

export { farmingSim, shippingSim, seedWeatherSim };
