/**
 * audio:ui feature entry — auto-imported by src/features/auto-import.ts, which
 * executes this file and registers the audio + music modules on the shared
 * registry.
 */
import { registerFeature } from '../../core/registry';
import { audioUi } from './audio';
import { musicUi } from './music';

registerFeature(audioUi);
registerFeature(musicUi);

export { AudioEngine, audioUi, coinTone, failTone, footstepTone, successTone } from './audio';
export type { ToneSpec } from './audio';
export { buildBar, chordMidis, midiToFreq, moodForHour, MusicEngine, musicUi, resolveMusicTheme } from './music';
export type { MusicContext, MusicMood, MusicNote, MusicPlan, MusicTheme } from './music';
export {
  audioBuses,
  audioContextCount,
  audioGestureSeen,
  installAudioUnlock,
  MASTER_GAIN,
  MUSIC_BUS_GAIN,
  sharedAudioContext,
  SFX_BUS_GAIN,
  unlockAudio,
} from './context';
export type { AudioBuses } from './context';