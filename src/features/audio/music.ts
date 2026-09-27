/**
 * music:ui — original procedural WebAudio soundtrack (WORKER-3 lane).
 *
 * No audio files and no licensed music: every loop is synthesized live from
 * pure data (scales, chord progressions, tempi) so the "Minecraft-POV electron"
 * request keeps an entirely original sound. Theme selection is context-driven
 * (time of day, season, weather, map biome, low health) and the bar generator
 * is deterministic given a seed, so the headless bot and the browser hear the
 * same arrangement for the same game (tests/…/music.test.ts).
 *
 * The engine shares the one game-wide AudioContext and the `music` bus with the
 * cue engine (see ./context.ts), which is what keeps the soundtrack tucked
 * under the SFX. On/off and volume come from the audio prefs the K panel writes,
 * so the toggle is authoritative — the engine never turns itself on.
 *
 * Registered by src/features/audio/index.ts. Headless-safe: in Node the
 * MusicEngine never starts a timer or an AudioContext; every event hook
 * degrades to a no-op and all logic still has unit coverage.
 */
import { defineFeature } from '../../core/feature';
import { Rng } from '@game/core/rng';
import type { SeasonIndex, Weather } from '@game/core/types';
import { readAudioPrefs } from '../settings-ui/prefs';
import { audioBuses, installAudioUnlock, type AudioBuses } from './context';
import { recordMusicBar } from './cues';

export type MusicMood = 'dawn' | 'day' | 'dusk' | 'night' | 'late' | 'home' | 'cave' | 'danger';

export interface MusicContext {
  /** 0..23 in-game hour. */
  hour: number;
  weather: Weather;
  seasonIndex: SeasonIndex;
  mapId: string;
  /** Player health fraction 0..1; low health flips the music to the danger mood. */
  healthPct?: number;
}

export interface MusicTheme {
  /** Composite signature used by the engine to detect real changes. */
  id: string;
  mood: MusicMood;
  /** Root MIDI note of the key. */
  root: number;
  /** Ascending semitone offsets of the scale within one octave. */
  steps: readonly number[];
  bpm: number;
  /** Bar density 0..1: higher = more lead notes and fuller texture. */
  density: number;
  leadWave: OscillatorType;
  bassWave: OscillatorType;
  /** Extra semitones for the lead voice (weather airiness). */
  bright: number;
  pad: boolean;
  perc: boolean;
}

export interface MusicNote {
  /** Seconds from the start of the bar. */
  at: number;
  midi: number;
  freq: number;
  dur: number;
  gain: number;
  wave: OscillatorType;
  role: 'bass' | 'pad' | 'lead' | 'perc';
}

export interface MusicPlan {
  bar: number;
  /** Bar length in seconds (4/4 at theme.bpm). */
  duration: number;
  bass: MusicNote[];
  pad: MusicNote[];
  lead: MusicNote[];
  perc: MusicNote[];
  /** Every scheduled note in one flat list. */
  notes: MusicNote[];
}

const ACCIDENTAL_FIFTH_UP = 7;

/** Ascending semitone ladder over `spans` octaves of a scale, for degree math. */
function scaleLadder(steps: readonly number[], spans: number): number[] {
  const out: number[] = [];
  for (let oct = 0; oct < spans; oct++) {
    for (const s of steps) out.push(oct * 12 + s);
  }
  return out;
}

const SEASON_SCALES: Record<SeasonIndex, { root: number; steps: readonly number[] }> = {
  0: { root: 55, steps: [0, 2, 4, 5, 7, 9, 11] }, // spring, Ionian
  1: { root: 57, steps: [0, 2, 4, 6, 7, 9, 11] }, // summer, Lydian
  2: { root: 53, steps: [0, 2, 4, 5, 7, 9, 10] }, // fall, Mixolydian
  3: { root: 50, steps: [0, 3, 5, 7, 10] }, // winter, pentatonic minor
};

interface Profile {
  bpm: number;
  density: number;
  pad: boolean;
  perc: boolean;
  leadWave: OscillatorType;
  bassWave: OscillatorType;
}

const TIME_PROFILE: Record<Exclude<MusicMood, 'home' | 'cave' | 'danger'>, Profile> = {
  dawn: { bpm: 78, density: 0.55, pad: true, perc: false, leadWave: 'triangle', bassWave: 'sine' },
  day: { bpm: 96, density: 0.9, pad: false, perc: true, leadWave: 'triangle', bassWave: 'sine' },
  dusk: { bpm: 80, density: 0.7, pad: true, perc: false, leadWave: 'sine', bassWave: 'sine' },
  night: { bpm: 62, density: 0.45, pad: true, perc: false, leadWave: 'sine', bassWave: 'sine' },
  late: { bpm: 66, density: 0.4, pad: true, perc: false, leadWave: 'sine', bassWave: 'sine' },
};

const OVERRIDE_PROFILE: Record<'home' | 'cave' | 'danger', Profile & { root: number }> = {
  home: {
    bpm: 70,
    density: 0.5,
    pad: true,
    perc: false,
    leadWave: 'sine',
    bassWave: 'triangle',
    root: 53,
  },
  cave: {
    bpm: 84,
    density: 0.6,
    pad: false,
    perc: true,
    leadWave: 'triangle',
    bassWave: 'sawtooth',
    root: 45,
  },
  danger: {
    bpm: 112,
    density: 0.85,
    pad: false,
    perc: true,
    leadWave: 'sawtooth',
    bassWave: 'sawtooth',
    root: 43,
  },
};

/** Root scale per mood (cave = natural minor, danger = phrygian). */
const OVERRIDE_STEPS: Record<'home' | 'cave' | 'danger', readonly number[]> = {
  home: [0, 2, 4, 5, 7, 9, 11],
  cave: [0, 2, 3, 5, 7, 8, 10],
  danger: [0, 1, 3, 5, 7, 8, 10],
};

/** Bar roots as scale degrees, one per bar, cycled. */
const PROGRESSIONS: Record<MusicMood, readonly number[]> = {
  dawn: [0, 3, 5, 3],
  day: [0, 4, 3, 5],
  dusk: [0, 5, 3, 5],
  night: [4, 0, 5, 3],
  late: [3, 0, 5, 3],
  home: [0, 3, 0, 3],
  cave: [0, 0, 5, 5],
  danger: [0, 1, 0, 1],
};

const WEATHER_MOD: Record<
  Weather,
  Partial<Pick<MusicTheme, 'leadWave' | 'bright' | 'pad' | 'perc' | 'density'>>
> = {
  sun: {},
  rain: { leadWave: 'sine', bright: 12, pad: true, perc: false, density: -0.2 },
  storm: { leadWave: 'sawtooth', bright: 0, pad: false, perc: true, density: 0.1 },
  snow: { leadWave: 'sine', bright: 12, pad: true, perc: false, density: -0.25 },
  wind: { leadWave: 'sine', bright: 0, pad: true, perc: false, density: -0.15 },
};

export function moodForHour(hour: number): MusicMood {
  const h = ((hour % 24) + 24) % 24;
  if (h >= 21 || h < 3) return 'night';
  if (h >= 19) return 'dusk';
  if (h >= 17) return 'dusk';
  if (h >= 8) return 'day';
  if (h >= 6) return 'dawn';
  return 'late';
}

export function resolveMusicTheme(ctx: MusicContext): MusicTheme {
  const season = SEASON_SCALES[ctx.seasonIndex] ?? SEASON_SCALES[0];
  let mood: MusicMood = moodForHour(ctx.hour);
  const place =
    ctx.mapId.includes('mine') || ctx.mapId.includes('cave')
      ? 'cave'
      : ctx.mapId === 'home'
        ? 'home'
        : 'none';
  if (place !== 'none') mood = place;
  const low = ctx.healthPct !== undefined && ctx.healthPct >= 0 && ctx.healthPct < 0.35;
  if (low) mood = 'danger';

  const time = TIME_PROFILE[mood as keyof typeof TIME_PROFILE];
  const ovr = OVERRIDE_PROFILE[mood as keyof typeof OVERRIDE_PROFILE] ?? null;
  const root = ovr?.root ?? season.root;
  const steps = ovr
    ? (OVERRIDE_STEPS[mood as keyof typeof OVERRIDE_STEPS] ?? season.steps)
    : season.steps;

  const mod = WEATHER_MOD[ctx.weather];
  const theme: MusicTheme = {
    id: '',
    mood,
    root,
    steps,
    bpm: ovr?.bpm ?? time.bpm,
    density: clamp01((ovr?.density ?? time.density) + (mod.density ?? 0)),
    leadWave: (mod.leadWave ?? ovr?.leadWave ?? time.leadWave) as OscillatorType,
    bassWave: (ovr?.bassWave ?? time.bassWave) as OscillatorType,
    bright: mod.bright ?? 0,
    pad: mod.pad ?? ovr?.pad ?? time.pad,
    perc: mod.perc ?? ovr?.perc ?? time.perc,
  };
  theme.id = [
    theme.mood,
    ctx.seasonIndex,
    ctx.weather,
    ctx.mapId,
    theme.bpm,
    theme.density,
    theme.perc,
    theme.leadWave,
    theme.bright,
  ].join('|');
  return theme;
}

function clamp01(v: number): number {
  return Math.min(1, Math.max(0, v));
}

/** midi -> frequency (A4 = 440 Hz, midi 69). */
export function midiToFreq(midi: number): number {
  return 440 * Math.pow(2, (midi - 69) / 12);
}

/** Chord tones (consecutive scale degrees above the bar root) as MIDI. */
export function chordMidis(theme: MusicTheme, degree: number, ladder: readonly number[]): number[] {
  const rootMidi = theme.root + ladder[degree]!;
  return [0, 2, 4].map((i) => rootMidi + ladder[(degree + i) % ladder.length]! - ladder[degree]!);
}

/** Build one deterministic 4/4 bar of the arrangement. */
export function buildBar(theme: MusicTheme, rng: Rng, barIndex: number): MusicPlan {
  const ladder = scaleLadder(theme.steps, 3);
  const prog = PROGRESSIONS[theme.mood] ?? PROGRESSIONS.day;
  const degree = prog[Math.abs(barIndex) % prog.length]!;
  const barBeat = 60 / theme.bpm;
  const sixteenth = barBeat / 4;
  const duration = barBeat * 4;
  const rootMidi = theme.root + ladder[degree]!;

  const bass: MusicNote[] = [];
  const pad: MusicNote[] = [];
  const lead: MusicNote[] = [];
  const perc: MusicNote[] = [];

  const bassRoot = rootMidi >= 43 ? rootMidi - 12 : rootMidi;
  bass.push(
    {
      at: 0,
      midi: bassRoot,
      freq: midiToFreq(bassRoot),
      dur: duration * 0.85,
      gain: 0.16,
      wave: theme.bassWave,
      role: 'bass',
    },
    {
      at: 8 * sixteenth,
      midi: bassRoot + ACCIDENTAL_FIFTH_UP,
      freq: midiToFreq(bassRoot + ACCIDENTAL_FIFTH_UP),
      dur: duration * 0.35,
      gain: 0.1,
      wave: theme.bassWave,
      role: 'bass',
    },
  );

  if (theme.pad) {
    const chord = chordMidis(theme, degree, ladder);
    chord.forEach((midi, i) => {
      pad.push({
        at: 0,
        midi,
        freq: midiToFreq(midi),
        dur: duration * 0.95,
        gain: 0.05 - i * 0.008,
        wave: 'sine',
        role: 'pad',
      });
    });
  }

  if (theme.perc) {
    perc.push({
      at: 0,
      midi: 38,
      freq: midiToFreq(38),
      dur: sixteenth * 3,
      gain: 0.22,
      wave: 'sine',
      role: 'perc',
    });
    for (const off of [2, 6, 10, 14]) {
      perc.push({
        at: off * sixteenth,
        midi: 92,
        freq: midiToFreq(92),
        dur: sixteenth,
        gain: 0.05,
        wave: 'square',
        role: 'perc',
      });
    }
  }

  const quarters = [0, 1, 2, 3].map((q) => q * 4 * sixteenth);
  const count = theme.density >= 0.75 ? 4 : theme.density >= 0.5 ? 3 : 2;
  const picked = rng
    .shuffle([...quarters])
    .slice(0, count)
    .sort((a, b) => a - b);
  const degLo = degree;
  const degHi = Math.min(degree + 5, ladder.length - 1);
  let cursor = degree + rng.int(0, 3);
  for (let i = 0; i < count; i++) {
    cursor += i === 0 ? 0 : rng.pick([-2, -1, -1, 0, 1, 1, 2] as const);
    cursor = Math.max(degLo, Math.min(degHi, cursor));
    const midi = theme.root + theme.bright + 12 + ladder[cursor]!;
    const off = rng.chance(0.4) ? sixteenth : 0;
    const dur = (rng.chance(0.35) ? 8 : 4) * sixteenth;
    const at = picked[i]! + off;
    lead.push({
      at,
      midi,
      freq: midiToFreq(midi),
      dur,
      gain: at % barBeat === 0 ? 0.12 : 0.08,
      wave: theme.leadWave,
      role: 'lead',
    });
  }

  const notes = [...bass, ...pad, ...lead, ...perc].sort((a, b) => a.at - b.at);
  return { bar: barIndex, duration, bass, pad, lead, perc, notes };
}

/**
 * Live scheduling engine. Headless-safe: no AudioContext or timer is ever
 * created without a window, and the arrangement itself is plain data so tests
 * run against MusicPlan rather than hardware.
 */
export class MusicEngine {
  private buses: AudioBuses | null = null;
  private rng: Rng;
  private theme: MusicTheme | null = null;
  private barIndex = 0;
  private nextBarAt = 0;
  private enabled = false;
  private volume = 0.6;
  private timer: number | null = null;
  private currentId: string | null = null;
  /** True once the bar clock has been pinned to the context's currentTime. */
  private anchored = false;
  /**
   * Per-engine volume node. The player's 0..1 volume belongs *here*, because
   * `buses.music` carries the fixed MUSIC_BUS_GAIN staging that keeps the
   * soundtrack under the SFX — writing the user volume straight onto the shared
   * bus would silently undo that staging.
   */
  private routeNode: GainNode | null = null;
  private routeTarget: GainNode | null = null;

  constructor(seed = 0x9e3779b9) {
    this.rng = new Rng(seed);
  }

  ensure(): boolean {
    const buses = audioBuses();
    this.buses = buses;
    return buses !== null && buses.ctx.state !== 'closed';
  }

  isEnabled(): boolean {
    return this.enabled;
  }

  getVolume(): number {
    return this.volume;
  }

  currentTheme(): string | null {
    return this.currentId;
  }

  setVolume(v: number): void {
    this.volume = clamp01(v);
    const buses = this.buses;
    if (buses) {
      this.route(buses)?.gain.setValueAtTime(this.volume, buses.ctx.currentTime);
    }
  }

  /** The node every note plays into: volume -> the shared staged music bus. */
  private route(buses: AudioBuses = this.buses!): GainNode | null {
    if (!buses) return null;
    if (this.routeNode === null || this.routeTarget !== buses.music) {
      const node = buses.ctx.createGain();
      node.gain.setValueAtTime(this.volume, buses.ctx.currentTime);
      node.connect(buses.music);
      this.routeNode = node;
      this.routeTarget = buses.music;
    }
    return this.routeNode;
  }

  /** Stop scheduling and release the per-engine node (bus staging is untouched). */
  dispose(): void {
    this.stop();
    this.routeNode?.disconnect();
    this.routeNode = null;
    this.routeTarget = null;
    this.buses = null;
  }

  setEnabled(on: boolean): void {
    this.enabled = on;
    if (typeof window === 'undefined') return;
    if (on && this.timer === null) {
      this.timer = window.setInterval(() => this.scheduler(), 250);
    }
    if (!on && this.timer !== null) {
      window.clearInterval(this.timer);
      this.timer = null;
    }
  }

  setTheme(theme: MusicTheme | null): void {
    if (theme && theme.id === this.currentId) return;
    this.theme = theme;
    this.currentId = theme?.id ?? null;
    this.barIndex = 0;
    this.nextBarAt = 0;
    this.anchored = false;
  }

  stop(): void {
    this.setEnabled(false);
    this.setTheme(null);
  }

  /**
   * Schedule one soundtrack note. Deliberately its own scheduler rather than a
   * shared helper with `AudioEngine.play()`: the cue recorder in ./cues.ts keys
   * on the SFX path, and sharing the helper would put every pad and kick on the
   * SFX cue log and make it meaningless again. This is the separation T-0505
   * exists to guarantee, so keep it.
   */
  private play(note: MusicNote, when: number): void {
    if (!this.ensure() || !this.buses) return;
    const { ctx } = this.buses;
    const music = this.route();
    if (!music) return;
    const t0 = when + note.at;
    const osc = ctx.createOscillator();
    osc.type = note.wave;
    osc.frequency.setValueAtTime(note.freq, t0);
    const gain = ctx.createGain();
    gain.gain.setValueAtTime(0, t0);
    gain.gain.linearRampToValueAtTime(note.gain, t0 + 0.012);
    gain.gain.exponentialRampToValueAtTime(0.0001, t0 + note.dur);
    osc.connect(gain);
    gain.connect(music);
    osc.start(t0);
    osc.stop(t0 + note.dur + 0.03);
  }

  private scheduler(): void {
    if (!this.enabled || !this.theme || !this.ensure()) return;
    const ctx = this.buses!.ctx;
    const now = ctx.currentTime;
    // The theme is usually chosen before any gesture exists, so the bar clock
    // has to be pinned to the context the first time one shows up. Without this
    // the loop would try to "catch up" from zero and dump every elapsed bar at
    // once the moment the player first presses a key.
    if (!this.anchored) {
      this.nextBarAt = now;
      this.anchored = true;
    }
    while (now + 0.05 >= this.nextBarAt) {
      const plan = buildBar(this.theme, this.rng.fork('music-bar-' + this.barIndex), this.barIndex);
      for (const note of plan.notes) {
        this.play(note, this.nextBarAt);
      }
      // Dev-only control log: proves the bed was genuinely playing during a
      // probe window. It is written to a separate bar log, never the SFX cue log.
      recordMusicBar(this.barIndex, this.theme.mood, plan.notes.length, this.nextBarAt);
      this.nextBarAt += plan.duration;
      this.barIndex += 1;
    }
  }
}

export const musicUi = defineFeature({
  id: 'music:ui',
  lane: 'ui',
  setup(ctx): void {
    installAudioUnlock();
    const engine = new MusicEngine(ctx.rng.fork('music').int(1, 0x7fffffff));
    const report = (): void =>
      ctx.bus.emit('music:changed', { enabled: engine.isEnabled(), volume: engine.getVolume() });
    // The persisted prefs are the source of truth: whatever the player last
    // chose in the K panel is what boots. Nothing here force-enables music.
    const prefs = readAudioPrefs();
    engine.setEnabled(prefs.musicEnabled);
    engine.setVolume(prefs.musicVolume);
    report();
    const refresh = (): void => {
      const s = ctx.store.state;
      engine.setTheme(
        resolveMusicTheme({
          hour: s.world.clock.hour,
          weather: s.world.weather,
          seasonIndex: s.world.calendar.seasonIndex,
          mapId: s.player.position.mapId,
          healthPct: s.player.health / s.player.healthMax,
        }),
      );
    };
    refresh();
    const off = ctx.bus.on('state:changed', refresh);
    ctx.bus.on('music:set-enabled', (e: { enabled: boolean }) => {
      engine.setEnabled(Boolean(e?.enabled));
      report();
    });
    ctx.bus.on('music:set-volume', (e: { volume: number }) => {
      engine.setVolume(Number(e?.volume));
      report();
    });
    // The scheduler arms itself via setEnabled(); the first real gesture builds
    // the shared context, at which point the bar clock anchors to "now" and the
    // soundtrack fades in on its own. No event force-enables music.
    moduleCleanup = () => {
      engine.dispose();
      off();
    };
  },
  ui() {
    return { mount(): void {}, dispose(): void {} };
  },
});

let moduleCleanup: (() => void) | null = null;
musicUi.dispose = () => {
  if (moduleCleanup) {
    moduleCleanup();
    moduleCleanup = null;
  }
};
