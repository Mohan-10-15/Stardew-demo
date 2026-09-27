/**
 * voxel.ts — pure, three-free math for the first-person "Minecraft-style"
 * presentation of the tile world (WORKER-1, lane 'world').
 *
 * The sim grid stays 2D (no content changes); this module translates a
 * MapState + legend into a set of block columns (VoxelBox) so a flat plain
 * reads as a raised, blocky island: walkable tiles keep the flat ground slab,
 * houses extrude to 3-tile cubes, tree tiles stack trunk+crown cubes, water
 * pools sit below the surface with an up-standing rim wall on the neighboring
 * floor tiles. Camera pose math (eye height, yaw/pitch from facing, pitch
 * clamp, look vector, head-bob) is also here so it is unit-testable headless.
 */
import type { MapState } from '@game/core/types';
import type { MapLegend } from '@game/core/schemas';

export type Facing = 'up' | 'down' | 'left' | 'right';

export type VoxelKind =
  | 'grass'
  | 'soil'
  | 'path'
  | 'water'
  | 'water-wall'
  | 'tree-trunk'
  | 'tree-crown'
  | 'house';

export interface VoxelBox {
  /** Column in map-grid coordinates (grid origin, not world). */
  col: number;
  row: number;
  /** Cube height in world units, sitting on `baseY`. */
  h: number;
  baseY: number;
  kind: VoxelKind;
  /** Deterministic per-column variance driver (0..1). */
  hash: number;
}

export interface LookPose {
  yaw: number;
  pitch: number;
}

/** Height of the flat walkable ground surface (matches the engine ground slab). */
export const SURFACE_TOP = 0.34;
/** Water pools sit with their surface below the floor so rims are visible. */
export const WATER_TOP = 0;
export const WATER_CUBE_DEPTH = 0.9;
export const WATER_WALL_H = 0.4;
export const HOUSE_HEIGHT = 3;
export const TREE_TRUNK_H = 1.2;
export const TREE_CROWN_H = 1.6;

/**
 * Top face of a height-1 terrain cube: the surface the player, the NPCs and
 * every placed object stand on, and the top of the tile `tileInFront()`
 * targets. buildTerrain centres each block on its tile with the extra lift
 * stacked ABOVE that plane, so the walkable surface is exactly y = 0 — which
 * is what every asset in ./assets is authored against (tree trunks, house
 * foundations, weeds, crops all sit with their base at 0).
 */
export const GROUND_TOP = 0;

/**
 * Eye height above that surface. Deliberately lower than Minecraft's 1.62:
 * interaction reach here is ONE tile, so a taller eye would push the targeted
 * tile's top face outside a 70° vertical FOV at any pitch that still shows the
 * horizon. 0.8 above the surface keeps the whole target tile on screen at the
 * default pitch (see `targetTileNdc` and the first-person camera tests).
 */
export const EYE_ABOVE_GROUND = 0.8;

/** World-space first-person eye height (feet on the surface + EYE_ABOVE_GROUND). */
export const EYE_HEIGHT = GROUND_TOP + EYE_ABOVE_GROUND;

/**
 * Default first-person pitch (negative = looking down). Interaction reach is
 * one tile and the eye sits 0.8 above the surface, so the top face of the
 * targeted tile is 39° below the horizon; a level view would put it off the
 * bottom of the screen entirely. -0.5 rad (-28.6°) lands the tile in the
 * lower-middle of the frame with the horizon still visible near the top.
 */
export const PITCH_DEFAULT = -0.5;
/** Look-down limit (nearly straight down at your own feet). */
export const PITCH_MIN = -1.15;
/** Look-up limit; free look stays available, it just no longer aims the target. */
export const PITCH_MAX = 0.55;
export const LOOK_SPEED = 0.003;
export const BOB_AMPLITUDE = 0.03;
/** Yaw easing rate for keyboard turns (per second, exponential damp). */
export const YAW_LAMBDA = 9;
/** First-person vertical FOV, in degrees. */
export const FOV_DEG = 70;

export function codeAt(map: MapState, col: number, row: number): string | undefined {
  if (col < 0 || row < 0 || col >= map.grid.width || row >= map.grid.height) return undefined;
  return map.grid.tiles[row * map.grid.width + col];
}

export function isWaterCode(map: MapState, legend: MapLegend, col: number, row: number): boolean {
  const code = codeAt(map, col, row);
  if (code === undefined) return false;
  return legend[code]?.water === true;
}

export function hashOf(col: number, row: number): number {
  return hash2(col, row);
}

function hash2(x: number, y: number): number {
  let h = (x * 374761393 + y * 668265263) ^ 0x5bf03635;
  h = Math.imul(h ^ (h >>> 13), 1274126177);
  return ((h ^ (h >>> 16)) >>> 0) / 4294967296;
}

/**
 * Block columns for a whole map. Called on map build (and harmless when
 * hidden); the view instantiates one cube per box.
 */
export function voxelColumns(map: MapState, legend: MapLegend): VoxelBox[] {
  const out: VoxelBox[] = [];
  const { width, height } = map.grid;

  const push = (col: number, row: number, h: number, baseY: number, kind: VoxelKind): void => {
    out.push({ col, row, h, baseY, kind, hash: hash2(col, row) });
  };

  for (let row = 0; row < height; row++) {
    for (let col = 0; col < width; col++) {
      const code = codeAt(map, col, row);
      if (code === undefined) continue;
      if (code === 'h') {
        push(col, row, HOUSE_HEIGHT, 0, 'house');
        continue;
      }
      if (code === 't') {
        push(col, row, TREE_TRUNK_H, 0, 'tree-trunk');
        push(col, row, TREE_CROWN_H, TREE_TRUNK_H, 'tree-crown');
        continue;
      }
      if (legend[code]?.water === true) {
        push(col, row, WATER_CUBE_DEPTH, WATER_TOP - WATER_CUBE_DEPTH, 'water');
        continue;
      }
      // Flat aisle cells that border sunken water raise a visible rim wall so
      // the plain reads as a raised blocky island.
      const rims =
        (isWaterCode(map, legend, col - 1, row) ? 1 : 0) +
        (isWaterCode(map, legend, col + 1, row) ? 1 : 0) +
        (isWaterCode(map, legend, col, row - 1) ? 1 : 0) +
        (isWaterCode(map, legend, col, row + 1) ? 1 : 0);
      if (rims > 0) {
        push(col, row, WATER_WALL_H, SURFACE_TOP - 0.02, 'water-wall');
      }
    }
  }
  return out;
}

export function clampPitch(pitch: number): number {
  return Math.max(PITCH_MIN, Math.min(PITCH_MAX, pitch));
}

/** Yaw so +z is 'down' (south), +x is 'right' (east) — matching the engine. */
export function yawOfFacing(facing: Facing): number {
  switch (facing) {
    case 'down':
      return 0;
    case 'right':
      return Math.PI / 2;
    case 'up':
      return Math.PI;
    case 'left':
      return -Math.PI / 2;
  }
}

/**
 * The cardinal a free yaw points at. This is the mouse-look -> facing rule: the
 * camera may point anywhere, but the 4-way `facing` that decides which tile
 * `tileInFront()` returns always follows the nearest compass direction, so the
 * two can never disagree. Exact diagonals (45° off) resolve to the higher
 * compass (round-half-up), which keeps the mapping total and deterministic.
 */
export function facingOfYaw(yaw: number): Facing {
  const quarter = Math.round(yaw / (Math.PI / 2));
  switch (((quarter % 4) + 4) % 4) {
    case 0:
      return 'down';
    case 1:
      return 'right';
    case 2:
      return 'up';
    default:
      return 'left';
  }
}

/** Wrap an angle into [0, 2PI) so a long session's free look cannot drift. */
export function wrapAngle(angle: number): number {
  const two = Math.PI * 2;
  return ((angle % two) + two) % two;
}

/** Shortest signed turn from `from` to `to`, in radians, within (-PI, PI]. */
export function yawDelta(from: number, to: number): number {
  let delta = (to - from) % (Math.PI * 2);
  if (delta > Math.PI) delta -= Math.PI * 2;
  if (delta <= -Math.PI) delta += Math.PI * 2;
  return delta;
}

/**
 * Exponential yaw damp that always takes the short way round the circle, so a
 * turn from north to west never spins 270° the long way. Same easing shape as
 * THREE.MathUtils.damp (1 - e^(-lambda*dt) of the remaining angle), just
 * wrap-aware, which a plain damp on a raw angle is not.
 */
export function dampYaw(current: number, target: number, lambda: number, dt: number): number {
  if (dt <= 0) return current;
  const step = 1 - Math.exp(-lambda * dt);
  return current + yawDelta(current, target) * step;
}

export interface TargetProjection {
  /** Normalised device coords: -1..1 across the viewport, 0 is dead centre. */
  x: number;
  y: number;
  /** True when the point is inside the frustum. */
  onScreen: boolean;
}

/**
 * Where the centre of the targeted tile's TOP face lands on screen, for an eye
 * at `eyeHeight` with the given pose. `tileInFront` is one tile away along the
 * facing and its top face is `GROUND_TOP`, so the offset from the eye is
 * (forward 1, down eyeHeight - GROUND_TOP).
 *
 * This is the invariant the first-person camera has to satisfy: whatever the
 * player faces, the tile they act on must be on screen, near the crosshair.
 * Unit-tested headlessly (the browser probe re-measures it for real).
 */
export function targetTileNdc(
  pose: LookPose,
  facing: Facing,
  eyeHeight: number,
  fovDeg: number = FOV_DEG,
  aspect: number = 16 / 9,
): TargetProjection {
  const yaw = yawOfFacing(facing);
  const forward = { x: Math.sin(yaw), y: 0, z: Math.cos(yaw) };
  const drop = eyeHeight - GROUND_TOP;
  // World-space offset from the eye to the tile's top-face centre.
  const ox = forward.x;
  const oy = -drop;
  const oz = forward.z;

  // Camera basis, matching THREE.Object3D.lookAt with +y up: -Z is the view
  // direction, +X is right, +Y is up.
  const dir = lookVector(pose);
  const zx = -dir.x;
  const zy = -dir.y;
  const zz = -dir.z;
  // xAxis = normalize(cross(worldUp, zAxis)) with worldUp = (0, 1, 0).
  const xLen = Math.hypot(zz, -zx);
  if (xLen < 1e-6) return { x: 0, y: 0, onScreen: false };
  const xx = zz / xLen;
  const xy = 0;
  const xz = -zx / xLen;
  // yAxis = cross(zAxis, xAxis).
  const yx = zy * xz - zz * xy;
  const yy = zz * xx - zx * xz;
  const yz = zx * xy - zy * xx;

  const vx = ox * xx + oy * xy + oz * xz;
  const vy = ox * yx + oy * yy + oz * yz;
  const depth = -(ox * zx + oy * zy + oz * zz);
  if (depth <= 1e-6) return { x: 0, y: 0, onScreen: false };
  const halfV = Math.tan((fovDeg / 2) * (Math.PI / 180));
  const x = vx / (depth * halfV * aspect);
  const y = vy / (depth * halfV);
  return { x, y, onScreen: Math.abs(x) <= 1 && Math.abs(y) <= 1 };
}

/** Unit look vector: pitch up is positive, azimuth rotates around +y. */
export function lookVector(pose: LookPose): { x: number; y: number; z: number } {
  const c = Math.cos(pose.pitch);
  return {
    x: Math.sin(pose.yaw) * c,
    y: Math.sin(pose.pitch),
    z: Math.cos(pose.yaw) * c,
  };
}

/** Vertical bob of the eye while walking; `phase` grows with time. */
export function headBob(phase: number): number {
  return Math.abs(Math.sin(phase)) * BOB_AMPLITUDE;
}