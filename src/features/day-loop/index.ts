/**
 * Day-loop UI feature entry point (WORKER-3 lane, T-0511). Owns the
 * keyboard day loop's on-screen half: the action bar, the farm dialog
 * (animals / machines / shipping) and the denial toasts. Self-registers.
 */
import { registerFeature } from '../../core/registry';
import { dayLoopUi } from './day-loop';

registerFeature(dayLoopUi);

export { dayLoopUi, createDayLoopUi } from './day-loop';
export * from './format';
