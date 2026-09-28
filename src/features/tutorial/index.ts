/**
 * First-run tutorial feature entry point (WORKER-3 lane, T-0511). Self-registers.
 */
import { registerFeature } from '../../core/registry';
import { tutorialUi } from './tutorial';

registerFeature(tutorialUi);

export { tutorialUi, createTutorialUi } from './tutorial';
export * from './steps';
