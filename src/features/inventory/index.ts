/**
 * Inventory feature entry point (WORKER-2 lane). Exports the sim submodule and
 * self-registers it (registry TDZ fixed core-side in M1 — see auto-import.ts).
 */
import { registerFeature } from '../../core/registry';
import { inventorySim } from './sim/InventorySim';

registerFeature(inventorySim);

export { inventorySim };
