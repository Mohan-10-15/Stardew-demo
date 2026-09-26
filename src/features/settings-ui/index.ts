import { registerFeature } from '../../core/registry';
import { settingsUi } from './settings';

registerFeature(settingsUi);

export { createSettingsUi } from './settings';
export { settingsUi } from './settings';
export {
  DEFAULT_AUDIO_PREFS,
  normalizeAudioPrefs,
  readAudioPrefs,
  writeAudioPrefs,
  type AudioPrefs,
} from './prefs';