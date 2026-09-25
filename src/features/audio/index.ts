/**
 * audio:ui feature entry — auto-imported by src/features/auto-import.ts, which
 * executes this file and registers the audio module on the shared registry.
 */
import { registerFeature } from '../../core/registry';
import { audioUi } from './audio';

registerFeature(audioUi);

export { AudioEngine, audioUi, coinTone, failTone, footstepTone, successTone } from './audio';
export type { ToneSpec } from './audio';