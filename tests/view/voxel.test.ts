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
  facingOfYaw,
  yawDelta,
  dampYaw,
  clampPitch,
  targetTileNdc,
  EYE_ABOVE_GROUND,
  EYE_HEIGHT,
  GROUND_TOP,
  HOUSE_HEIGHT,
  PITCH_DEFAULT,
  SURFACE_TOP,
  WATER_TOP,
  YAW_LAMBDA,
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
    // The eye hangs above GROUND_TOP (the terrain surface the player stands
    // on), NOT above the hidden legacy voxel layer's SURFACE_TOP.
    expect(GROUND_TOP).toBe(0);
    expect(EYE_HEIGHT).toBeCloseTo(EYE_ABOVE_GROUND, 6);
    expect(EYE_HEIGHT).toBeGreaterThan(GROUND_TOP + 0.6);
    expect(EYE_HEIGHT).toBeLessThan(2);
  });
});

describe('camera / facing coherence math', () => {
  it('maps a yaw back to the nearest cardinal', () => {
    expect(facingOfYaw(0)).toBe('down');
    expect(facingOfYaw(Math.PI / 2)).toBe('right');
    expect(facingOfYaw(Math.PI)).toBe('up');
    expect(facingOfYaw(-Math.PI / 2)).toBe('left');
    // wrap-safe: just before north is still west-ish, just after is north-ish
    expect(facingOfYaw(Math.PI - 0.01)).toBe('up');
    expect(facingOfYaw(Math.PI + 0.01)).toBe('up');
    expect(facingOfYaw(-Math.PI - 0.01)).toBe('up');
    expect(facingOfYaw(2 * Math.PI - 0.01)).toBe('down');
  });

  it('takes the short way round a yaw turn', () => {
    expect(yawDelta(0, Math.PI / 2)).toBeCloseTo(Math.PI / 2, 6);
    // south -> west must be -90°, never +270°
    expect(yawDelta(0, -Math.PI / 2)).toBeCloseTo(-Math.PI / 2, 6);
    // ...and the long way round wraps the same way
    expect(yawDelta(0, (3 * Math.PI) / 2)).toBeCloseTo(-Math.PI / 2, 6);
  });

  it('damps a yaw turn without overshooting', () => {
    const start = 0;
    const goal = Math.PI;
    let yaw = start;
    let steps = 0;
    while (Math.abs(yawDelta(yaw, goal)) > 1e-4 && steps < 600) {
      const before = Math.abs(yawDelta(yaw, goal));
      yaw = dampYaw(yaw, goal, YAW_LAMBDA, 1 / 60);
      const after = Math.abs(yawDelta(yaw, goal));
      expect(after).toBeLessThanOrEqual(before + 1e-9); // monotone approach
      expect(after).toBeGreaterThanOrEqual(-1e-9);
      steps++;
    }
    expect(steps).toBeGreaterThan(2); // eased, not a snap
    expect(yawDelta(yaw, goal)).toBeCloseTo(0, 3);
  });

  it('projects the targeted tile inside the viewport for every facing', () => {
    for (const facing of ['down', 'up', 'left', 'right'] as const) {
      const pose = { yaw: yawOfFacing(facing), pitch: PITCH_DEFAULT };
      const ndc = targetTileNdc(pose, facing, EYE_HEIGHT, 70, 16 / 9);
      expect(ndc.onScreen).toBe(true);
      expect(Math.abs(ndc.x)).toBeLessThan(1);
      expect(Math.abs(ndc.y)).toBeLessThan(1);
      // straight ahead, so horizontally centred: the crosshair covers it
      expect(ndc.x).toBeCloseTo(0, 6);
      // and it sits low in the frame, leaving the horizon visible near the top
      expect(ndc.y).toBeLessThan(0);
      expect(ndc.y).toBeGreaterThan(-0.9);
    }
  });

  it('drops the target off screen only when the player looks away from it', () => {
    // Pitching up far enough takes the one-tile target out of frame. That is the
    // documented reason the crosshair is gated on this projection instead of
    // being painted on unconditionally: no reticle, no promise.
    const up = targetTileNdc({ yaw: 0, pitch: PITCH_MAX }, 'down', EYE_HEIGHT, 70, 16 / 9);
    expect(up.onScreen).toBe(false);
    // looking straight down at your own feet still shows it (it fills the frame)
    const down = targetTileNdc({ yaw: 0, pitch: PITCH_MIN }, 'down', EYE_HEIGHT, 70, 16 / 9);
    expect(down.onScreen).toBe(true);
  });

  it('agrees with three.js projection', async () => {
    const THREE = await import('three');
    const pose = { yaw: yawOfFacing('down'), pitch: PITCH_DEFAULT };
    const camera = new THREE.PerspectiveCamera(70, 16 / 9, 0.1, 200);
    camera.position.set(0, EYE_HEIGHT, 0);
    const dir = lookVector(pose);
    camera.lookAt(camera.position.x + dir.x, camera.position.y + dir.y, camera.position.z + dir.z);
    camera.updateMatrixWorld();
    const v = new THREE.Vector3(0, GROUND_TOP, 1).project(camera);
    const ndc = targetTileNdc(pose, 'down', EYE_HEIGHT, 70, 16 / 9);
    expect(ndc.x).toBeCloseTo(v.x, 3);
    expect(ndc.y).toBeCloseTo(v.y, 3);
  });
});
