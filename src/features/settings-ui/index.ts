import { registerFeature } from '../../core/registry';
import { settingsUi } from './settings';

registerFeature(settingsUi);

export { createSettingsUi } from './settings';
export { settingsUi } from './settings';
export { settingsPanelModel, togglePrefs, type SettingsPanelModel } from './panel-model';
export {
  DEFAULT_AUDIO_PREFS,
  normalizeAudioPrefs,
  readAudioPrefs,
  writeAudioPrefs,
  type AudioPrefs,
} from './prefs';
