/**
 * Audio preferences for settings:ui (WORKER-3 lane, T-0405). Pure-normalized
 * defaults survive save/reload via localStorage when a browser is present and
 * degrade to the same defaults headless — so every branch is unit-testable.
 */
export interface AudioPrefs {
  musicEnabled: boolean;
  /** 0..1 master music volume. */
  musicVolume: number;
}

export const DEFAULT_AUDIO_PREFS: AudioPrefs = {
  musicEnabled: false,
  musicVolume: 0.6,
};

/** Clamp / coerce arbitrary raw storage into valid prefs. */
export function normalizeAudioPrefs(raw: unknown): AudioPrefs {
  const out: AudioPrefs = { ...DEFAULT_AUDIO_PREFS };
  if (raw && typeof raw === 'object') {
    const r = raw as Record<string, unknown>;
    if (typeof r.musicEnabled === 'boolean') out.musicEnabled = r.musicEnabled;
    if (typeof r.musicVolume === 'number' && Number.isFinite(r.musicVolume)) {
      out.musicVolume = Math.min(1, Math.max(0, r.musicVolume));
    }
  }
  return out;
}

const PREF_KEY = 'eh.audio';

export function readAudioPrefs(): AudioPrefs {
  if (typeof window === 'undefined' || typeof window.localStorage === 'undefined') {
    return { ...DEFAULT_AUDIO_PREFS };
  }
  try {
    const raw = window.localStorage.getItem(PREF_KEY);
    return raw === null ? { ...DEFAULT_AUDIO_PREFS } : normalizeAudioPrefs(JSON.parse(raw));
  } catch {
    return { ...DEFAULT_AUDIO_PREFS };
  }
}

export function writeAudioPrefs(prefs: AudioPrefs): void {
  if (typeof window === 'undefined' || typeof window.localStorage === 'undefined') return;
  try {
    window.localStorage.setItem(PREF_KEY, JSON.stringify(normalizeAudioPrefs(prefs)));
  } catch {
    // private browsing / quota: prefs just stay session-only
  }
}