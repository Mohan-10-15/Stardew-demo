/**
 * blocks.ts — the voxel block registry + terrain builder (WORKER-1, lane
 * 'world'). Every world block is a full 1x1x1 cube. The registry maps a
 * BlockKind to a shared geometry + one or more flat-shaded, pixel-textured
 * materials (a material array gives a grass block its green top and dirt sides
 * — six face groups, exactly like a Minecraft grass block).
 *
 * Terrain is built from the map grid as real cube blocks via one InstancedMesh
 * per block kind, so a 32x24 map stays cheap. Height variation is VISUAL ONLY;
 * the sim stays tile-based and walkability (isWalkable) is untouched.
 */
import * as THREE from 'three';
import type { MapState } from '../../../core/types';
import type { MapLegend } from '../../../core/schemas';
import { blockTexture, disposeBlockTextures } from './textures';

export const BLOCK_SIZE = 1;

/** Face group order for a BoxGeometry material array. */
export const FACE_ORDER = ['px', 'nx', 'py', 'ny', 'pz', 'nz'] as const;
export type FaceName = (typeof FACE_ORDER)[number];

export type BlockKind =
  | 'grass'
  | 'dirt'
  | 'farmland'
  | 'stone'
  | 'cobblestone'
  | 'sand'
  | 'path'
  | 'water'
  | 'log'
  | 'planks'
  | 'leaves'
  | 'brick'
  | 'glass'
  | 'ore_coal'
  | 'ore_iron'
  | 'ore_gold'
  | 'ore_copper';

export interface BlockDef {
  kind: BlockKind;
  /** Shared unit-cube geometry. */
  geometry: THREE.BoxGeometry;
  /** Single material, or a six-face material array (grass uses the array). */
  materials: THREE.Material[];
  /** True when `materials` is a per-face array (6 groups). */
  perFace: boolean;
  /** Water is translucent and does not cast/receive shadows. */
  translucent: boolean;
  /** Instanced meshes for this block should not receive shadows. */
  noShadow: boolean;
}

let cachedGeo: THREE.BoxGeometry | null = null;

/** The one shared unit cube every block uses. */
export function blockGeometry(): THREE.BoxGeometry {
  if (!cachedGeo) cachedGeo = new THREE.BoxGeometry(BLOCK_SIZE, BLOCK_SIZE, BLOCK_SIZE);
  return cachedGeo;
}

function texMat(name: string, key: string, opts: Partial<THREE.MeshLambertMaterialParameters> = {}): THREE.MeshLambertMaterial {
  return new THREE.MeshLambertMaterial({
    name,
    map: blockTexture(key),
    flatShading: true,
    ...opts,
  });
}

function blockDef(
  kind: BlockKind,
  faceKeys: readonly string[],
  opts: { translucent?: boolean; noShadow?: boolean } = {},
): BlockDef {
  const geometry = blockGeometry();
  if (faceKeys.length === 1) {
    return {
      kind,
      geometry,
      materials: [texMat(kind, faceKeys[0]!, opts.translucent ? { transparent: true, opacity: 0.82 } : {})],
      perFace: false,
      translucent: opts.translucent ?? false,
      noShadow: opts.noShadow ?? opts.translucent ?? false,
    };
  }
  const materials = FACE_ORDER.map((face, i) => texMat(`${kind}:${face}`, faceKeys[i] ?? faceKeys[0]!));
  return {
    kind,
    geometry,
    materials,
    perFace: true,
    translucent: opts.translucent ?? false,
    noShadow: opts.noShadow ?? opts.translucent ?? false,
  };
}

let registry: Map<BlockKind, BlockDef> | null = null;

/** Build (once) and cache the full block registry. */
export function blockRegistry(): Map<BlockKind, BlockDef> {
  if (registry) return registry;
  const defs: BlockDef[] = [
    // Grass: green top, dirt sides, dirt bottom.
    blockDef('grass', ['grass_side', 'grass_side', 'grass_top', 'dirt', 'grass_side', 'grass_side']),
    blockDef('dirt', ['dirt']),
    blockDef('farmland', ['farmland']),
    blockDef('stone', ['stone']),
    blockDef('cobblestone', ['cobblestone']),
    blockDef('sand', ['sand']),
    blockDef('path', ['path']),
    blockDef('water', ['water'], { translucent: true }),
    // Log: bark sides, ring top/bottom.
    blockDef('log', ['log_side', 'log_side', 'log_top', 'log_top', 'log_side', 'log_side']),
    blockDef('planks', ['planks']),
    blockDef('leaves', ['leaves']),
    blockDef('brick', ['brick']),
    blockDef('glass', ['glass'], { translucent: true }),
    blockDef('ore_coal', ['ore_coal']),
    blockDef('ore_iron', ['ore_iron']),
    blockDef('ore_gold', ['ore_gold']),
    blockDef('ore_copper', ['ore_copper']),
  ];
  registry = new Map(defs.map((d) => [d.kind, d]));
  return registry;
}

/** Resolve a BlockKind to its definition. Throws for an unknown kind. */
export function getBlock(kind: BlockKind): BlockDef {
  const def = blockRegistry().get(kind);
  if (!def) throw new Error(`[engine:view] unknown block kind: ${kind}`);
  return def;
}

/** Every block kind in the registry. */
export function allBlockKinds(): BlockKind[] {
  return [...blockRegistry().keys()];
}

/** Grass top face is distinct from its side faces (sanity helper). */
export function grassTopIsDistinct(): boolean {
  const def = getBlock('grass');
  // FACE_ORDER top = index 2 (py); sides are 0/1/4/5 (px/nx/pz/nz).
  const top = def.materials[2] as THREE.MeshLambertMaterial | undefined;
  const side = def.materials[0] as THREE.MeshLambertMaterial | undefined;
  const sideEast = def.materials[4] as THREE.MeshLambertMaterial | undefined;
  if (!top || !side || !sideEast) return false;
  // The top must NOT wear the grass_side texture, and every side must.
  const topMap = top.map?.name ?? '';
  const sideMap = side.map?.name ?? '';
  const sideEastMap = sideEast.map?.name ?? '';
  return topMap === 'grass_top' && sideMap === 'grass_side' && sideEastMap === 'grass_side';
}

// --- Legend -> block kind mapping ----------------------------------------

/** Map a legend tile code to the block kind the ground should render as. */
export function blockKindForCode(code: string, legend: MapLegend): BlockKind {
  if (code === 't') return 'log'; // tree tiles render a log column below (see assets)
  if (legend[code]?.water === true) return 'water';
  if (code === 's') return 'farmland';
  if (code === 'p') return 'path';
  return 'grass';
}

// --- Terrain building -----------------------------------------------------

export interface TerrainBlock {
  kind: BlockKind;
  col: number;
  row: number;
  /** Visual-only stack height (whole blocks). */
  height: number;
  /** Deterministic per-cell hash for tonal variance. */
  hash: number;
}

/** Deterministic per-cell hash (mirrors the assets.ts hash2 contract). */
function cellHash(x: number, z: number): number {
  let h = (x * 374761393 + z * 668265263) ^ 0x5bf03635;
  h = Math.imul(h ^ (h >>> 13), 1274126177);
  return ((h ^ (h >>> 16)) >>> 0) / 4294967296;
}

/**
 * Turn a map grid into the list of ground blocks to render. Houses ('h') are
 * skipped (drawn as their own house asset). Walkability is NOT consulted — this
 * is presentation only.
 *
 * `tilled` carries the tiles the player has hoed: those render as farmland, the
 * same block kind the authored `s` tiles use. That is deliberate — the tilled
 * look is then literally one instanced block kind for both, so authored soil and
 * player-tilled soil cannot drift apart.
 */
export function terrainBlocks(
  map: MapState,
  legend: MapLegend,
  tilled?: ReadonlySet<string>,
): TerrainBlock[] {
  const out: TerrainBlock[] = [];
  const { width, height } = map.grid;
  for (let row = 0; row < height; row++) {
    for (let col = 0; col < width; col++) {
      const code = map.grid.tiles[row * width + col];
      if (code === undefined || code === 'h') continue;
      const tilledHere = tilled?.has(`${col},${row}`) === true;
      const kind: BlockKind = tilledHere ? 'farmland' : blockKindForCode(code, legend);
      out.push({ kind, col, row, height: 1, hash: cellHash(col, row) });
    }
  }
  return out;
}

export interface BuiltTerrain {
  group: THREE.Group;
  /** Total instance count across every instanced mesh. */
  instanceCount: number;
  /** Instanced mesh per block kind that actually got instances. */
  meshes: Map<BlockKind, THREE.InstancedMesh>;
}

/**
 * Build an InstancedMesh per block kind from terrain blocks and add them to a
 * fresh group. `worldPos` maps a (col,row) to a world Vector3 (supplied by the
 * engine so the grid origin matches the rest of the scene).
 */
export function buildTerrain(
  blocks: TerrainBlock[],
  worldPos: (col: number, row: number) => THREE.Vector3,
): BuiltTerrain {
  const group = new THREE.Group();
  group.name = 'terrain';
  const byKind = new Map<BlockKind, TerrainBlock[]>();
  for (const block of blocks) {
    const list = byKind.get(block.kind);
    if (list) list.push(block);
    else byKind.set(block.kind, [block]);
  }

  const meshes = new Map<BlockKind, THREE.InstancedMesh>();
  let instanceCount = 0;
  const dummy = new THREE.Object3D();

  for (const [kind, list] of byKind) {
    const def = getBlock(kind);
    const material = def.perFace ? def.materials : def.materials[0]!;
    const mesh = new THREE.InstancedMesh(def.geometry, material as THREE.Material, list.length);
    mesh.name = `terrain:${kind}`;
    for (let i = 0; i < list.length; i++) {
      const b = list[i]!;
      const p = worldPos(b.col, b.row);
      // The walkable surface is exactly y = 0 (GROUND_TOP), which is what the
      // player, the NPCs, placed assets and the highlight are authored against:
      // a height-1 block is centred half a block BELOW its tile, and any extra
      // stacked block is lifted above the surface. Blocks used to sit half a
      // block high, which buried every placeable and put the interaction
      // target above the first-person eye.
      dummy.position.set(p.x, b.height - 1.5, p.z);
      dummy.updateMatrix();
      mesh.setMatrixAt(i, dummy.matrix);
    }
    mesh.instanceMatrix.needsUpdate = true;
    // Geometry + materials are owned by the cached block registry; a removal
    // pass must detach but never dispose them (see disposeTerrain / EngineView).
    mesh.userData.sharedBlock = true;
    mesh.castShadow = !def.noShadow;
    mesh.receiveShadow = !def.noShadow;
    group.add(mesh);
    meshes.set(kind, mesh);
    instanceCount += list.length;
  }

  return { group, instanceCount, meshes };
}

/** Dispose a built terrain group's per-mesh resources (geometry is shared). */
export function disposeTerrain(terrain: BuiltTerrain | null): void {
  if (!terrain) return;
  for (const mesh of terrain.meshes.values()) {
    // InstancedMesh frees the instanceMatrix buffer; geometry is shared, so we
    // only detach it here.
    mesh.dispose();
  }
  terrain.group.clear();
}

/** Release the cached block geometry, registry materials and textures. */
export function disposeBlockRegistry(): void {
  if (registry) {
    for (const def of registry.values()) {
      for (const mat of def.materials) mat.dispose();
    }
    registry = null;
  }
  disposeBlockTextures();
  if (cachedGeo) {
    cachedGeo.dispose();
    cachedGeo = null;
  }
}
