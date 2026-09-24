/**
 * Engine feature (WORKER-1, lanes world + sim). Defines the position/collision
 * sim module and the Three.js view module. Self-registers on import.
 */
import { registerFeature } from '../../core/registry';
import { engineSim } from './sim/PlayerPosition';
import { engineView } from './view/EngineView';

// Side-effect registration: auto-import.ts loads this file after the registry
// module body has initialized, so calling registerFeature here is safe.
registerFeature(engineSim);
registerFeature(engineView);

export { engineSim, engineView };