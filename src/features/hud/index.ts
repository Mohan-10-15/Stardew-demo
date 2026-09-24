/**
 * HUD feature entry point (WORKER-3 lane). Self-registers on import; the core
 * auto-import glob picks this file up automatically.
 */
import { registerFeature } from '../../core/registry';
import { hudUi } from './hud';

registerFeature(hudUi);

export { hudUi, createHudUi, HOTBAR_SLOTS } from './hud';
export * from './format';