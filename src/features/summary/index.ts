/**
 * End-of-day summary feature entry point (WORKER-3 lane). Self-registers on
 * import; the core auto-import glob picks this file up automatically.
 */
import { registerFeature } from '../../core/registry';
import { summaryUi } from './summary';

registerFeature(summaryUi);

export { summaryUi, createSummaryUi } from './summary';
export * from './format';