/**
 * Procedural low-poly asset builders (WORKER-1). Every mesh a map legend code
 * or placed-object id resolves to goes through here behind an asset-ID layer:
 * swap or upgrade any builder without touching the renderer. Palette is a
 * coherent ember/rustle autumn theme (see docs/ASSET_LICENSES.md for CC0
 * direction) — flat-shaded Lambert materials, no textures.
 */
import * as THREE from 'three';

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
    grass: new THREE.MeshLambertMaterial({ color: 0xffffff, name: 'grass-base' }),
    soil: new THREE.MeshLambertMaterial({ color: 0x7a5637, name: 'soil-base' }),
    path: new THREE.MeshLambertMaterial({ color: 0xcfbd93, name: 'path-base' }),
    water: new THREE.MeshLambertMaterial({
      color: 0x2f6f8f,
      name: 'water-base',
      transparent: true,
      opacity: 0.9,
    }),
  };
}

export function grassInstanceColor(x: number, z: number): THREE.Color {
  const f = 0.85 + 0.3 * hash2(x, z);
  return new THREE.Color(0x61913d).multiplyScalar(f);
}

function sharedMaterial(color: number, name: string): THREE.MeshLambertMaterial {
  return new THREE.MeshLambertMaterial({ color, name });
}

const furrowMat = () => sharedMaterial(0x49301a, 'soil-furrow');

/** The single, shared tilled-soil visual. Authored `s` tiles and player-tilled
 *  soil both go through here (buildTilledAsset delegates below), so cultivated
 *  ground reads identically everywhere. Crossed, higher-contrast strips so it
 *  stays visible under the interaction highlight. */
export function buildFurrow(x: number, z: number): THREE.Object3D {
  const g = new THREE.Group();
  const a = new THREE.Mesh(new THREE.BoxGeometry(1, 0.1, 0.26), furrowMat());
  a.position.y = 0.02;
  a.rotation.y = hash2(x, z) > 0.5 ? Math.PI / 2 : 0;
  const b = new THREE.Mesh(new THREE.BoxGeometry(0.26, 0.08, 1), furrowMat());
  b.position.y = 0.02;
  a.receiveShadow = true;
  b.receiveShadow = true;
  g.add(a, b);
  return g;
}

export function buildTilledAsset(x: number, z: number): THREE.Object3D {
  return buildFurrow(x, z);
}

const trunkMat = () => sharedMaterial(0x6b4a2f, 'tree-trunk');
const leafMat = () => sharedMaterial(0x4a6b31, 'tree-foliage');

export function buildTreeAsset(x: number, z: number): THREE.Object3D {
  const g = new THREE.Group();
  const h = hash2(x, z);
  const trunk = new THREE.Mesh(new THREE.CylinderGeometry(0.13, 0.19, 0.5, 7), trunkMat());
  trunk.position.y = 0.25;
  const foliage = new THREE.Mesh(new THREE.ConeGeometry(0.55, 0.95, 7), leafMat());
  foliage.position.y = 0.95;
  const accent = new THREE.Mesh(new THREE.ConeGeometry(0.34, 0.5, 6), sharedMaterial(0x8a5c2a, 'tree-accent'));
  accent.position.y = 1.35;
  trunk.castShadow = true;
  foliage.castShadow = true;
  accent.castShadow = true;
  trunk.receiveShadow = true;
  g.add(trunk, foliage, accent);
  const scale = 0.9 + 0.25 * h;
  g.scale.setScalar(scale);
  return g;
}

export function buildHouseAsset(span: HouseSpan): THREE.Object3D {
  const g = new THREE.Group();
  const cols = span.maxCol - span.minCol + 1;
  const rows = span.maxRow - span.minRow + 1;
  const w = cols * GRID_CELL;
  const d = rows * GRID_CELL;

  const base = new THREE.Mesh(new THREE.BoxGeometry(w + 0.14, 0.5, d + 0.14), sharedMaterial(0x8a5a3b, 'house-base'));
  base.position.y = 0.25;

  const walls = new THREE.Mesh(new THREE.BoxGeometry(w * 0.94, 0.75, d * 0.94), sharedMaterial(0xd9b38c, 'house-walls'));
  walls.position.y = 0.78;

  const roof = new THREE.Mesh(new THREE.ConeGeometry(1, 0.64, 4), sharedMaterial(0x8a4a2c, 'house-roof'));
  roof.rotation.y = Math.PI / 4;
  roof.scale.set(w / 1.414, 1, d / 1.414);
  roof.position.y = 1.22;

  const chimney = new THREE.Mesh(new THREE.BoxGeometry(0.2, 0.34, 0.2), sharedMaterial(0x7a4a2e, 'house-chimney'));
  chimney.position.set(w / 4, 1.42, d / 4);

  const door = new THREE.Mesh(new THREE.BoxGeometry(0.36, 0.52, 0.06), sharedMaterial(0x5a3b23, 'house-door'));
  door.position.set(0, 0.3, d / 2 - 0.03);

  const windowMat = sharedMaterial(0xcfe3d8, 'house-window');
  const winW = new THREE.Mesh(new THREE.BoxGeometry(0.06, 0.22, 0.22), windowMat);
  winW.position.set(w / 2 - 0.04, 0.68, -d / 5);
  const winE = new THREE.Mesh(new THREE.BoxGeometry(0.06, 0.22, 0.22), windowMat);
  winE.position.set(w / 2 - 0.04, 0.68, d / 5);

  for (const m of [base, walls, roof, chimney, door, winW, winE]) {
    m.castShadow = true;
    m.receiveShadow = true;
  }
  g.add(base, walls, roof, chimney, door, winW, winE);
  return g;
}

const weedMat = () => sharedMaterial(0x6fae49, 'weed');

export function buildWeedAsset(hash: number): THREE.Object3D {
  const g = new THREE.Group();
  const tufts = 3 + (hash > 0.5 ? 1 : 0);
  for (let i = 0; i < tufts; i++) {
    const t = new THREE.Mesh(new THREE.ConeGeometry(0.07, 0.22, 5), weedMat());
    const a = hash * 6.283 + i * 2.09;
    t.position.set(Math.cos(a) * 0.12, 0.14, Math.sin(a) * 0.12);
    t.castShadow = true;
    g.add(t);
  }
  return g;
}

export function buildBranchAsset(hash: number): THREE.Object3D {
  const g = new THREE.Group();
  const log = new THREE.Mesh(new THREE.CylinderGeometry(0.07, 0.12, 0.8, 7), sharedMaterial(0x7a5a3a, 'branch'));
  log.rotation.z = Math.PI / 2;
  log.position.y = 0.09;
  log.rotation.y = hash * Math.PI;
  const twig = new THREE.Mesh(new THREE.CylinderGeometry(0.03, 0.045, 0.3, 5), sharedMaterial(0x6b4a2f, 'branch-twig'));
  twig.position.set(0.25, 0.2, 0);
  twig.rotation.z = 0.7;
  log.castShadow = true;
  twig.castShadow = true;
  g.add(log, twig);
  return g;
}

export function buildRockAsset(hash: number): THREE.Object3D {
  const g = new THREE.Group();
  const main = new THREE.Mesh(new THREE.IcosahedronGeometry(0.32, 0), sharedMaterial(0x6f7378, 'rock'));
  main.scale.set(1, 0.62, 1);
  main.position.y = 0.17;
  main.rotation.y = hash * 5;
  const chip = new THREE.Mesh(new THREE.IcosahedronGeometry(0.16, 0), sharedMaterial(0x7e8287, 'rock-chip'));
  chip.scale.set(1, 0.6, 1);
  chip.position.set(0.3, 0.09, 0.15);
  main.castShadow = true;
  chip.castShadow = true;
  g.add(main, chip);
  return g;
}

export function buildStumpAsset(): THREE.Object3D {
  const g = new THREE.Group();
  const stump = new THREE.Mesh(new THREE.CylinderGeometry(0.2, 0.25, 0.34, 7), sharedMaterial(0x7a5637, 'stump'));
  stump.position.y = 0.17;
  const top = new THREE.Mesh(new THREE.CylinderGeometry(0.17, 0.17, 0.05, 7), sharedMaterial(0xc9a06a, 'stump-top'));
  top.position.y = 0.36;
  top.rotation.y = Math.PI / 7;
  stump.castShadow = true;
  top.receiveShadow = true;
  g.add(stump, top);
  return g;
}

export function buildShippingBinAsset(): THREE.Object3D {
  const g = new THREE.Group();
  const body = new THREE.Mesh(new THREE.BoxGeometry(0.95, 0.5, 0.6), sharedMaterial(0x9a6a3e, 'bin-body'));
  body.position.y = 0.27;
  const lid = new THREE.Mesh(new THREE.BoxGeometry(1.02, 0.13, 0.68), sharedMaterial(0x7a4a2e, 'bin-lid'));
  lid.position.y = 0.56;
  const slot = new THREE.Mesh(new THREE.BoxGeometry(0.52, 0.1, 0.06), sharedMaterial(0x3a2312, 'bin-slot'));
  slot.position.set(0, 0.52, 0.31);
  const postL = new THREE.Mesh(new THREE.BoxGeometry(0.09, 0.34, 0.09), sharedMaterial(0x6b4a2f, 'bin-post'));
  postL.position.set(-0.4, 0.17, -0.23);
  const postR = new THREE.Mesh(new THREE.BoxGeometry(0.09, 0.34, 0.09), sharedMaterial(0x6b4a2f, 'bin-post'));
  postR.position.set(0.4, 0.17, -0.23);
  for (const m of [body, lid, slot, postL, postR]) {
    m.castShadow = true;
    m.receiveShadow = true;
  }
  g.add(body, lid, slot, postL, postR);
  return g;
}

export function buildCropAsset(stage: number, hash: number): THREE.Object3D {
  const g = new THREE.Group();
  const s = 0.55 + 0.22 * Math.max(0, stage);
  const stem = new THREE.Mesh(new THREE.CylinderGeometry(0.03, 0.05, 0.34 * s, 5), sharedMaterial(0x4a7a2e, 'crop-stem'));
  stem.position.y = 0.17 * s;
  const leafA = new THREE.Mesh(new THREE.BoxGeometry(0.32 * s, 0.08, 0.05), leafMat());
  leafA.position.y = 0.22 * s;
  leafA.rotation.y = hash > 0.5 ? Math.PI / 2 : 0;
  const fruit = new THREE.Mesh(new THREE.SphereGeometry(0.07, 6, 5), sharedMaterial(0xcc6a2a, 'crop-fruit'));
  fruit.position.y = 0.4 * s;
  for (const m of [stem, leafA, fruit]) {
    m.castShadow = true;
    m.receiveShadow = true;
  }
  g.add(stem, leafA, fruit);
  return g;
}

export function buildMiscAsset(): THREE.Object3D {
  const g = new THREE.Group();
  const crate = new THREE.Mesh(new THREE.BoxGeometry(0.42, 0.42, 0.42), sharedMaterial(0xc99a5a, 'misc-crate'));
  crate.position.y = 0.21;
  const band = new THREE.Mesh(new THREE.BoxGeometry(0.46, 0.12, 0.46), sharedMaterial(0x8a6a3a, 'misc-band'));
  band.position.y = 0.3;
  crate.castShadow = true;
  band.castShadow = true;
  crate.receiveShadow = true;
  g.add(crate, band);
  return g;
}

export function buildPlacedAsset(assetId: string, stage: number, hash: number): THREE.Object3D {
  if (assetId === 'tilled') return buildTilledAsset(Math.floor(hash * 97), Math.floor(hash * 31));
  if (assetId.startsWith('crop:')) return buildCropAsset(stage, hash);
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

const skinMat = () => sharedMaterial(0xe8b88a, 'player-skin');
const shirtMat = () => sharedMaterial(0xc96a3a, 'player-shirt');
const pantsMat = () => sharedMaterial(0x5a4632, 'player-pants');
const hatMat = () => sharedMaterial(0x6b4a2f, 'player-hat');

export function buildPlayer(): THREE.Object3D {
  const g = new THREE.Group();

  const legL = new THREE.Mesh(new THREE.BoxGeometry(0.13, 0.34, 0.13), pantsMat());
  legL.position.set(-0.09, 0.17, 0);
  const legR = new THREE.Mesh(new THREE.BoxGeometry(0.13, 0.34, 0.13), pantsMat());
  legR.position.set(0.09, 0.17, 0);

  const torso = new THREE.Mesh(new THREE.BoxGeometry(0.36, 0.34, 0.22), shirtMat());
  torso.position.y = 0.5;

  const armL = new THREE.Mesh(new THREE.BoxGeometry(0.1, 0.3, 0.1), shirtMat());
  armL.position.set(-0.25, 0.52, 0);
  const armR = new THREE.Mesh(new THREE.BoxGeometry(0.1, 0.3, 0.1), shirtMat());
  armR.position.set(0.25, 0.52, 0);
  armR.name = 'player-arm-r';

  const head = new THREE.Mesh(new THREE.BoxGeometry(0.26, 0.26, 0.26), skinMat());
  head.position.y = 0.84;

  const brim = new THREE.Mesh(new THREE.CylinderGeometry(0.2, 0.2, 0.05, 10), hatMat());
  brim.position.y = 1.0;
  const crown = new THREE.Mesh(new THREE.BoxGeometry(0.2, 0.14, 0.2), hatMat());
  crown.position.y = 1.1;

  for (const m of [legL, legR, torso, armL, armR, head, brim, crown]) {
    m.castShadow = true;
    m.receiveShadow = true;
  }
  g.add(legL, legR, torso, armL, armR, head, brim, crown);
  return g;
}

export function buildHighlight(): THREE.Mesh {
  const mat = new THREE.MeshBasicMaterial({
    color: 0xffcf7a,
    transparent: true,
    opacity: 0.35,
    depthWrite: false,
  });
  const quad = new THREE.Mesh(new THREE.PlaneGeometry(0.82, 0.82), mat);
  quad.rotation.x = -Math.PI / 2;
  quad.position.y = 0.03;
  return quad;
}

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