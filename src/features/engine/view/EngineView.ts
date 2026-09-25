/**
 * engine:view — the Three.js renderer (WORKER-1, lane 'world').
 *
 * Reads sim state every frame; never mutates it. Builds the farm map from
 * state.maps via an asset-ID layer (src/features/engine/view/assets.ts),
 * diff-syncs placed objects, lerps a low-poly player between tiles, runs an
 * angled top-down follow camera with wheel zoom, a facing interaction
 * highlight, and a day/night light ramp driven by world.clock.
 *
 * Headless guard: in Node (vitest, bot) setup returns a no-op handle and no
 * DOM/three-side is ever touched.
 */
import * as THREE from 'three';
import { defineFeature, type FeatureContext, type ViewHandle } from '../../../core/feature';
import type { GameState, MapState, SeasonIndex } from '../../../core/types';
import { tileInFront, isWalkable } from '../sim/PlayerPosition';
import { toolKindOf, type ToolKind } from '../../farming/sim/FarmingSim';
import {
  GRID_CELL,
  hash2,
  groundGeometry,
  groundMaterials,
  grassInstanceColor,
  buildFurrow,
  buildTreeAsset,
  buildHouseAsset,
  buildPlacedAsset,
  buildPlayer,
  buildHighlight,
  buildPrecipitation,
  type GroundMaterials,
  type HouseSpan,
} from './assets';
import { NpcView } from './npcs';

const CAM_PITCH = (57 * Math.PI) / 180;
const CAM_YAW = Math.PI / 4;
const CAM_DIR = new THREE.Vector3(
  Math.cos(CAM_PITCH) * Math.sin(CAM_YAW),
  Math.sin(CAM_PITCH),
  Math.cos(CAM_PITCH) * Math.cos(CAM_YAW),
).normalize();
const BASE_DISTANCE = 10;
const ZOOM_MIN = 0.6;
const ZOOM_MAX = 1.8;
const TILE_LERP_SECONDS = 0.11;
const FOLLOW_LAMBDA = 5;
const SWING_SECONDS = 0.26;
const FAIL_FLASH_SECONDS = 0.18;

const BURST_COLOR: Record<ToolKind, number> = {
  hoe: 0x8a5a30,
  watering: 0x4fa8e8,
  axe: 0x8a7a5a,
  pickaxe: 0x96908a,
  scythe: 0x7dbe63,
  hands: 0x6fae49,
};

const SKY_DAY = new THREE.Color(0x8ec6ea);
const SKY_NIGHT = new THREE.Color(0x0b1120);
const LIGHT_DAY = new THREE.Color(0xfff2d8);
const LIGHT_NIGHT = new THREE.Color(0x3b4f8f);
const AMBIENT_DAY = new THREE.Color(0xe8efff);
const AMBIENT_NIGHT = new THREE.Color(0x202c4a);

interface SeasonPalette {
  grassTint: THREE.Color;
  waterTint: THREE.Color;
  foliageTint: THREE.Color;
}

/** Per-season ambient tint, re-applied whenever world.calendar.seasonIndex changes. */
const SEASON_PALETTES: readonly SeasonPalette[] = [
  { grassTint: new THREE.Color(0x8fbe58), waterTint: new THREE.Color(0x2f8fb5), foliageTint: new THREE.Color(0x5a8a34) },
  { grassTint: new THREE.Color(0x7faf4a), waterTint: new THREE.Color(0x1f8ab0), foliageTint: new THREE.Color(0x4d7a2c) },
  { grassTint: new THREE.Color(0xc8b25a), waterTint: new THREE.Color(0x3f78a0), foliageTint: new THREE.Color(0xb4692a) },
  { grassTint: new THREE.Color(0xe2e8e2), waterTint: new THREE.Color(0x5f83a8), foliageTint: new THREE.Color(0xccd6cc) },
];

const WEATHER_RAIN = new THREE.Color(0x7d8a94);
const WEATHER_STORM = new THREE.Color(0x5d6a74);
const WEATHER_SNOW = new THREE.Color(0xd2dae2);
const WEATHER_WIND = new THREE.Color(0x90a4b8);

const FOG_NEAR = 26;
const FOG_FAR = 60;

export interface EngineViewHandle extends ViewHandle {
  dispose(): void;
}

function codeAt(map: MapState, x: number, y: number): string | undefined {
  if (x < 0 || y < 0 || x >= map.grid.width || y >= map.grid.height) return undefined;
  return map.grid.tiles[y * map.grid.width + x];
}

function collectHouseRegions(map: MapState): HouseSpan[] {
  const seen = new Set<number>();
  const regions: HouseSpan[] = [];
  const { width, height } = map.grid;
  for (let r = 0; r < height; r++) {
    for (let c = 0; c < width; c++) {
      const key = r * width + c;
      if (seen.has(key) || codeAt(map, c, r) !== 'h') continue;
      const cells: Array<[number, number]> = [];
      const stack: Array<[number, number]> = [[c, r]];
      seen.add(key);
      while (stack.length > 0) {
        const [cc, rr] = stack.pop()!;
        cells.push([cc, rr]);
        const neighbors: Array<[number, number]> = [
          [cc + 1, rr],
          [cc - 1, rr],
          [cc, rr + 1],
          [cc, rr - 1],
        ];
        for (const [nc, nr] of neighbors) {
          const nkey = nr * width + nc;
          if (!seen.has(nkey) && codeAt(map, nc, nr) === 'h') {
            seen.add(nkey);
            stack.push([nc, nr]);
          }
        }
      }
      const minCol = Math.min(...cells.map((p) => p[0]));
      const maxCol = Math.max(...cells.map((p) => p[0]));
      const minRow = Math.min(...cells.map((p) => p[1]));
      const maxRow = Math.max(...cells.map((p) => p[1]));
      regions.push({ minCol, maxCol, minRow, maxRow, hash: hash2(minCol, minRow) });
    }
  }
  return regions;
}

function createEngineView(ctx: FeatureContext): EngineViewHandle {
  if (ctx.headless || typeof document === 'undefined' || typeof window === 'undefined') {
    return {
      render(_dt: number, _time: number): void {},
      dispose(): void {},
    };
  }

  const gameRoot = document.getElementById('game-root');
  if (!gameRoot) throw new Error('[engine:view] missing #game-root element');
  const rootEl: HTMLElement = gameRoot;

  const renderer = new THREE.WebGLRenderer({ antialias: true, alpha: true });
  renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
  renderer.setSize(window.innerWidth, window.innerHeight);
  renderer.shadowMap.enabled = true;
  renderer.shadowMap.type = THREE.PCFSoftShadowMap;
  rootEl.appendChild(renderer.domElement);

  const scene = new THREE.Scene();
  const sky = new THREE.Color().copy(SKY_DAY);
  scene.background = sky;
  const fog = new THREE.Fog(new THREE.Color().copy(SKY_DAY), FOG_NEAR, FOG_FAR);
  scene.fog = fog;

  const camera = new THREE.PerspectiveCamera(50, window.innerWidth / window.innerHeight, 0.1, 200);

  const ambient = new THREE.AmbientLight(AMBIENT_DAY, 0.75);
  scene.add(ambient);

  const sun = new THREE.DirectionalLight(LIGHT_DAY, 1.1);
  sun.castShadow = true;
  sun.shadow.mapSize.set(1024, 1024);
  const sunCam = sun.shadow.camera;
  sunCam.left = -14;
  sunCam.right = 14;
  sunCam.top = 14;
  sunCam.bottom = -14;
  sunCam.near = 0.5;
  sunCam.far = 80;
  scene.add(sun);
  scene.add(sun.target);

  const groundLayer = new THREE.Group();
  const placedLayer = new THREE.Group();
  const npcView = new NpcView(ctx.content.npcs);
  const player = buildPlayer();
  const highlight = buildHighlight();
  highlight.visible = false;
  scene.add(groundLayer, placedLayer, npcView.group, player, highlight);

  const fxLayer = new THREE.Group();
  scene.add(fxLayer);
  interface FxParticle {
    mesh: THREE.Mesh;
    vel: THREE.Vector3;
    life: number;
    max: number;
  }
  const particles: FxParticle[] = [];
  const PARTICLE_CAP = 40;
  const armR = player.getObjectByName('player-arm-r') ?? null;
  let swingT = 0;
  let failFlashT = 0;

  function spawnBurst(tileWorld: THREE.Vector3, color: number): void {
    for (let i = 0; i < 9; i++) {
      if (particles.length >= PARTICLE_CAP) return;
      const mat = new THREE.MeshBasicMaterial({ color, transparent: true });
      const mesh = new THREE.Mesh(new THREE.BoxGeometry(0.09, 0.09, 0.09), mat);
      const a = Math.random() * Math.PI * 2;
      mesh.position.copy(tileWorld);
      mesh.position.y = 0.16;
      particles.push({
        mesh,
        vel: new THREE.Vector3(Math.cos(a) * 0.55, 1.4 + Math.random() * 1.3, Math.sin(a) * 0.55),
        life: 0.5,
        max: 0.5,
      });
      fxLayer.add(mesh);
    }
  }

  function onToolUsed(e: { tile: { x: number; y: number }; toolId: string }): void {
    const map = ctx.store.state.maps[ctx.store.state.player.position.mapId];
    if (!map) return;
    swingT = SWING_SECONDS;
    spawnBurst(worldPos(map, e.tile.x, e.tile.y), BURST_COLOR[toolKindOf(e.toolId)]);
  }

  function onToolFailed(): void {
    failFlashT = FAIL_FLASH_SECONDS;
  }

  let npcRebuildPending = false;
  const offWarp = ctx.bus.on('player:warped', () => {
    npcRebuildPending = true;
  });
  const offUsed = ctx.bus.on('tool:used', onToolUsed);
  const offFail = ctx.bus.on('tool:failed', onToolFailed);

  let disposed = false;
  let zoom = 1;
  let currentMapId: string | null = null;
  let gridKey = '';
  const placedMesh = new Map<string, THREE.Object3D>();
  const groundMatsRef: { mats: GroundMaterials | null } = { mats: null };
  let seasonApplied: SeasonIndex | null = null;

  const worldPos = (map: MapState, col: number, row: number): THREE.Vector3 =>
    new THREE.Vector3(
      (col - (map.grid.width - 1) / 2) * GRID_CELL,
      0,
      (row - (map.grid.height - 1) / 2) * GRID_CELL,
    );

  function disposeGroup(group: THREE.Group): void {
    for (const child of [...group.children]) {
      group.remove(child);
      child.traverse((node) => {
        if (node instanceof THREE.Mesh) {
          node.geometry.dispose();
          const mat = node.material;
          if (Array.isArray(mat)) {
            for (const m of mat) m.dispose();
          } else {
            mat.dispose();
          }
        }
      });
    }
  }

  function rebuildGround(state: GameState): void {
    const mapId = currentMapId;
    if (!mapId) return;
    const map = state.maps[mapId];
    if (!map) return;
    const legend = ctx.content.maps.get(mapId)?.legend ?? {};

    disposeGroup(groundLayer);

    const grassCells: Array<[number, number]> = [];
    const soilCells: Array<[number, number]> = [];
    const pathCells: Array<[number, number]> = [];
    const waterCells: Array<[number, number]> = [];
    const treeCells: Array<[number, number]> = [];

    const { width, height } = map.grid;
    for (let r = 0; r < height; r++) {
      for (let c = 0; c < width; c++) {
        const code = codeAt(map, c, r);
        if (code === 'h') continue;
        if (code === 't') {
          treeCells.push([c, r]);
          continue;
        }
        if (code === 's') {
          soilCells.push([c, r]);
          continue;
        }
        if (code === 'p') {
          pathCells.push([c, r]);
          continue;
        }
        if (legend[code ?? '']?.water === true) {
          waterCells.push([c, r]);
          continue;
        }
        grassCells.push([c, r]);
      }
    }

    const mats = groundMaterials();
    groundMatsRef.mats = mats;
    seasonApplied = null;

    function makeInstanced(
      gridMap: MapState,
      kind: 'grass' | 'soil' | 'path' | 'water',
      cells: Array<[number, number]>,
      material: THREE.Material,
    ): void {
      if (cells.length === 0) return;
      const mesh = new THREE.InstancedMesh(groundGeometry().clone(), material, cells.length);
      const dummy = new THREE.Object3D();
      for (let i = 0; i < cells.length; i++) {
        const [c, r] = cells[i]!;
        dummy.position.copy(worldPos(gridMap, c, r));
        dummy.updateMatrix();
        mesh.setMatrixAt(i, dummy.matrix);
        if (kind === 'grass') mesh.setColorAt(i, grassInstanceColor(c, r));
      }
      mesh.instanceMatrix.needsUpdate = true;
      if (mesh.instanceColor) mesh.instanceColor.needsUpdate = true;
      mesh.receiveShadow = kind !== 'water';
      groundLayer.add(mesh);
    }

    makeInstanced(map, 'grass', grassCells, mats.grass);
    makeInstanced(map, 'soil', soilCells, mats.soil);
    makeInstanced(map, 'path', pathCells, mats.path);
    makeInstanced(map, 'water', waterCells, mats.water);

    for (const [c, r] of soilCells) {
      const furrow = buildFurrow(c, r);
      furrow.position.copy(worldPos(map, c, r));
      groundLayer.add(furrow);
    }
    for (const [c, r] of treeCells) {
      const tree = buildTreeAsset(c, r);
      tree.position.copy(worldPos(map, c, r));
      groundLayer.add(tree);
    }
    for (const span of collectHouseRegions(map)) {
      const house = buildHouseAsset(span);
      house.position.set(
        ((span.minCol + span.maxCol) / 2 - (width - 1) / 2) * GRID_CELL,
        0,
        ((span.minRow + span.maxRow) / 2 - (height - 1) / 2) * GRID_CELL,
      );
      groundLayer.add(house);
    }
  }

  function syncPlaced(state: GameState): void {
    const mapId = currentMapId;
    if (!mapId) return;
    const map = state.maps[mapId];
    if (!map) return;
    const nextKeys = new Set(Object.keys(map.placed));
    for (const [key, obj] of placedMesh) {
      if (!nextKeys.has(key)) {
        placedLayer.remove(obj);
        placedMesh.delete(key);
      }
    }
    for (const key of nextKeys) {
      if (placedMesh.has(key)) continue;
      const placed = map.placed[key];
      if (!placed) continue;
      const data = placed.data?.stage;
      const stage = typeof data === 'number' ? data : 0;
      const object = buildPlacedAsset(placed.id, stage, hash2(placed.x, placed.y));
      object.position.copy(worldPos(map, placed.x, placed.y));
      placedLayer.add(object);
      placedMesh.set(key, object);
    }
  }

  function setMap(state: GameState, mapId: string): void {
    currentMapId = mapId;
    lastTileKey = '';
    disposedPlaced();
    const map = state.maps[mapId];
    gridKey = map ? `${map.grid.width}x${map.grid.height}:${map.grid.tiles.join('')}` : '';
    rebuildGround(state);
    syncPlaced(state);
  }

  function disposedPlaced(): void {
    for (const obj of placedMesh.values()) {
      placedLayer.remove(obj);
      obj.traverse((node) => {
        if (node instanceof THREE.Mesh) {
          node.geometry.dispose();
          const mat = node.material;
          if (Array.isArray(mat)) {
            for (const m of mat) m.dispose();
          } else {
            mat.dispose();
          }
        }
      });
    }
    placedMesh.clear();
  }

  function syncMapIfNeeded(state: GameState): void {
    const target = state.player.position.mapId;
    if (currentMapId !== target) {
      setMap(state, target);
      return;
    }
    const map = state.maps[target];
    if (!map) return;
    const key = `${map.grid.width}x${map.grid.height}:${map.grid.tiles.join('')}`;
    if (key !== gridKey) {
      gridKey = key;
      rebuildGround(state);
    }
    syncPlaced(state);
  }

  const lerpFrom = new THREE.Vector3();
  const lerpTo = new THREE.Vector3();
  let lerpT = 1;
  let lastTileKey = '';

  function facingRotation(facing: 'up' | 'down' | 'left' | 'right'): number {
    switch (facing) {
      case 'down':
        return 0;
      case 'up':
        return Math.PI;
      case 'right':
        return Math.PI / 2;
      case 'left':
        return -Math.PI / 2;
    }
  }

  function updatePlayer(dt: number, state: GameState): void {
    const mapId = currentMapId;
    if (!mapId) return;
    const map = state.maps[mapId];
    if (!map) return;
    const pos = state.player.position;
    const key = `${pos.x},${pos.y}`;
    const continuous = !Number.isInteger(pos.x) || !Number.isInteger(pos.y);
    if (continuous) {
      // Continuous walk already advances sub-tile positions every frame;
      // snap straight to the live world position (no lerp lag).
      player.position.copy(worldPos(map, pos.x, pos.y));
      lastTileKey = key;
    } else {
      if (key !== lastTileKey) {
        const target = worldPos(map, pos.x, pos.y);
        if (lastTileKey === '') {
          lerpFrom.copy(target);
          lerpTo.copy(target);
          lerpT = 1;
        } else {
          lerpFrom.copy(player.position);
          lerpTo.copy(target);
          lerpT = 0;
        }
        lastTileKey = key;
      }
      if (lerpT < 1) {
        lerpT = Math.min(1, lerpT + dt / TILE_LERP_SECONDS);
        const e = lerpT * lerpT * (3 - 2 * lerpT);
        player.position.lerpVectors(lerpFrom, lerpTo, e);
      }
    }
    player.rotation.y = THREE.MathUtils.damp(player.rotation.y, facingRotation(state.player.facing), 10, dt);
  }

  function updateHighlight(state: GameState): void {
    const mapId = currentMapId;
    if (!mapId) {
      highlight.visible = false;
      return;
    }
    const map = state.maps[mapId];
    if (!map) {
      highlight.visible = false;
      return;
    }
    const tile = tileInFront(state.player.position, state.player.facing);
    const inBounds =
      tile.x >= 0 && tile.y >= 0 && tile.x < map.grid.width && tile.y < map.grid.height;
    if (!inBounds) {
      highlight.visible = false;
      return;
    }
    const legend = ctx.content.maps.get(mapId)?.legend ?? {};
    const walkable = isWalkable(map, legend, tile.x, tile.y);
    const material = highlight.material as THREE.MeshBasicMaterial;
    if (failFlashT > 0) {
      material.color.setHex(0xe05a4f);
      material.opacity = 0.7;
    } else {
      material.color.setHex(walkable ? 0xffcf7a : 0xe56b4f);
      material.opacity = walkable ? 0.35 : 0.5;
    }
    highlight.visible = true;
    highlight.position.copy(worldPos(map, tile.x, tile.y));
  }

  function updateEffects(dt: number): void {
    for (let i = particles.length - 1; i >= 0; i--) {
      const p = particles[i]!;
      p.life -= dt;
      if (p.life <= 0) {
        fxLayer.remove(p.mesh);
        p.mesh.geometry.dispose();
        (p.mesh.material as THREE.Material).dispose();
        particles.splice(i, 1);
        continue;
      }
      p.vel.y -= 6 * dt;
      p.mesh.position.addScaledVector(p.vel, dt);
      const mat = p.mesh.material as THREE.MeshBasicMaterial;
      mat.opacity = Math.max(0, p.life / p.max);
      p.mesh.scale.setScalar(Math.max(0.06, p.life / p.max));
    }
    if (swingT > 0) {
      swingT = Math.max(0, swingT - dt);
      if (armR) {
        const ease = 1 - swingT / SWING_SECONDS;
        armR.rotation.z = -1.25 * Math.sin(Math.PI * Math.min(1, ease));
      }
    } else if (armR && armR.rotation.z !== 0) {
      armR.rotation.z = 0;
    }
    if (failFlashT > 0) failFlashT = Math.max(0, failFlashT - dt);
  }

  let cameraSettled = false;

  function updateCamera(dt: number): void {
    const target = player.position.clone();
    target.y = 0.7;
    const desired = target.clone().addScaledVector(CAM_DIR, BASE_DISTANCE * zoom);
    if (!cameraSettled) {
      camera.position.copy(desired);
      cameraSettled = true;
    } else {
      const k = 1 - Math.exp(-FOLLOW_LAMBDA * dt);
      camera.position.lerp(desired, k);
    }
    camera.lookAt(target);
  }

  const lightDay = new THREE.Color();
  const lightNight = new THREE.Color();
  const ambientDay = new THREE.Color();
  const ambientNight = new THREE.Color();

  function updateLighting(state: GameState): void {
    const h = state.world.clock.hour + state.world.clock.minute / 60;
    const a = ((h - 12) / 12) * Math.PI;
    const t = (Math.cos(a) + 1) / 2;

    lightDay.copy(LIGHT_DAY);
    lightNight.copy(LIGHT_NIGHT);
    sun.color.copy(lightNight).lerp(lightDay, t);
    sun.intensity = 0.28 + 0.95 * t;

    ambientDay.copy(AMBIENT_DAY);
    ambientNight.copy(AMBIENT_NIGHT);
    ambient.color.copy(ambientNight).lerp(ambientDay, t);
    ambient.intensity = 0.2 + 0.62 * t;

    sky.copy(SKY_NIGHT).lerp(SKY_DAY, t);

    const elevation = 0.35 + 0.9 * t;
    const p = player.position;
    const sweepX = Math.cos(((h - 6) / 12) * Math.PI);
    const sweepZ = Math.sin(((h - 6) / 12) * Math.PI);
    sun.position.set(p.x + sweepX * 10, 6 + 16 * elevation, p.z + sweepZ * 10);
    sun.target.position.set(p.x, 0, p.z);
  }

  const weatherTint = new THREE.Color();

  function applyWeatherTint(state: GameState, base: THREE.Color): THREE.Color {
    weatherTint.copy(base);
    switch (state.world.weather) {
      case 'rain':
        weatherTint.lerp(WEATHER_RAIN, 0.4);
        break;
      case 'storm':
        weatherTint.lerp(WEATHER_STORM, 0.55);
        break;
      case 'snow':
        weatherTint.lerp(WEATHER_SNOW, 0.5);
        break;
      case 'wind':
        weatherTint.lerp(WEATHER_WIND, 0.22);
        break;
      default:
        break;
    }
    return weatherTint;
  }

  /** Day/night sky + fog driven by world.clock.hour (dark ~22-04, bright midday). */
  function updateAtmosphere(state: GameState): void {
    const h = state.world.clock.hour + state.world.clock.minute / 60;
    const a = ((h - 12) / 12) * Math.PI;
    const t = (Math.cos(a) + 1) / 2;
    const tone = applyWeatherTint(state, SKY_NIGHT.clone().lerp(SKY_DAY, t));
    sky.copy(tone);
    fog.color.copy(tone);
  }

  function applySeasonPalette(state: GameState): void {
    const seasonIndex = state.world.calendar.seasonIndex;
    if (seasonApplied === seasonIndex) return;
    seasonApplied = seasonIndex;
    const palette = SEASON_PALETTES[seasonIndex];
    if (!palette) return;
    const mats = groundMatsRef.mats;
    if (mats) {
      mats.grass.color.copy(palette.grassTint);
      mats.water.color.copy(palette.waterTint);
    }
    groundLayer.traverse((node) => {
      if (node instanceof THREE.Mesh) {
        const material = node.material;
        if (material instanceof THREE.MeshLambertMaterial || material instanceof THREE.MeshStandardMaterial) {
          const name = material.name;
          if (name === 'tree-foliage' || name === 'tree-accent') {
            material.color.copy(palette.foliageTint);
          }
        }
      }
    });
  }

  let weatherKind: 'rain' | 'snow' | null = null;
  let precipLayer: THREE.Points | null = null;

  function disposePrecip(): void {
    if (!precipLayer) return;
    scene.remove(precipLayer);
    precipLayer.geometry.dispose();
    (precipLayer.material as THREE.Material).dispose();
    precipLayer = null;
    weatherKind = null;
  }

  /** Toggle a cheap particle layer to match world.weather (rain/storm/snow only). */
  function syncWeather(state: GameState): void {
    const w = state.world.weather;
    const kind: 'rain' | 'snow' | null = w === 'rain' || w === 'storm' ? 'rain' : w === 'snow' ? 'snow' : null;
    if (kind === weatherKind) return;
    disposePrecip();
    if (kind) {
      precipLayer = buildPrecipitation(kind, kind === 'rain' ? 220 : 140);
      scene.add(precipLayer);
      weatherKind = kind;
    }
  }

  function updatePrecipitation(dt: number, state: GameState): void {
    if (!precipLayer || !weatherKind) return;
    const positions = precipLayer.userData.positions as Float32Array;
    const count = precipLayer.userData.count as number;
    const fall = weatherKind === 'rain' ? 7.5 : 1.8;
    const width = 22;
    const span = 18;
    const drift = weatherKind === 'rain' ? 0.9 : 0.35;
    for (let i = 0; i < count; i++) {
      let x = positions[i * 3]! + drift * dt;
      let y = positions[i * 3 + 1]! - fall * dt;
      if (y < -span / 2) {
        y += span;
        x = (Math.random() - 0.5) * width;
        positions[i * 3 + 2] = (Math.random() - 0.5) * width;
      }
      if (x < -width / 2) x += width;
      else if (x > width / 2) x -= width;
      positions[i * 3] = x;
      positions[i * 3 + 1] = y;
    }
    precipLayer.geometry.attributes.position!.needsUpdate = true;
    const pos = state.player.position;
    const map = state.maps[pos.mapId];
    if (map) {
      precipLayer.position.copy(worldPos(map, pos.x, pos.y));
      precipLayer.position.y = 6;
    }
  }

  function updateWeatherVisuals(dt: number, state: GameState): void {
    syncWeather(state);
    updatePrecipitation(dt, state);
  }

  function render(dt: number, _time: number): void {
    const state = ctx.store.state;
    if (currentMapId === null && !state.maps[state.player.position.mapId]) return;
    syncMapIfNeeded(state);
    applySeasonPalette(state);
    updateWeatherVisuals(dt, state);
    const npcMapId = state.player.position.mapId;
    npcView.update(state.maps[npcMapId], npcMapId, dt, npcRebuildPending);
    npcRebuildPending = false;
    updatePlayer(dt, state);
    updateHighlight(state);
    updateEffects(dt);
    updateCamera(dt);
    updateLighting(state);
    updateAtmosphere(state);
    renderer.render(scene, camera);
  }

  function onResize(): void {
    const w = window.innerWidth;
    const h = window.innerHeight;
    renderer.setSize(w, h);
    camera.aspect = w / h;
    camera.updateProjectionMatrix();
  }

  function onWheel(e: WheelEvent): void {
    e.preventDefault();
    zoom = THREE.MathUtils.clamp(zoom * Math.exp(-e.deltaY * 0.0016), ZOOM_MIN, ZOOM_MAX);
  }

  window.addEventListener('resize', onResize);
  renderer.domElement.addEventListener('wheel', onWheel, { passive: false });

  function dispose(): void {
    if (disposed) return;
    disposed = true;
    window.removeEventListener('resize', onResize);
    renderer.domElement.removeEventListener('wheel', onWheel);
    offWarp();
    offUsed();
    offFail();
    for (const p of particles) {
      fxLayer.remove(p.mesh);
      p.mesh.geometry.dispose();
      (p.mesh.material as THREE.Material).dispose();
    }
    particles.length = 0;
    scene.remove(fxLayer);
    disposePrecip();
    disposedPlaced();
    npcView.dispose();
    disposeGroup(groundLayer);
    player.traverse((node) => {
      if (node instanceof THREE.Mesh) {
        node.geometry.dispose();
        const mat = node.material;
        if (Array.isArray(mat)) {
          for (const m of mat) m.dispose();
        } else {
          mat.dispose();
        }
      }
    });
    renderer.dispose();
    if (rootEl.contains(renderer.domElement)) rootEl.removeChild(renderer.domElement);
  }

  return { render, dispose };
}

let viewHandle: EngineViewHandle | null = null;

export const engineView = defineFeature({
  id: 'engine:view',
  lane: 'world',
  setup(ctx: FeatureContext): void {
    viewHandle = createEngineView(ctx);
  },
  view(): ViewHandle {
    if (!viewHandle) {
      viewHandle = {
        render(_dt: number, _time: number): void {},
        dispose(): void {},
      };
    }
    return viewHandle;
  },
  dispose(): void {
    viewHandle?.dispose();
    viewHandle = null;
  },
});