/**
 * Block registry + voxel terrain (WORKER-1). Runs headless in the node test
 * environment: the procedural 16x16 textures are CanvasTextures built over a
 * pixel buffer (NearestFilter), and the terrain builder produces real
 * InstancedMeshes with a finite, non-zero instance count from the real maps.
 */
import * as THREE from 'three';
import { describe, expect, it } from 'vitest';
import { loadContent } from '@game/core/content';
import { mapStateFromDef } from '@game/core/state';
import {
  allBlockKinds,
  blockKindForCode,
  blockRegistry,
  buildTerrain,
  getBlock,
  grassTopIsDistinct,
  terrainBlocks,
  FACE_ORDER,
} from '@game/features/engine/view/blocks';
import {
  blockTextureSet,
  blockTexture,
  paintTexture,
  cropTextureKeys,
  allTextureKeys,
  CROP_COLOURS,
  TEX_SIZE,
} from '@game/features/engine/view/textures';
import { buildPlacedAsset, buildCropAsset } from '@game/features/engine/view/assets';

describe('block registry', () => {
  it('resolves every block kind to a shared geometry plus material(s)', () => {
    const registry = blockRegistry();
    expect(registry.size).toBeGreaterThan(0);
    for (const kind of allBlockKinds()) {
      const def = registry.get(kind);
      expect(def, `missing registry entry ${kind}`).toBeDefined();
      expect(def!.geometry).toBeInstanceOf(THREE.BoxGeometry);
      expect(def!.materials.length).toBeGreaterThan(0);
      for (const mat of def!.materials) expect(mat).toBeInstanceOf(THREE.Material);
    }
  });

  it('gives the grass block six face groups with the top distinct from the sides', () => {
    const def = getBlock('grass');
    expect(def.perFace).toBe(true);
    expect(def.materials).toHaveLength(FACE_ORDER.length);
    expect(def.materials).toHaveLength(6);
    // FACE_ORDER = [px, nx, py, ny, pz, nz]; top = py (index 2).
    const top = def.materials[2] as THREE.MeshLambertMaterial;
    const sideA = def.materials[0] as THREE.MeshLambertMaterial;
    const sideB = def.materials[4] as THREE.MeshLambertMaterial;
    expect(top).toBeDefined();
    expect(sideA).toBeDefined();
    expect(top.map?.name).toBe('grass_top');
    expect(sideA.map?.name).toBe('grass_side');
    expect(sideB.map?.name).toBe('grass_side');
    expect(grassTopIsDistinct()).toBe(true);
  });

  it('uses a six-face array for the log (ring top/bottom, bark sides) too', () => {
    const def = getBlock('log');
    expect(def.perFace).toBe(true);
    expect(def.materials).toHaveLength(6);
  });
});

describe('procedural pixel textures', () => {
  it('generates 16x16 pixel-art with NearestFilter and no mipmaps', () => {
    const set = blockTextureSet();
    expect(Object.keys(set).length).toBeGreaterThan(0);
    for (const [key, tex] of Object.entries(set)) {
      expect(tex, `texture ${key} is not a CanvasTexture`).toBeInstanceOf(THREE.CanvasTexture);
      expect(tex.image.width).toBe(TEX_SIZE);
      expect(tex.image.height).toBe(TEX_SIZE);
      expect(tex.magFilter).toBe(THREE.NearestFilter);
      expect(tex.minFilter).toBe(THREE.NearestFilter);
      expect(tex.generateMipmaps).toBe(false);
    }
  });

  it('caches the texture set (same object on repeated calls)', () => {
    expect(blockTextureSet()).toBe(blockTextureSet());
    expect(blockTexture('stone')).toBe(blockTextureSet()['stone']);
  });

  it('paints a deterministic, varied pixel buffer for every texture key', () => {
    for (const key of allTextureKeys()) {
      const a = paintTexture(key);
      const b = paintTexture(key);
      expect(a.length).toBe(TEX_SIZE * TEX_SIZE * 4);
      // Deterministic: same key -> identical bytes.
      expect(Array.from(a)).toEqual(Array.from(b));
      // Vary pixels within a block (not flat colour).
      const unique = new Set<number>();
      for (let i = 0; i < a.length; i += 4) unique.add(a[i]!);
      expect(unique.size, `texture ${key} is flat`).toBeGreaterThan(1);
    }
  });

  it('ships ore stone variants and a per-crop leaf/stem set', () => {
    const set = blockTextureSet();
    for (const ore of ['ore_coal', 'ore_iron', 'ore_gold', 'ore_copper']) {
      expect(set[ore], `missing ore texture ${ore}`).toBeDefined();
    }
    for (const crop of Object.keys(CROP_COLOURS)) {
      const keys = cropTextureKeys(crop);
      expect(set[keys.leaf], `missing leaf texture for ${crop}`).toBeDefined();
      expect(set[keys.stem], `missing stem texture for ${crop}`).toBeDefined();
    }
  });
});

describe('legend + placed coverage', () => {
  it('maps every legend code in content/maps to a block kind', async () => {
    const content = await loadContent();
    const seen = new Set<string>();
    for (const def of content.maps.values()) {
      for (const code of Object.keys(def.legend)) {
        seen.add(code);
        const kind = blockKindForCode(code, def.legend);
        expect(getBlock(kind), `legend code ${code} -> ${kind}`).toBeDefined();
      }
    }
    // farm + village between them use at least g/s/w/h/t/p.
    for (const code of ['g', 's', 'w', 'h', 't', 'p']) {
      expect(seen.has(code), `expected legend code ${code} in content`).toBe(true);
    }
  });

  it('builds a placed asset for every placed-object id the content seeds', async () => {
    const content = await loadContent();
    const ids = new Set<string>();
    for (const def of content.maps.values()) {
      for (const p of def.initialPlaced) ids.add(p.id);
    }
    ids.add('tilled');
    ids.add('crop:parsnip');
    for (const id of ids) {
      const obj = buildPlacedAsset(id, 2, 0.5);
      expect(obj, `no asset for placed id ${id}`).toBeInstanceOf(THREE.Object3D);
    }
  });

  it('builds a per-crop coloured crop asset that grows with the stage', () => {
    const early = buildCropAsset(0, 0.5, 'parsnip');
    const mature = buildCropAsset(4, 0.5, 'parsnip');
    expect(early).toBeInstanceOf(THREE.Object3D);
    expect(mature).toBeInstanceOf(THREE.Object3D);
    // A mature crop has more cubes than a freshly seeded one.
    const count = (o: THREE.Object3D): number => {
      let n = 0;
      o.traverse((node) => {
        if (node instanceof THREE.Mesh) n++;
      });
      return n;
    };
    expect(count(mature)).toBeGreaterThan(count(early));
  });
});

describe('voxel terrain from a real map', () => {
  it('produces a finite, non-zero instance count for the farm', async () => {
    const content = await loadContent();
    const def = content.maps.get('farm')!;
    const map = mapStateFromDef(def);
    const blocks = terrainBlocks(map, def.legend);
    expect(blocks.length).toBeGreaterThan(0);
    for (const b of blocks) {
      expect(Number.isFinite(b.hash)).toBe(true);
      expect(b.height).toBeGreaterThan(0);
    }
    const worldPos = (col: number, row: number): THREE.Vector3 =>
      new THREE.Vector3(col, 0, row);
    const built = buildTerrain(blocks, worldPos);
    expect(built.instanceCount).toBeGreaterThan(0);
    expect(Number.isFinite(built.instanceCount)).toBe(true);
    // At least one instanced mesh was created.
    expect(built.meshes.size).toBeGreaterThan(0);
    for (const mesh of built.meshes.values()) {
      expect(mesh).toBeInstanceOf(THREE.InstancedMesh);
      expect(mesh.count).toBeGreaterThan(0);
    }
  });

  it('gives the farm a grass top height of 1 or 2 (visual variation only)', async () => {
    const content = await loadContent();
    const def = content.maps.get('farm')!;
    const map = mapStateFromDef(def);
    const blocks = terrainBlocks(map, def.legend);
    const grass = blocks.filter((b) => b.kind === 'grass');
    expect(grass.length).toBeGreaterThan(0);
    for (const g of grass) expect([1, 2]).toContain(g.height);
  });
});
