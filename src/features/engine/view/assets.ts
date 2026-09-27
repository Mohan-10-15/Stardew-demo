/**
 * assets.ts — procedural Minecraft-style asset builders (WORKER-1). Every mesh a
 * map legend code or placed-object id resolves to goes through here behind an
 * asset-ID layer: swap or upgrade any builder without touching the renderer.
 *
 * Everything is CUBIC: 1x1x1 voxel blocks, flat-shaded, wearing the procedural
 * 16x16 pixel textures from ./textures. No smooth primitives, no external
 * files. Trees are log columns + cube canopies, rocks are 2-4 rotated stone
 * cubes, crops are small cubes on a stem, houses are plank walls with a
 * stair-stepped block roof, a glass window and a stone chimney.
 */
import * as THREE from 'three';
import { blockTexture } from './textures';
import { getBlock, type BlockKind } from './blocks';

export const GRID_CELL = 1;

export interface HouseSpan {
  minCol: number;
  maxCol: number;
  minRow: number;
  maxRow: number;
  hash: number;
}

export function hash2(x: number, z: number): number {
  let h = (x * 374761393 + z * 668265263) ^ 0x5bf03635;
  h = Math.imul(h ^ (h >>> 13), 1274126177);
  return ((h ^ (h >>> 16)) >>> 0) / 4294967296;
}

// --- Material helpers -----------------------------------------------------

/** A shared, flat-shaded textured block material for a texture key. */
function blockMaterial(texKey: string, name: string): THREE.MeshLambertMaterial {
  return new THREE.MeshLambertMaterial({ color: 0xffffff, map: blockTexture(texKey), name, flatShading: true });
}

/** Flat-shaded, untextured colour material (for accents / figures). */
function flatMaterial(color: number, name: string): THREE.MeshLambertMaterial {
  return new THREE.MeshLambertMaterial({ color, name, flatShading: true });
}

function shadowed(mesh: THREE.Object3D): void {
  mesh.castShadow = true;
  mesh.receiveShadow = true;
}

/** One 1x1x1 voxel cube mesh. `kind` selects the registry material. */
export function blockMesh(kind: BlockKind): THREE.Mesh {
  const def = getBlock(kind);
  const material = def.perFace ? def.materials : def.materials[0]!;
  const mesh = new THREE.Mesh(def.geometry, material as THREE.Material);
  mesh.castShadow = !def.noShadow;
  mesh.receiveShadow = !def.noShadow;
  // Geometry + materials are owned by the cached block registry; a removal
  // pass must detach but never dispose them (see disposeGroup in EngineView).
  mesh.userData.sharedBlock = true;
  return mesh;
}

/** A textured voxel cube with a given size (defaults to a full block). */
function cubeMesh(
  texKey: string,
  name: string,
  size: { x: number; y: number; z: number },
  position: { x: number; y: number; z: number },
  material?: THREE.Material,
): THREE.Mesh {
  const geo = new THREE.BoxGeometry(size.x, size.y, size.z);
  const mesh = new THREE.Mesh(geo, material ?? blockMaterial(texKey, name));
  mesh.position.set(position.x, position.y, position.z);
  shadowed(mesh);
  return mesh;
}

// --- Ground ---------------------------------------------------------------

const slabGeo = new THREE.BoxGeometry(1, 0.34, 1);
slabGeo.translate(0, -0.17, 0);

export function groundGeometry(): THREE.BufferGeometry {
  return slabGeo;
}

export interface GroundMaterials {
  grass: THREE.MeshLambertMaterial;
  soil: THREE.MeshLambertMaterial;
  path: THREE.MeshLambertMaterial;
  water: THREE.MeshLambertMaterial;
}

export function groundMaterials(): GroundMaterials {
  return {
    grass: blockMaterial('grass_top', 'grass-base'),
    soil: blockMaterial('farmland', 'soil-base'),
    path: blockMaterial('path', 'path-base'),
    water: new THREE.MeshLambertMaterial({
      color: 0xffffff,
      map: blockTexture('water'),
      name: 'water-base',
      flatShading: true,
      transparent: true,
      opacity: 0.82,
    }),
  };
}

export function grassInstanceColor(x: number, z: number): THREE.Color {
  const f = 0.9 + 0.22 * hash2(x, z);
  return new THREE.Color(0xffffff).multiplyScalar(f);
}

// --- Tilled soil ----------------------------------------------------------
//
// Tilled ground is NOT drawn here. Authored `s` tiles and player-hoed tiles are
// both farmland blocks in the terrain InstancedMesh (see terrainBlocks), which
// is the only place tilled soil is rendered. One visual for one thing.

// --- Trees ----------------------------------------------------------------

/**
 * An oak: a 1x1 log trunk column with a leaf canopy built from cubes —
 * a 5x5x2 layer, a 3x3x2 layer above it, plus a top cap.
 */
export function buildTreeAsset(x: number, z: number): THREE.Object3D {
  const g = new THREE.Group();
  const h = hash2(x, z);

  // Trunk: 4 stacked log blocks.
  const trunkHeight = 4 + (h > 0.6 ? 1 : 0);
  for (let i = 0; i < trunkHeight; i++) {
    const block = blockMesh('log');
    block.position.y = i + 0.5;
    g.add(block);
  }

  const baseY = trunkHeight;
  // Canopy layer 1 + 2: 5x5 slab of leaves (corners randomly trimmed).
  for (let dy = 0; dy < 2; dy++) {
    for (let dx = -2; dx <= 2; dx++) {
      for (let dz = -2; dz <= 2; dz++) {
        const corner = Math.abs(dx) === 2 && Math.abs(dz) === 2;
        if (corner && hash2(x * 31 + dx, z * 31 + dz + dy * 7) < 0.5) continue;
        if (Math.abs(dx) === 2 && Math.abs(dz) === 1 && hash2(dx * 13 + dy, dz * 17) < 0.25) continue;
        const leaf = blockMesh('leaves');
        leaf.position.set(dx, baseY + dy + 0.5, dz);
        g.add(leaf);
      }
    }
  }
  // Canopy layer 3 + 4: 3x3 slab on top.
  for (let dy = 2; dy < 4; dy++) {
    for (let dx = -1; dx <= 1; dx++) {
      for (let dz = -1; dz <= 1; dz++) {
        if (Math.abs(dx) === 1 && Math.abs(dz) === 1 && hash2(dx * 19 + dy, dz * 23) < 0.4) continue;
        const leaf = blockMesh('leaves');
        leaf.position.set(dx, baseY + dy + 0.5, dz);
        g.add(leaf);
      }
    }
  }
  // Top cap.
  const cap = blockMesh('leaves');
  cap.position.set(0, baseY + 4.5, 0);
  g.add(cap);

  return g;
}

// --- Houses ---------------------------------------------------------------

/**
 * A plank house: plank walls, a stair-stepped block roof (not a cone), a glass
 * window and a stone chimney. Built from whole/half blocks on the tile span.
 */
export function buildHouseAsset(span: HouseSpan): THREE.Object3D {
  const g = new THREE.Group();
  const cols = span.maxCol - span.minCol + 1;
  const rows = span.maxRow - span.minRow + 1;
  const w = cols * GRID_CELL;
  const d = rows * GRID_CELL;

  const wallHeight = 3;

  // Stone foundation course.
  g.add(
    cubeMesh('cobblestone', 'house-base', { x: w + 0.12, y: 0.5, z: d + 0.12 }, { x: 0, y: 0.25, z: 0 }),
  );

  // Plank walls, built as a ring of half-height courses so it stays cheap.
  const courseH = wallHeight / 2;
  const courseY = [0.5 + courseH / 2, 0.5 + courseH * 1.5];
  for (const y of courseY) {
    // long walls (front/back)
    g.add(
      cubeMesh('planks', 'house-walls', { x: w, y: courseH, z: 0.2 }, { x: 0, y, z: d / 2 - 0.1 }),
      cubeMesh('planks', 'house-walls', { x: w, y: courseH, z: 0.2 }, { x: 0, y, z: -d / 2 + 0.1 }),
    );
    // short walls (west/east)
    g.add(
      cubeMesh('planks', 'house-walls', { x: 0.2, y: courseH, z: d - 0.4 }, { x: w / 2 - 0.1, y, z: 0 }),
      cubeMesh('planks', 'house-walls', { x: 0.2, y: courseH, z: d - 0.4 }, { x: -w / 2 + 0.1, y, z: 0 }),
    );
  }

  // Stair-stepped block roof: shrinking slabs of brick/roof blocks.
  const roofSteps = 3;
  for (let i = 0; i < roofSteps; i++) {
    const shrink = i * 0.3;
    const y = 0.5 + wallHeight + 0.15 + i * 0.3;
    g.add(
      cubeMesh(
        'brick',
        'house-roof',
        { x: Math.max(0.3, w - shrink * 2), y: 0.3, z: Math.max(0.3, d - shrink * 2) },
        { x: 0, y, z: 0 },
      ),
    );
  }

  // Glass window on the east wall.
  g.add(
    cubeMesh('glass', 'house-window', { x: 0.08, y: 0.5, z: 0.5 }, { x: w / 2 - 0.02, y: 1.1, z: -d / 5 }),
    cubeMesh('glass', 'house-window', { x: 0.08, y: 0.5, z: 0.5 }, { x: w / 2 - 0.02, y: 1.1, z: d / 5 }),
  );

  // Stone chimney.
  g.add(
    cubeMesh('stone', 'house-chimney', { x: 0.3, y: 1.0, z: 0.3 }, { x: w / 4, y: 0.5 + wallHeight + 0.6, z: d / 4 }),
  );

  // Door (a darker plank block on the south wall).
  g.add(
    cubeMesh('log_side', 'house-door', { x: 0.5, y: 0.9, z: 0.08 }, { x: 0, y: 0.95, z: d / 2 - 0.02 }),
  );

  return g;
}

// --- Weeds / branches / rocks / stumps -----------------------------------

/** Weeds: a few small green cubes sprouting from the tile. */
export function buildWeedAsset(hash: number): THREE.Object3D {
  const g = new THREE.Group();
  const tufts = 3 + (hash > 0.5 ? 1 : 0);
  for (let i = 0; i < tufts; i++) {
    const t = new THREE.Mesh(
      new THREE.BoxGeometry(0.14, 0.22, 0.14),
      blockMaterial('leaves', 'weed'),
    );
    const a = hash * 6.283 + i * 2.09;
    t.position.set(Math.cos(a) * 0.16, 0.11, Math.sin(a) * 0.16);
    shadowed(t);
    g.add(t);
  }
  return g;
}

/** A fallen branch: two stacked/rotated log cubes. */
export function buildBranchAsset(hash: number): THREE.Object3D {
  const g = new THREE.Group();
  const log = new THREE.Mesh(new THREE.BoxGeometry(0.24, 0.24, 0.9), blockMaterial('log_side', 'branch'));
  log.position.y = 0.12;
  log.rotation.y = hash * Math.PI; // 90-degree steps are baked by the caller hash
  shadowed(log);
  g.add(log);

  const twig = new THREE.Mesh(new THREE.BoxGeometry(0.16, 0.16, 0.4), blockMaterial('log_side', 'branch-twig'));
  twig.position.set(0.2, 0.22, 0.1);
  twig.rotation.y = hash * Math.PI;
  shadowed(twig);
  g.add(twig);
  return g;
}

/**
 * A rock: a cluster of 2-4 stone/cobble cubes at slightly different sizes,
 * rotated in 90-degree steps only (the Minecraft rule — no arbitrary angles).
 */
export function buildRockAsset(hash: number): THREE.Object3D {
  const g = new THREE.Group();
  const count = 2 + Math.floor(hash * 3); // 2..4
  const quarter = Math.floor(hash * 4) * (Math.PI / 2);
  for (let i = 0; i < count; i++) {
    const size = 0.28 + ((hash * (i + 3) * 7) % 0.3);
    const rock = new THREE.Mesh(
      new THREE.BoxGeometry(size, size * 0.85, size),
      blockMaterial(i % 2 === 0 ? 'stone' : 'cobblestone', i % 2 === 0 ? 'rock' : 'rock-chip'),
    );
    const a = quarter + (i * Math.PI) / 2;
    const rad = i === 0 ? 0 : 0.16 + (i % 2) * 0.1;
    rock.position.set(Math.cos(a) * rad, size / 2, Math.sin(a) * rad);
    rock.rotation.y = quarter + i * (Math.PI / 2);
    shadowed(rock);
    g.add(rock);
  }
  return g;
}

/** A stump: a short log column with a ring top. */
export function buildStumpAsset(): THREE.Object3D {
  const g = new THREE.Group();
  const stump = blockMesh('log');
  stump.position.y = 0.5;
  stump.scale.set(1, 1, 1);
  g.add(stump);
  return g;
}

/** A shipping bin: plank cubes with a dark slot and log posts. */
export function buildShippingBinAsset(): THREE.Object3D {
  const g = new THREE.Group();
  // Body of plank cubes.
  g.add(cubeMesh('planks', 'bin-body', { x: 0.9, y: 0.5, z: 0.6 }, { x: 0, y: 0.3, z: 0 }));
  // Lid slab.
  g.add(cubeMesh('planks', 'bin-lid', { x: 1.0, y: 0.14, z: 0.7 }, { x: 0, y: 0.62, z: 0 }));
  // Dark slot on the front.
  g.add(cubeMesh('dirt', 'bin-slot', { x: 0.5, y: 0.1, z: 0.06 }, { x: 0, y: 0.56, z: 0.31 }));
  // Log posts.
  g.add(
    cubeMesh('log', 'bin-post', { x: 0.1, y: 0.34, z: 0.1 }, { x: -0.4, y: 0.17, z: -0.22 }),
    cubeMesh('log', 'bin-post', { x: 0.1, y: 0.34, z: 0.1 }, { x: 0.4, y: 0.17, z: -0.22 }),
  );
  return g;
}

// --- Crops ----------------------------------------------------------------

/** A per-crop leaf/stem voxel colour, derived from the crop id token. */
function cropTokens(cropIdOrStage: string): { leaf: string; stem: string } {
  const id = cropIdOrStage.replace(/^crop:/, '');
  return { leaf: `${id}_leaf`, stem: `${id}_stem` };
}

/**
 * A crop: small cubes on a stem, stage-driven height, still readable at a
 * glance. Stages 0..n grow the stem and add fruit/leaf cubes at the top.
 */
export function buildCropAsset(stage: number, hash: number, cropId = 'default'): THREE.Object3D {
  const g = new THREE.Group();
  const { leaf: leafKey, stem: stemKey } = cropTokens(cropId);
  const s = Math.max(0, stage);
  const height = 0.12 + 0.16 * s;

  // Stem: a column of small stem-coloured cubes.
  const stemBlocks = 1 + Math.min(3, s);
  for (let i = 0; i < stemBlocks; i++) {
    const b = cubeMesh(stemKey, 'crop-stem', { x: 0.1, y: 0.16, z: 0.1 }, { x: 0, y: 0.08 + i * 0.16, z: 0 });
    g.add(b);
  }

  // Leaf pair near the middle.
  const leafY = Math.min(height, 0.08 + stemBlocks * 0.16);
  g.add(
    cubeMesh(leafKey, 'crop-leaf', { x: 0.26, y: 0.08, z: 0.1 }, { x: -0.08, y: leafY, z: 0 }),
    cubeMesh(leafKey, 'crop-leaf', { x: 0.26, y: 0.08, z: 0.1 }, { x: 0.08, y: leafY, z: 0 }),
  );

  // Fruit/flower cube once the crop is mature (stage 3+).
  if (s >= 3) {
    g.add(cubeMesh(leafKey, 'crop-fruit', { x: 0.16, y: 0.16, z: 0.16 }, { x: 0, y: height + 0.06, z: 0 }));
  }
  // Nudge position deterministically so a field of crops is not uniform.
  g.position.x += (hash - 0.5) * 0.12;
  g.position.z += (hash * 2 % 1 - 0.5) * 0.12;
  return g;
}

// --- Misc / placed dispatch ----------------------------------------------

/** A generic supply crate of plank cubes. */
export function buildMiscAsset(): THREE.Object3D {
  const g = new THREE.Group();
  g.add(cubeMesh('planks', 'misc-crate', { x: 0.5, y: 0.5, z: 0.5 }, { x: 0, y: 0.25, z: 0 }));
  g.add(cubeMesh('log', 'misc-band', { x: 0.54, y: 0.12, z: 0.54 }, { x: 0, y: 0.32, z: 0 }));
  return g;
}

export function buildPlacedAsset(
  assetId: string,
  stage: number,
  hash: number,
  cropId = 'default',
): THREE.Object3D {
  // 'tilled' is intentionally absent: tilled soil is drawn by the terrain mesh
  // so authored and player-hoed tiles share one look, and callers skip it.
  if (assetId.startsWith('crop:')) return buildCropAsset(stage, hash, cropId || assetId.slice(5));
  switch (assetId) {
    case 'weed':
      return buildWeedAsset(hash);
    case 'branch':
      return buildBranchAsset(hash);
    case 'rock':
      return buildRockAsset(hash);
    case 'stump':
      return buildStumpAsset();
    case 'shipping-bin':
      return buildShippingBinAsset();
    default:
      return buildMiscAsset();
  }
}

// --- Player ---------------------------------------------------------------

const skinMat = () => flatMaterial(0xe8b88a, 'player-skin');
const shirtMat = () => flatMaterial(0xc96a3a, 'player-shirt');
const pantsMat = () => flatMaterial(0x5a4632, 'player-pants');
const hatMat = () => flatMaterial(0x6b4a2f, 'player-hat');
const eyeMat = () => flatMaterial(0x2a1f18, 'player-eye');

/**
 * A Minecraft-proportioned box character. The right arm is named
 * `player-arm-r` because the swing animation drives that exact node; legs are
 * `player-leg-l` / `player-leg-r` for the walk cycle.
 */
export function buildPlayer(): THREE.Object3D {
  const g = new THREE.Group();
  g.name = 'player';

  // Legs: 0.25 x 0.75 x 0.25 boxes (Minecraft's 12:8 ratio scaled down).
  const legL = new THREE.Mesh(new THREE.BoxGeometry(0.25, 0.75, 0.25), pantsMat());
  legL.position.set(-0.13, 0.375, 0);
  legL.name = 'player-leg-l';
  const legR = new THREE.Mesh(new THREE.BoxGeometry(0.25, 0.75, 0.25), pantsMat());
  legR.position.set(0.13, 0.375, 0);
  legR.name = 'player-leg-r';

  // Torso: 0.5 wide x 0.75 tall x 0.25 deep.
  const torso = new THREE.Mesh(new THREE.BoxGeometry(0.5, 0.75, 0.25), shirtMat());
  torso.position.y = 0.75 + 0.375;
  torso.name = 'player-torso';

  // Arms: 0.25 x 0.75 x 0.25, pivot at the shoulder so the swing rotates right.
  const armL = new THREE.Mesh(new THREE.BoxGeometry(0.25, 0.75, 0.25), shirtMat());
  armL.position.set(-0.375, 0.75 + 0.75 - 0.09, 0);
  armL.name = 'player-arm-l';
  const armR = new THREE.Mesh(new THREE.BoxGeometry(0.25, 0.75, 0.25), shirtMat());
  armR.position.set(0.375, 0.75 + 0.75 - 0.09, 0);
  armR.name = 'player-arm-r';

  // Head: 0.5 cube with a hat cap and front eyes.
  const head = new THREE.Mesh(new THREE.BoxGeometry(0.5, 0.5, 0.5), skinMat());
  head.position.y = 0.75 + 0.75 + 0.25;
  head.name = 'player-head';
  const cap = new THREE.Mesh(new THREE.BoxGeometry(0.54, 0.16, 0.54), hatMat());
  cap.position.y = head.position.y + 0.3;
  cap.name = 'player-hat';
  const eyeL = new THREE.Mesh(new THREE.BoxGeometry(0.09, 0.09, 0.02), eyeMat());
  eyeL.position.set(-0.11, head.position.y + 0.04, 0.26);
  const eyeR = new THREE.Mesh(new THREE.BoxGeometry(0.09, 0.09, 0.02), eyeMat());
  eyeR.position.set(0.11, head.position.y + 0.04, 0.26);

  for (const m of [legL, legR, torso, armL, armR, head, cap, eyeL, eyeR]) shadowed(m);
  g.add(legL, legR, torso, armL, armR, head, cap, eyeL, eyeR);
  return g;
}

// --- Highlight (Minecraft block outline) ---------------------------------

/**
 * A Minecraft-style block outline: a dark wireframe box around the targeted
 * block (not a translucent floor quad). A second, slightly larger additive
 * shell provides the subtle face tint.
 */
export function buildHighlight(): THREE.Object3D {
  const g = new THREE.Group();

  const edgeMat = new THREE.LineBasicMaterial({ color: 0x0d0a08, transparent: true, opacity: 0.95 });
  const edges = new THREE.LineSegments(new THREE.EdgesGeometry(new THREE.BoxGeometry(1.02, 1.02, 1.02)), edgeMat);
  edges.name = 'highlight-outline';
  g.add(edges);

  // Faint red/green face tint shell (kept subtle; the outline carries the read).
  const faceMat = new THREE.MeshBasicMaterial({
    color: 0xffcf7a,
    transparent: true,
    opacity: 0.12,
    depthWrite: false,
    side: THREE.DoubleSide,
  });
  const face = new THREE.Mesh(new THREE.BoxGeometry(1, 1, 1), faceMat);
  face.name = 'highlight-face';
  g.add(face);

  g.visible = false;
  return g;
}

// --- Precipitation --------------------------------------------------------

/**
 * Cheap procedural weather particles. `rain` renders a dense field of small
 * falling drops; `snow` renders larger, slower, soft flakes. The view module
 * owns the frame-by-frame fall; this just builds the static point cloud.
 */
export function buildPrecipitation(kind: 'rain' | 'snow', count: number): THREE.Points {
  const positions = new Float32Array(count * 3);
  const spread = 22;
  const span = 18;
  for (let i = 0; i < count; i++) {
    positions[i * 3] = (Math.random() - 0.5) * spread;
    positions[i * 3 + 1] = (Math.random() - 0.5) * span;
    positions[i * 3 + 2] = (Math.random() - 0.5) * spread;
  }
  const geometry = new THREE.BufferGeometry();
  geometry.setAttribute('position', new THREE.BufferAttribute(positions, 3));
  const material = new THREE.PointsMaterial({
    color: kind === 'rain' ? 0x9fb6cc : 0xffffff,
    size: kind === 'rain' ? 0.13 : 0.22,
    transparent: true,
    opacity: kind === 'rain' ? 0.7 : 0.9,
    depthWrite: false,
    sizeAttenuation: true,
  });
  const points = new THREE.Points(geometry, material);
  points.frustumCulled = false;
  points.userData = { kind, positions, count };
  return points;
}
