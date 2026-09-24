/**
 * Core shared types for Ember Hollow.
 *
 * The simulation is tile-based and deterministic. Rendering (Three.js view
 * modules) only ever reads the state produced here. All randomness inside the
 * sim must flow through Rng (src/core/rng.ts) seeded from state.rngSeed.
 */

export type SeasonIndex = 0 | 1 | 2 | 3;
export type Weather = 'sun' | 'rain' | 'storm' | 'snow' | 'wind';
export type Facing = 'up' | 'down' | 'left' | 'right';
export type SkillId = 'farming' | 'foraging' | 'mining' | 'fishing' | 'combat';
export type Direction2D = 'N' | 'S' | 'E' | 'W';

export const SEASON_NAMES = ['Spring', 'Summer', 'Fall', 'Winter'] as const;
export const WEATHERS: readonly Weather[] = ['sun', 'rain', 'storm', 'snow', 'wind'];
export const SKILL_IDS: readonly SkillId[] = ['farming', 'foraging', 'mining', 'fishing', 'combat'];

/** One simulation tick advances this many in-game minutes (SV-style 10-min ticks). */
export const TICK_MINUTES = 10;
/** The in-game hour the day begins when waking / passing out. */
export const DAY_START_HOUR = 6;
/** Days per season. */
export const DAYS_PER_SEASON = 28;
/** Seasons per year. */
export const SEASONS_PER_YEAR = 4;
/** The in-game hour at which the farmer is overcome and collapses (2:00 AM). */
export const PASS_OUT_HOUR = 2;
/** Hour of the day as a float used by NPC schedules / event windows. */
export const MAX_SAVE_SLOTS = 3;

export type QualityTier = 0 | 1 | 2;

export interface TilePos {
  x: number;
  y: number;
}

export interface WorldPos {
  mapId: string;
  x: number;
  y: number;
}

export interface TimeCalendar {
  year: number;
  seasonIndex: SeasonIndex;
  dayOfMonth: number;
}

export interface Clock {
  /** 0..23 in-game hour. */
  hour: number;
  /** 0..50, multiples of TICK_MINUTES. */
  minute: number;
}

export interface WorldState {
  calendar: TimeCalendar;
  clock: Clock;
  weather: Weather;
  /** Weather for the following days, index 0 = tomorrow. */
  forecast: Weather[];
  /** Absolute in-game day counter: day 1 of year 1 = 1. */
  dayCount: number;
  /** True when the farmer collapsed at 2:00 AM and was dragged home. */
  passedOut: boolean;
  /** Uptime counter in real seconds (not persisted logic; diagnostics). */
  playSeconds: number;
}

export interface SkillState {
  level: number;
  xp: number;
}

export interface ItemStack {
  id: string;
  qty: number;
  quality: QualityTier;
}

export interface InventoryState {
  /** Fixed-size bag; null = empty slot. */
  slots: (ItemStack | null)[];
  capacity: number;
  /** Currently selected hotbar slot. */
  selected: number;
  /** Preview of the tile the player is pointing at (view-only field). */
  cursor: TilePos;
}

export interface FarmState {
  /** id of the player-owned map. */
  mapId: string;
  name: string;
}

export interface PlayerState {
  name: string;
  farmName: string;
  position: WorldPos;
  facing: Facing;
  energy: number;
  energyMax: number;
  health: number;
  healthMax: number;
  money: number;
  skills: Record<SkillId, SkillState>;
  inventory: InventoryState;
  /** earned experience for the current game; drives end-of-day summary. */
  stats: Record<string, number>;
}

export interface MapGridState {
  /** Row-major tile codes, length = width * height. */
  tiles: string[];
  width: number;
  height: number;
}

export interface PlacedObject {
  id: string;
  /** WorldPos for placed items on grid maps. */
  x: number;
  y: number;
  /** Optional sub-state stored by the owning feature/system. */
  data?: Record<string, unknown>;
}

export interface NpcPresence {
  npcId: string;
  x: number;
  y: number;
  facing: Facing;
}

export interface MapState {
  id: string;
  grid: MapGridState;
  /** Placed persistent objects keyed "x,y". */
  placed: Record<string, PlacedObject>;
  /** Current positions of NPCs on this map. */
  npcs: Record<string, NpcPresence>;
  /** Frozen time-crossers (e.g. tree stumps) flag. */
  version: number;
}

export interface RelationshipState {
  npcId: string;
  hearts: number;
  giftCountToday: number;
  talkedToday: boolean;
  married: boolean;
  gaveBouquet: boolean;
}

export interface QuestState {
  active: string[];
  completed: string[];
}

export interface ProgressionState {
  /** Unlocked area/feature flags. */
  flags: string[];
  /** Collection completion counts by collection id. */
  collections: Record<string, number>;
  /** Community hub restoration progress (0..1 shares of the Heartstone). */
  heartstoneProgress: number;
  /** Flags specific to the main story line. */
  story: string[];
}

/** Feature modules may hang typed-but-schema-validated state here. */
export interface Extensions {
  [featureId: string]: Record<string, unknown>;
}

export interface GameState {
  /** Saves schema version this state conforms to. */
  version: number;
  meta: {
    saveName: string;
    createdAt: number;
    updatedAt: number;
    playCount: number;
  };
  rngSeed: number;
  world: WorldState;
  player: PlayerState;
  farm: FarmState;
  maps: Record<string, MapState>;
  relationships: Record<string, RelationshipState>;
  quests: QuestState;
  progression: ProgressionState;
  extensions: Extensions;
}

/** Global game configuration / balance tunables (content-validated). */
export interface Config {
  energyPerStar: number;
  baseTileWalkCost: number;
  toolUpgradeCosts: number[];
  shippingBinItemLimit: number;
}

export const DEFAULT_CONFIG: Config = {
  energyPerStar: 16,
  baseTileWalkCost: 1,
  toolUpgradeCosts: [0, 1000, 2500, 5000, 10000],
  shippingBinItemLimit: 36,
};

/** Discriminated actions that reducers consume. All action payloads must be JSON-safe. */
export interface SimAction<T extends string = string, P = unknown> {
  type: T;
  payload: P;
}