import * as THREE from 'three';
import { describe, expect, it } from 'vitest';
import type { NpcDef } from '@game/core/schemas';
import type { Facing, MapState, NpcPresence } from '@game/core/types';
import {
  NpcView,
  facingFromDelta,
  interpolatePosition,
  npcsForMap,
} from '@game/features/engine/view/npcs';

function npc(npcId: string, x: number, y: number, facing: Facing = 'down'): NpcPresence {
  return { npcId, x, y, facing };
}

function mapState(
  id: string,
  width: number,
  height: number,
  npcs: Record<string, NpcPresence>,
): MapState {
  return {
    id,
    grid: { width, height, tiles: Array.from({ length: width * height }, () => 'g') },
    placed: {},
    npcs,
    version: 1,
  };
}

function definition(id: string, color?: string, hairColor?: string): NpcDef {
  return {
    id,
    name: id,
    birth: { season: 0, day: 1 },
    gift: { loves: [], likes: [], neutral: [], dislikes: [], hates: [] },
    baseProfile: { color, hairColor },
  };
}

describe('NPC view pure helpers', () => {
  it('derives only the NPCs stored on the requested map', () => {
    const village = mapState('village', 5, 5, {
      rowan: npc('rowan', 1, 2),
      marisol: npc('marisol', 3, 4),
    });
    const farm = mapState('farm', 3, 3, {});

    expect(npcsForMap(village).map((entry) => entry.npcId)).toEqual(['marisol', 'rowan']);
    expect(npcsForMap(farm)).toEqual([]);
    expect(npcsForMap(undefined)).toEqual([]);
  });

  it('derives cardinal facing from a movement delta with a down tie-break', () => {
    expect(facingFromDelta(1, 0)).toBe('right');
    expect(facingFromDelta(-1, 0)).toBe('left');
    expect(facingFromDelta(0, 1)).toBe('down');
    expect(facingFromDelta(0, -1)).toBe('up');
    expect(facingFromDelta(0, 0)).toBe('down');
  });

  it('interpolates and clamps positions within a tick window', () => {
    const previous = { x: 2, y: 5 };
    const current = { x: 6, y: 1 };

    expect(interpolatePosition(previous, current, -1)).toEqual(previous);
    expect(interpolatePosition(previous, current, 0.5)).toEqual({ x: 4, y: 3 });
    expect(interpolatePosition(previous, current, 2)).toEqual(current);
  });
});

describe('NpcView', () => {
  it('builds one colored humanoid mesh per NPC and rebuilds it for a warped map', () => {
    const definitions = new Map<string, NpcDef>([
      ['rowan', definition('rowan', '#4f7f76', '#3a261f')],
      ['marisol', definition('marisol', '#a84f45', '#6b3f24')],
    ]);
    const village = mapState('village', 5, 5, {
      rowan: npc('rowan', 1, 2, 'left'),
      marisol: npc('marisol', 3, 4, 'up'),
    });
    const farm = mapState('farm', 4, 3, {
      rowan: npc('rowan', 3, 2, 'right'),
    });
    const view = new NpcView(definitions);

    view.rebuild(village, 'village');

    expect(view.meshCount).toBe(2);
    expect(view.group.children).toHaveLength(2);
    expect(view.group.children.map((mesh) => mesh.userData.npcId)).toEqual(['marisol', 'rowan']);
    for (const child of view.group.children) {
      expect(child).toBeInstanceOf(THREE.Mesh);
      const mesh = child as THREE.Mesh;
      expect(mesh.geometry.getAttribute('color')).toBeDefined();
    }

    view.update(farm, 'farm', 1 / 60, true);

    expect(view.currentMapId).toBe('farm');
    expect(view.meshCount).toBe(1);
    expect(view.group.children).toHaveLength(1);
    expect(view.group.children[0]?.userData.npcId).toBe('rowan');
    expect(view.group.children[0]?.position.x).toBeCloseTo(1.5, 5);
    expect(view.group.children[0]?.position.z).toBeCloseTo(1, 5);
    view.dispose();
  });

  it('rebuilds when the NPC set changes on the same map', () => {
    const view = new NpcView(new Map<string, NpcDef>());
    view.rebuild(
      mapState('village', 3, 3, { rowan: npc('rowan', 0, 0) }),
      'village',
    );

    view.update(
      mapState('village', 3, 3, { marisol: npc('marisol', 2, 2) }),
      'village',
      1 / 60,
    );

    expect(view.meshCount).toBe(1);
    expect(view.group.children[0]?.userData.npcId).toBe('marisol');
    view.dispose();
  });

  it('lerps movement, bobs, and turns toward the simulated facing', () => {
    const village = mapState('village', 5, 3, { rowan: npc('rowan', 1, 1, 'down') });
    const view = new NpcView(new Map<string, NpcDef>());
    view.rebuild(village, 'village');
    const npcState = village.npcs.rowan!;
    npcState.x = 2;
    npcState.facing = 'right';

    view.update(village, 'village', 0.12);
    const mesh = view.group.children[0]!;

    expect(mesh.position.x).toBeGreaterThan(-1);
    expect(mesh.position.x).toBeLessThan(1);
    expect(mesh.position.y).not.toBe(0);
    expect(mesh.rotation.y).toBeGreaterThan(0);

    view.update(village, 'village', 0.48);
    expect(mesh.position.x).toBeCloseTo(0, 5);
    expect(mesh.position.y).toBe(0);
    expect(mesh.rotation.y).toBeCloseTo(Math.PI / 2, 2);
    view.dispose();
  });
});
