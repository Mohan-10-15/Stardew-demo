/**
 * Shop feature entry point (WORKER-2 lane). Exports the sim submodule and
 * self-registers it (registry TDZ fixed core-side in M1 — see auto-import.ts).
 * Only the sim is owned here; the shop UI (WORKER-3) is a separate feature.
 */
import { registerFeature } from '../../core/registry';
import { shopSim } from './sim/ShopSim';

registerFeature(shopSim);

export { shopSim };