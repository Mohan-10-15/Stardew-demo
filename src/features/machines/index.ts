import { registerFeature } from '../../core/registry';
import { machinesSim } from './sim/MachinesSim';

registerFeature(machinesSim);

export {
  collectMachine,
  insertMachine,
  interactMachine,
  isTileWalkable,
  machineAtTile,
  machineDefOf,
  machineIdOf,
  machinesSim,
  MACHINE_PREFIX,
  placeMachine,
  tickMachines,
} from './sim/MachinesSim';
export type { MachineDeps, MachineResult } from './sim/MachinesSim';