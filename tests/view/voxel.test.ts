/**
 * Voxel presentation math (WORKER-1). Pure grid → blocks + camera pose
 * helpers; no three.js, so it runs headless. Uses the real village/farm maps
 * from content.
 */
import { describe, expect, it } from 'vitest';
import { loadContent } from '@game/core/content';
import { mapStateFromDef } from '@game/core/state';
import {
  codeAt,
  headBob,
  lookVector,
  voxelColumns,
  yawOfFacing,
  clampPitch,
  EYE_HEIGHT,
  HOUSE_HEIGHT,
  SURFACE_TOP,
  WATER_TOP,
  PITCH_MAX,
  PITCH_MIN,
} from '@game/features/engine/view/voxel';

describe('voxelColumns', () => {
  it('extrudes house tiles into 3-tile cubes', async () => {
    const content = await loadContent();
    const def = content.maps.get('village')!;
    const map = mapStateFromDef(def);
    const boxes = voxelColumns(map, def.legend);

    const houses = boxes.filter((b) => b.kind === 'house');
    const expectedHouseish = map.grid.tiles.filter((c) => c === 'h').length;
    expect(houses.length).toBe(expectedHouseish);
    expect(houses.every((b) => b.h === HOUSE_HEIGHT && b.baseY === 0)).toBe(true);
    expect(houses.length).toBeGreaterThan(0); // village has h-regions
  });

  it('stacks trunk + crown for tree tiles', async () => {
    const content = await loadContent();
    const def = content.maps.get('farm')!;
    const map = mapStateFromDef(def);
    const boxes = voxelColumns(map, def.legend);
    const trunk = boxes.filter((b) => b.kind === 'tree-trunk');
    const crown = boxes.filter((b) => b.kind === 'tree-crown');
    expect(trunk.length).toBeGreaterThan(0);
    expect(crown.length).toBe(trunk.length);
    // crown sits directly on the trunk
    for (const c of crown) {
      const mate = trunk.find((t) => t.col === c.col && t.row === c.row);
      expect(mate).toBeDefined();
      expect(c.baseY).toBe(mate!.h);
    }
  });

  it('sinks water pools with rim walls on bordering floor tiles', async () => {
    const content = await loadContent();
    const def = content.maps.get('village')!;
    const map = mapStateFromDef(def);
    const boxes = voxelColumns(map, def.legend);

    const water = boxes.filter((b) => b.kind === 'water');
    const walls = boxes.filter((b) => b.kind === 'water-wall');
    expect(water.length).toBeGreaterThan(0);
    expect(walls.length).toBeGreaterThan(0);

    // water top sits at WATER_TOP below the walkable surface
    expect(water[0]!.baseY + water[0]!.h).toBe(WATER_TOP);
    expect(WATER_TOP).toBeLessThan(SURFACE_TOP);

    // every rim wall stands on a flat cell that borders water
    for (const w of walls) {
      const dirs: Array<[number, number]> = [
        [-1, 0],
        [1, 0],
        [0, -1],
        [0, 1],
      ];
      const adjacentWater = dirs.some(([dc, dr]) => {
        const cc = w.col + (dc as number);
        const rr = w.row + (dr as number);
        const code = codeAt(map, cc, rr);
        return code !== undefined && def.legend[code]?.water === true;
      });
      expect(adjacentWater).toBe(true);
    }
  });

  it('grass and middle aisle tiles produce no columns', async () => {
    const content = await loadContent();
    const def = content.maps.get('village')!;
    const map = mapStateFromDef(def);
    const boxes = voxelColumns(map, def.legend);
    // a fully interior grass cell (no water neighbour) must not be raised
    const raisedAisle = boxes.some((b) => b.kind === 'water-wall' && def.legend[codeAt(map, b.col, b.row)!]?.water === true);
    expect(raisedAisle).toBe(false);
  });

  it('produces a water pool with rims on the farm pond', async () => {
    const content = await loadContent();
    const def = content.maps.get('farm')!;
    const map = mapStateFromDef(def);
    const boxes = voxelColumns(map, def.legend);
    expect(boxes.filter((b) => b.kind === 'water').length).toBeGreaterThan(0);
    expect(boxes.filter((b) => b.kind === 'water-wall').length).toBeGreaterThan(0);
  });
});

describe('first-person pose', () => {
  it('maps facing to yaw: down→south(+z), right→east(+x), up→north, left→west', () => {
    expect(yawOfFacing('down')).toBe(0);
    expect(yawOfFacing('right')).toBeCloseTo(Math.PI / 2);
    expect(yawOfFacing('up')).toBeCloseTo(Math.PI);
    expect(yawOfFacing('left')).toBeCloseTo(-Math.PI / 2);
  });

  it('builds a unit look vector for yaw+pitch', () => {
    const v = lookVector({ yaw: 0, pitch: 0 });
    expect(v.z).toBeGreaterThan(0.99); // facing south
    const up = lookVector({ yaw: 0, pitch: 0.6 });
    expect(up.y).toBeCloseTo(Math.sin(0.6), 5);
    const e = lookVector({ yaw: Math.PI / 2, pitch: 0 });
    expect(e.x).toBeGreaterThan(0.99);
  });

  it('clamps pitch to the playable range', () => {
    expect(clampPitch(-9)).toBe(PITCH_MIN);
    expect(clampPitch(9)).toBe(PITCH_MAX);
    expect(clampPitch(0.1)).toBe(0.1);
  });

  it('head-bob is non-negative and bounded by BOB_AMPLITUDE', () => {
    for (let i = 0; i < 60; i++) {
      const b = headBob(i * 0.37);
      expect(b).toBeGreaterThanOrEqual(0);
      expect(b).toBeLessThanOrEqual(0.031);
    }
  });

  it('eye height sits above the walkable surface', () => {
    expect(EYE_HEIGHT).toBeGreaterThan(SURFACE_TOP + 0.6);
    expect(EYE_HEIGHT).toBeLessThan(2);
  });
});