/**
 * Input feature entry point (WORKER-3 lane). Self-registers on import; the core
 * auto-import glob picks this file up automatically.
 */
import { registerFeature } from '../../core/registry';
import { inputUi } from './input';

registerFeature(inputUi);

export { inputUi, createInputUi, HOLD_INTERVAL_MS } from './input';
export {
  DEFAULT_KEYMAP,
  HOTBAR_SLOT_KEYS,
  actionToSim,
  buildKeyIndex,
  findBinding,
  normalizeKey,
  type InputAction,
  type InputSimAction,
  type KeyBinding,
} from './keymap';