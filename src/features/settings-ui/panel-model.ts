/**
 * settings-ui/panel-model.ts (WORKER-3 lane, T-0503) — the pure "what does the
 * panel show" layer of the K dialog.
 *
 * The dialog itself is DOM-only, so this module holds the part that can be
 * pinned headlessly: prefs in, the exact strings/values the Music row, the
 * on/off switch and the volume readout must use. `settings.ts` renders from
 * this, which is what keeps the switch, the slider and the K-hotkey honest
 * about each other (a bug once shipped where the Music row was built but never
 * appended, so the toggle was invisible).
 */
import { MESSAGES, type Messages } from '../ui-kit/i18n/en';
import { replaceTokens } from '../ui-kit/template';
import { normalizeAudioPrefs, type AudioPrefs } from './prefs';

export interface SettingsPanelModel {
  /** Text of the Music on/off switch. */
  readonly toggleText: string;
  /** `role=switch` state. */
  readonly toggleChecked: boolean;
  /** Accessible name for the switch. */
  readonly toggleAria: string;
  /** Slider position, 0..100. */
  readonly volumeValue: number;
  /** Readout next to the slider, e.g. "60%". */
  readonly volumeText: string;
  /** Row labels, in render order. */
  readonly rows: readonly { readonly label: string; readonly control: 'switch' | 'slider' }[];
}

/** Resolve the whole panel from (possibly unnormalized) prefs. */
export function settingsPanelModel(
  raw: unknown,
  messages: Messages = MESSAGES,
): SettingsPanelModel {
  const prefs: AudioPrefs = normalizeAudioPrefs(raw);
  const state = prefs.musicEnabled ? messages.settings.on : messages.settings.off;
  const percent = Math.round(prefs.musicVolume * 100);
  return {
    toggleText: replaceTokens(messages.settings.musicToggle, { state }),
    toggleChecked: prefs.musicEnabled,
    toggleAria: replaceTokens(messages.settings.musicAria, { state }),
    volumeValue: percent,
    volumeText: replaceTokens(messages.settings.volumePercent, { percent: String(percent) }),
    rows: [
      { label: messages.settings.music, control: 'switch' },
      { label: messages.settings.volume, control: 'slider' },
    ],
  };
}

/** Flipping the switch yields the mirrored model, whatever came in before. */
export function togglePrefs(raw: unknown): AudioPrefs {
  const prefs = normalizeAudioPrefs(raw);
  return { ...prefs, musicEnabled: !prefs.musicEnabled };
}
