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

/** First-person eye height above the walkable surface. */
export const EYE_HEIGHT = 1.3;
export const PITCH_MIN = -1.25;
export const PITCH_MAX = 1.25;
export const LOOK_SPEED = 0.003;
export const BOB_AMPLITUDE = 0.03;

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