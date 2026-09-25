import * as THREE from 'three';
import { mergeGeometries } from 'three/addons/utils/BufferGeometryUtils.js';
import { GRID_CELL } from './assets';
import type { Facing, MapState, NpcPresence, TilePos } from '../../../core/types';
import type { NpcDef } from '../../../core/schemas';

const DEFAULT_TUNIC = new THREE.Color(0xb97743);
const DEFAULT_HAIR = new THREE.Color(0x5a4632);
const PANTS_COLOR = new THREE.Color(0x4d4438);
const SKIN_COLOR = new THREE.Color(0xe8b88a);
const FACE_COLOR = new THREE.Color(0x332a24);
const MOVE_SECONDS = 0.48;
const ROTATION_LAMBDA = 12;
const BOB_HEIGHT = 0.035;
const BOB_HZ = 5.5;
const FACING_ROTATIONS: Readonly<Record<Facing, number>> = {
  down: 0,
  up: Math.PI,
  right: Math.PI / 2,
  left: -Math.PI / 2,
};

interface NpcEntry {
  mesh: THREE.Mesh<THREE.BufferGeometry, THREE.MeshLambertMaterial>;
  previous: THREE.Vector3;
  target: THREE.Vector3;
  observedX: number;
  observedY: number;
  elapsed: number;
  moving: boolean;
  facing: Facing;
  targetRotation: number;
  bobPhase: number;
}

export function facingRotation(facing: Facing): number {
  return FACING_ROTATIONS[facing];
}

export function facingFromDelta(dx: number, dy: number): Facing {
  if (dx > 0) return 'right';
  if (dx < 0) return 'left';
  if (dy > 0) return 'down';
  if (dy < 0) return 'up';
  return 'down';
}

export function smoothInterpolation(t: number): number {
  const progress = Math.max(0, Math.min(1, t));
  return progress * progress * (3 - 2 * progress);
}

function interpolateCoordinate(previous: number, current: number, progress: number): number {
  return previous + (current - previous) * progress;
}

export function interpolatePosition(previous: TilePos, current: TilePos, t: number): TilePos {
  const progress = smoothInterpolation(t);
  return {
    x: interpolateCoordinate(previous.x, current.x, progress),
    y: interpolateCoordinate(previous.y, current.y, progress),
  };
}

export function npcsForMap(map: MapState | undefined): NpcPresence[] {
  if (!map) return [];
  const result: NpcPresence[] = [];
  for (const npcId of Object.keys(map.npcs).sort()) {
    const npc = map.npcs[npcId];
    if (npc) result.push(npc);
  }
  return result;
}

function profileColor(profile: Record<string, unknown>, key: string, fallback: THREE.Color): THREE.Color {
  const value = profile[key];
  if (typeof value === 'number' && Number.isFinite(value)) return new THREE.Color(value);
  if (typeof value === 'string') {
    const text = value.trim();
    if (/^(?:#[0-9a-f]{3}|#[0-9a-f]{4}|#[0-9a-f]{6}|#[0-9a-f]{8})$/i.test(text)) {
      return new THREE.Color(text);
    }
    if (/^0x(?:[0-9a-f]{3}|[0-9a-f]{4}|[0-9a-f]{6}|[0-9a-f]{8})$/i.test(text)) {
      return new THREE.Color(Number.parseInt(text.slice(2), 16));
    }
  }
  return fallback.clone();
}

function coloredBox(
  width: number,
  height: number,
  depth: number,
  x: number,
  y: number,
  z: number,
  color: THREE.Color,
): THREE.BoxGeometry {
  const geometry = new THREE.BoxGeometry(width, height, depth);
  geometry.translate(x, y, z);
  const positions = geometry.getAttribute('position');
  const colors = new Float32Array(positions.count * 3);
  for (let i = 0; i < positions.count; i++) color.toArray(colors, i * 3);
  geometry.setAttribute('color', new THREE.BufferAttribute(colors, 3));
  return geometry;
}

function buildHumanoidGeometry(definition: NpcDef | undefined): THREE.BufferGeometry {
  const profile = definition?.baseProfile ?? {};
  const tunic = profileColor(profile, 'color', DEFAULT_TUNIC);
  const hair = profileColor(profile, 'hairColor', DEFAULT_HAIR);
  const parts = [
    coloredBox(0.13, 0.34, 0.13, -0.09, 0.17, 0, PANTS_COLOR),
    coloredBox(0.13, 0.34, 0.13, 0.09, 0.17, 0, PANTS_COLOR),
    coloredBox(0.36, 0.34, 0.22, 0, 0.5, 0, tunic),
    coloredBox(0.1, 0.3, 0.1, -0.25, 0.52, 0, tunic),
    coloredBox(0.1, 0.3, 0.1, 0.25, 0.52, 0, tunic),
    coloredBox(0.26, 0.26, 0.26, 0, 0.84, 0, hair),
    coloredBox(0.18, 0.11, 0.025, 0, 0.84, 0.14, SKIN_COLOR),
    coloredBox(0.065, 0.045, 0.035, 0, 0.835, 0.165, FACE_COLOR),
  ];
  const geometry = mergeGeometries(parts, false);
  for (const part of parts) part.dispose();
  if (!geometry) throw new Error('[engine:view] could not build NPC geometry');
  geometry.computeBoundingSphere();
  return geometry;
}

function setWorldTile(map: MapState, x: number, y: number, target: THREE.Vector3): void {
  target.set(
    (x - (map.grid.width - 1) / 2) * GRID_CELL,
    0,
    (y - (map.grid.height - 1) / 2) * GRID_CELL,
  );
}

export class NpcView {
  readonly group = new THREE.Group();

  private readonly definitions: ReadonlyMap<string, NpcDef>;
  private readonly material = new THREE.MeshLambertMaterial({
    color: 0xffffff,
    vertexColors: true,
    flatShading: true,
  });
  private readonly entries = new Map<string, NpcEntry>();
  private mapId: string | null = null;
  private disposed = false;

  constructor(definitions: ReadonlyMap<string, NpcDef>) {
    this.definitions = definitions;
    this.group.name = 'npcs';
    this.group.userData = { mapId: null };
  }

  get count(): number {
    return this.entries.size;
  }

  get meshCount(): number {
    return this.entries.size;
  }

  get currentMapId(): string | null {
    return this.mapId;
  }

  rebuild(map: MapState | undefined, mapId: string): void {
    if (this.disposed) return;
    this.clearEntries();
    this.mapId = mapId;
    this.group.userData = { mapId };

    for (const npc of npcsForMap(map)) {
      const definition = this.definitions.get(npc.npcId);
      const mesh = new THREE.Mesh(buildHumanoidGeometry(definition), this.material);
      const target = new THREE.Vector3();
      if (map) setWorldTile(map, npc.x, npc.y, target);
      mesh.name = `npc:${npc.npcId}`;
      mesh.userData = { npcId: npc.npcId, tileX: npc.x, tileY: npc.y };
      mesh.position.copy(target);
      mesh.rotation.y = facingRotation(npc.facing);
      this.group.add(mesh);
      this.entries.set(npc.npcId, {
        mesh,
        previous: target.clone(),
        target,
        observedX: npc.x,
        observedY: npc.y,
        elapsed: 1,
        moving: false,
        facing: npc.facing,
        targetRotation: facingRotation(npc.facing),
        bobPhase: 0,
      });
    }
    this.group.visible = this.entries.size > 0;
  }

  update(map: MapState | undefined, mapId: string, dt: number, forceRebuild = false): void {
    if (this.disposed) return;
    if (!map) {
      if (forceRebuild || this.mapId !== mapId || this.entries.size > 0) this.rebuild(undefined, mapId);
      return;
    }
    if (forceRebuild || this.mapId !== mapId || this.npcSetChanged(map)) {
      this.rebuild(map, mapId);
      return;
    }

    const frameDt = Math.max(0, dt);
    for (const npcId in map.npcs) {
      if (!Object.hasOwn(map.npcs, npcId)) continue;
      const npc = map.npcs[npcId];
      const entry = this.entries.get(npcId);
      if (!npc || !entry) continue;

      if (npc.x !== entry.observedX || npc.y !== entry.observedY) {
        entry.previous.copy(entry.target);
        setWorldTile(map, npc.x, npc.y, entry.target);
        entry.observedX = npc.x;
        entry.observedY = npc.y;
        entry.elapsed = 0;
        entry.moving = entry.previous.distanceToSquared(entry.target) > 0;
      }
      if (npc.facing !== entry.facing) {
        entry.facing = npc.facing;
        entry.targetRotation = facingRotation(npc.facing);
      }
      this.advance(entry, frameDt);
    }
  }

  dispose(): void {
    if (this.disposed) return;
    this.disposed = true;
    this.clearEntries();
    this.material.dispose();
    this.mapId = null;
    this.group.visible = false;
  }

  private advance(entry: NpcEntry, dt: number): void {
    if (entry.moving) {
      entry.elapsed = Math.min(MOVE_SECONDS, entry.elapsed + dt);
      const progress = smoothInterpolation(entry.elapsed / MOVE_SECONDS);
      entry.mesh.position.x = interpolateCoordinate(entry.previous.x, entry.target.x, progress);
      entry.mesh.position.z = interpolateCoordinate(entry.previous.z, entry.target.z, progress);
      entry.bobPhase += dt * BOB_HZ * Math.PI * 2;
      entry.mesh.position.y = Math.sin(entry.bobPhase) * BOB_HEIGHT;
      if (entry.elapsed >= MOVE_SECONDS) {
        entry.moving = false;
        entry.mesh.position.y = 0;
      }
    } else {
      entry.mesh.position.y = 0;
    }
    entry.mesh.rotation.y = THREE.MathUtils.damp(
      entry.mesh.rotation.y,
      entry.targetRotation,
      ROTATION_LAMBDA,
      dt,
    );
  }

  private npcSetChanged(map: MapState): boolean {
    let count = 0;
    for (const npcId in map.npcs) {
      if (!Object.hasOwn(map.npcs, npcId)) continue;
      count++;
      if (!this.entries.has(npcId)) return true;
    }
    return count !== this.entries.size;
  }

  private clearEntries(): void {
    for (const entry of this.entries.values()) entry.mesh.geometry.dispose();
    this.entries.clear();
    this.group.clear();
  }
}
