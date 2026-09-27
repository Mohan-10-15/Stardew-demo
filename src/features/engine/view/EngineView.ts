/**
 * engine:view — the Three.js renderer (WORKER-1, lane 'world').
 *
 * Reads sim state every frame; never mutates it. Builds the farm map from
 * state.maps via a voxel block registry (./blocks) + asset-ID layer
 * (./assets.ts), diff-syncs placed objects, lerps a Minecraft-proportioned
 * player between tiles, and runs a first-person eye camera (the DEFAULT, with
 * pointer-lock mouse look) that toggles to an angled top-down follow camera
 * with the V key. Interaction feedback is unmistakable: a successful
 * `tool:used` swings the arm and bursts blocky cube particles, while a
 * `tool:failed` only flashes the targeted block red.
 *
 * Headless guard: in Node (vitest, bot) setup returns a no-op handle and no
 * DOM/three-side is ever touched.
 *
 * Camera/facing coherence (T-0504): the first-person camera follows
 * `player.facing` (eased, never snapped) and free mouse look pushes the facing
 * back the other way via `player:face`, so the yaw and the 4-way facing can
 * never disagree and the tile `tileInFront()` returns is always the one under
 * the crosshair. Nothing in that chain needs pointer lock: the keyboard turns
 * the camera on its own, and pointer lock only upgrades the mouse to absolute
 * look (drag-to-look is the fallback).
 */
import * as THREE from 'three';
import { defineFeature, type FeatureContext, type ViewHandle } from '../../../core/feature';
import type { GameState, MapState, SeasonIndex } from '../../../core/types';
import type { MapLegend } from '../../../core/schemas';
import { tileInFront, isWalkable, JOG_UNITS_PER_SEC } from '../sim/PlayerPosition';
import { toolKindOf, type ToolKind } from '../../farming/sim/FarmingSim';
import {
  GRID_CELL,
  hash2,
  groundMaterials,
  grassInstanceColor,
  buildTreeAsset,
  buildHouseAsset,
  buildPlacedAsset,
  buildPlayer,
  buildHighlight,
  buildPrecipitation,
  type GroundMaterials,
  type HouseSpan,
} from './assets';
import {
  blockRegistry,
  buildTerrain,
  disposeTerrain,
  getBlock,
  terrainBlocks,
  type BuiltTerrain,
} from './blocks';
import { NpcView } from './npcs';
import { buildCrosshair } from './crosshair';
import {
  FirstPersonLook,
  lookInputDelta,
  lookInputPress,
  lookInputRelease,
  lookInputSwallowsClick,
  newLookInput,
} from './look';
import {
  EYE_ABOVE_GROUND,
  FOV_DEG,
  headBob,
  lookVector,
  targetTileNdc,
  voxelColumns,
  type VoxelKind,
} from './voxel';

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
const FAIL_FLASH_SECONDS = 0.2;
/** Pointer travel (px) past which a canvas click counts as a look drag. */
const DRAG_LOOK_PIXELS = 6;

/** The camera toggle key. NOT 'f' (f is bound to "open shop" in the keymap). */
export const VIEW_TOGGLE_KEY = 'v';

const BURST_COLOR: Record<ToolKind, number> = {
  hoe: 0x8a5a30,
  watering: 0x4fa8e8,
  axe: 0x8a7a5a,
  pickaxe: 0x96908a,
  scythe: 0x7dbe63,
  fishing: 0x4fb5c8,
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

/** Dev-only inspection handle published to globalThis (see publishDevHandle). */
interface DevSceneHandle {
  scene: THREE.Scene;
  camera: THREE.Camera;
  renderer: THREE.WebGLRenderer;
  metrics: () => {
    particles: number;
    swinging: boolean;
    failFlash: boolean;
    firstPerson: boolean;
  };
  /** Look state + whether the mouse is captured, for the browser probes. */
  look: () => {
    yaw: number;
    pitch: number;
    target: number;
    facing: string;
    pointerLocked: boolean;
    crosshair: boolean;
    eyeHeight: number;
  };
}

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

  // Camera-mode hint. A plain overlay (pointer-events: none) so it never steals
  // focus or blocks clicks; updated by setCameraMode. No stylesheet touch.
  const cameraHint = document.createElement('div');
  cameraHint.id = 'eh-camera-hint';
  cameraHint.style.position = 'absolute';
  cameraHint.style.left = '12px';
  cameraHint.style.bottom = '12px';
  cameraHint.style.padding = '4px 10px';
  cameraHint.style.background = 'rgba(8, 10, 16, 0.55)';
  cameraHint.style.color = '#e8f0ff';
  cameraHint.style.font = '600 12px/1.4 monospace';
  cameraHint.style.pointerEvents = 'none';
  cameraHint.style.zIndex = '10';
  rootEl.appendChild(cameraHint);
  const setHint = (first: boolean): void => {
    cameraHint.textContent = first
      ? 'Click to lock mouse • Drag to look • WASD turns • V = top view • Space = use tool'
      : 'V = back to first person • Space = use tool';
  };

  // First-person aim dot. Centred on the viewport, pointer-events none so it
  // can never eat the click that grabs pointer lock, and below the UI layer.
  const crosshair = buildCrosshair();
  rootEl.appendChild(crosshair.el);

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

  const camera = new THREE.PerspectiveCamera(FOV_DEG, window.innerWidth / window.innerHeight, 0.05, 200);

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
  scene.add(groundLayer, placedLayer, npcView.group, player, highlight);

  // First-person "voxel" presentation layer (see ./voxel.ts): extra block
  // columns for raised rims etc. Only visible with the first-person camera.
  const voxelGroup = new THREE.Group();
  scene.add(voxelGroup);
  const VOXEL_MATERIALS: Record<VoxelKind, THREE.MeshLambertMaterial> = {
    grass: new THREE.MeshLambertMaterial({ color: 0x61913d, name: 'voxel-grass', flatShading: true }),
    soil: new THREE.MeshLambertMaterial({ color: 0x7a5637, name: 'voxel-soil', flatShading: true }),
    path: new THREE.MeshLambertMaterial({ color: 0xcfbd93, name: 'voxel-path', flatShading: true }),
    water: new THREE.MeshLambertMaterial({
      color: 0x2f6f8f,
      name: 'voxel-water',
      flatShading: true,
      transparent: true,
      opacity: 0.86,
    }),
    'water-wall': new THREE.MeshLambertMaterial({ color: 0x5a4a38, name: 'voxel-wall', flatShading: true }),
    'tree-trunk': new THREE.MeshLambertMaterial({ color: 0x6b4a2f, name: 'voxel-trunk', flatShading: true }),
    'tree-crown': new THREE.MeshLambertMaterial({ color: 0x4a6b31, name: 'voxel-crown', flatShading: true }),
    house: new THREE.MeshLambertMaterial({ color: 0xd9b38c, name: 'voxel-house', flatShading: true }),
  };
  voxelGroup.visible = false;

  // First-person held hand: a blocky arm in the lower-right of the view.
  const handGroup = new THREE.Group();
  handGroup.name = 'fp-hand-group';
  {
    const armGeo = new THREE.BoxGeometry(0.16, 0.5, 0.16);
    const armMat = new THREE.MeshLambertMaterial({ color: 0xc96a3a, name: 'fp-arm', flatShading: true });
    const hand = new THREE.Mesh(armGeo, armMat);
    hand.name = 'fp-hand';
    handGroup.add(hand);
    const toolGeo = new THREE.BoxGeometry(0.1, 0.62, 0.1);
    const toolMat = new THREE.MeshLambertMaterial({ color: 0x8a6440, name: 'fp-tool', flatShading: true });
    const tool = new THREE.Mesh(toolGeo, toolMat);
    tool.name = 'fp-tool-mesh';
    tool.position.y = -0.5;
    handGroup.add(tool);
  }
  handGroup.position.set(0.42, -0.4, -0.7);
  handGroup.rotation.set(-0.5, -0.3, 0.2);
  handGroup.visible = false;
  handGroup.renderOrder = 2;
  // Parented to the camera so the held arm/tool stays pinned in the
  // lower-right of the view no matter where the player walks.
  camera.add(handGroup);
  scene.add(camera);

  // Dev-only scene handle so the browser harness can measure the live scene.
  let devHandle: DevSceneHandle | null = null;
  function publishDevHandle(): void {
    if (!import.meta.env.DEV) return;
    if (devHandle) return; // guard against double-publishing
    devHandle = {
      scene,
      camera,
      renderer,
      metrics: () => ({
        particles: particles.length,
        swinging: swingT > 0,
        failFlash: failFlashT > 0,
        firstPerson,
      }),
      look: () => ({
        yaw: look.yaw,
        pitch: look.pitch,
        target: look.target,
        facing: ctx.store.state.player.facing,
        pointerLocked: document.pointerLockElement === renderer.domElement,
        crosshair: crosshair.visible(),
        eyeHeight: EYE_ABOVE_GROUND,
      }),
    };
    (globalThis as unknown as { __EH_SCENE__?: DevSceneHandle }).__EH_SCENE__ = devHandle;
  }
  function clearDevHandle(): void {
    if (!devHandle) return;
    const g = globalThis as unknown as { __EH_SCENE__?: DevSceneHandle };
    if (g.__EH_SCENE__ === devHandle) delete g.__EH_SCENE__;
    devHandle = null;
  }
  publishDevHandle();

  const fxLayer = new THREE.Group();
  scene.add(fxLayer);
  interface FxParticle {
    mesh: THREE.Mesh;
    vel: THREE.Vector3;
    life: number;
    max: number;
  }
  const particles: FxParticle[] = [];
  const PARTICLE_CAP = 64;
  const armR = player.getObjectByName('player-arm-r') ?? null;
  const legL = player.getObjectByName('player-leg-l') ?? null;
  const legR = player.getObjectByName('player-leg-r') ?? null;
  let swingT = 0;
  let failFlashT = 0;

  // Shared cube-fragment geometry for particle bursts.
  const fragGeo = new THREE.BoxGeometry(0.08, 0.08, 0.08);

  function spawnBurst(tileWorld: THREE.Vector3, color: number): void {
    for (let i = 0; i < 12; i++) {
      if (particles.length >= PARTICLE_CAP) return;
      const mat = new THREE.MeshLambertMaterial({ color, flatShading: true });
      const mesh = new THREE.Mesh(fragGeo, mat);
      const a = Math.random() * Math.PI * 2;
      mesh.position.copy(tileWorld);
      mesh.position.y = 0.4;
      particles.push({
        mesh,
        vel: new THREE.Vector3(Math.cos(a) * 0.9, 1.8 + Math.random() * 1.6, Math.sin(a) * 0.9),
        life: 0.55,
        max: 0.55,
      });
      fxLayer.add(mesh);
    }
  }

  // Deliberately declared BEFORE the bus subscriptions below: EventBus replays
  // any buffered events synchronously on .on(), so these must exist already or
  // a buffered tool/cast event would hit a temporal-dead-zone ReferenceError.
  const worldPos = (map: MapState, col: number, row: number): THREE.Vector3 =>
    new THREE.Vector3(
      (col - (map.grid.width - 1) / 2) * GRID_CELL,
      0,
      (row - (map.grid.height - 1) / 2) * GRID_CELL,
    );

  function onToolUsed(e: { tile: { mapId?: string; x: number; y: number }; toolId: string }): void {
    const mapId = e.tile.mapId ?? ctx.store.state.player.position.mapId;
    const map = ctx.store.state.maps[mapId];
    if (!map) return;
    swingT = SWING_SECONDS;
    spawnBurst(worldPos(map, e.tile.x, e.tile.y), BURST_COLOR[toolKindOf(e.toolId)]);
  }

  function onToolFailed(): void {
    failFlashT = FAIL_FLASH_SECONDS;
  }

  // Fishing bobber: a pulsing float shown at the cast tile while the fishing
  // line is out, driven purely by bus events from fishing:sim.
  const bobberMat = new THREE.MeshLambertMaterial({ color: 0xd94f4f, flatShading: true });
  const bobber = new THREE.Mesh(new THREE.BoxGeometry(0.16, 0.16, 0.16), bobberMat);
  bobber.visible = false;
  scene.add(bobber);
  let bobberMapId: string | null = null;
  /** Float pulse phase; declared before subscriptions (buffered replays). */
  let bobberBob = 0;

  function hideBobber(): void {
    bobberMapId = null;
    bobber.visible = false;
  }

  function onFishingCast(payload: { tile: { mapId: string; x: number; y: number } }): void {
    const map = ctx.store.state.maps[payload.tile.mapId];
    if (!map) return;
    bobberMapId = payload.tile.mapId;
    bobber.position.copy(worldPos(map, payload.tile.x, payload.tile.y));
    bobber.position.y = 0.18;
    bobber.visible = true;
  }

  let npcRebuildPending = false;
  const offWarp = ctx.bus.on('player:warped', () => {
    npcRebuildPending = true;
    hideBobber();
  });
  const offUsed = ctx.bus.on('tool:used', onToolUsed);
  const offFail = ctx.bus.on('tool:failed', onToolFailed);
  const offMode = ctx.bus.on('view:camera-mode', (payload: { mode: 'top' | 'first' }) => {
    if (payload && (payload.mode === 'top' || payload.mode === 'first')) setCameraMode(payload.mode);
  });
  const offCast = ctx.bus.on('fishing:cast', onFishingCast);
  const offBite = ctx.bus.on('fishing:bite', () => {
    bobberBob = Math.PI; // quick excited pulse on the bite strike
  });
  const offHide = ctx.bus.on('fishing:caught', hideBobber);
  const offEscape = ctx.bus.on('fishing:escaped', hideBobber);
  const offCancel = ctx.bus.on('fishing:reel-cancel', hideBobber);
  const offNoFish = ctx.bus.on('fishing:no-fish', hideBobber);

  let disposed = false;
  let zoom = 1;
  let currentMapId: string | null = null;
  let gridKey = '';
  const placedMesh = new Map<string, THREE.Object3D>();
  const groundMatsRef: { mats: GroundMaterials | null } = { mats: null };
  let seasonApplied: SeasonIndex | null = null;
  let terrain: BuiltTerrain | null = null;

  // Minecraft is first person: boot into eye mode. Declared false so the
  // setCameraMode('first') call at the end of setup actually applies the
  // per-mode visibility (hand on, body off) instead of early-returning.
  let firstPerson = false;
  // Yaw/pitch + the camera<->facing agreement rule (./look).
  const look = new FirstPersonLook();
  let bobPhase = 0;
  const prevPlayerEye = new THREE.Vector3();

  function disposeGroup(group: THREE.Group): void {
    for (const child of [...group.children]) {
      group.remove(child);
      child.traverse((node) => {
        // Geometry + materials owned by the cached block registry must only be
        // detached here, never disposed (they survive map rebuilds).
        if (node.userData.sharedBlock === true) return;
        if (node instanceof THREE.Mesh || node instanceof THREE.LineSegments) {
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

  /** Tiles the player has hoed: `tilled` placed objects that are still on the map. */
  function tilledTiles(map: MapState): Set<string> {
    const out = new Set<string>();
    for (const key of Object.keys(map.placed)) {
      const placed = map.placed[key];
      if (placed && placed.id === 'tilled') out.add(`${placed.x},${placed.y}`);
    }
    return out;
  }

  /**
   * Grid + tilled tiles, i.e. everything the terrain InstancedMesh is built
   * from. Tilling/untilling changes the ground, so it has to invalidate the
   * cached terrain exactly like a grid change does.
   */
  function groundKey(map: MapState): string {
    return `${map.grid.width}x${map.grid.height}:${map.grid.tiles.join('')}|${[...tilledTiles(map)].sort().join(';')}`;
  }

  function rebuildGround(state: GameState): void {
    const mapId = currentMapId;
    if (!mapId) return;
    const map = state.maps[mapId];
    if (!map) return;
    const legend = ctx.content.maps.get(mapId)?.legend ?? {};

    disposeGroup(groundLayer);
    disposeTerrain(terrain);
    terrain = null;

    // Voxel terrain: one InstancedMesh per block kind, built from the grid.
    // Tilled tiles are part of THIS mesh (see the farmland note below), so
    // hoeing a tile does not spawn a second, differently-drawn soil block.
    const blocks = terrainBlocks(map, legend, tilledTiles(map));
    // Trees render as their own asset (a trunk + cube canopy), so skip the
    // single log block terrain would place under them.
    const groundBlocks = blocks.filter((b) => b.kind !== 'log');
    terrain = buildTerrain(groundBlocks, (c, r) => worldPos(map, c, r));
    groundLayer.add(terrain.group);

    // Add subtle per-instance grass tint (kept cheap; the texture carries look).
    const grassMesh = terrain.meshes.get('grass');
    if (grassMesh) {
      grassMesh.instanceColor = new THREE.InstancedBufferAttribute(
        new Float32Array(grassMesh.count * 3).fill(1),
        3,
      );
      let i = 0;
      for (const b of groundBlocks) {
        if (b.kind !== 'grass') continue;
        const c = grassInstanceColor(b.col, b.row);
        grassMesh.setColorAt(i, c);
        i++;
      }
      if (grassMesh.instanceColor) grassMesh.instanceColor.needsUpdate = true;
    }

    // Flat ground slab material reference for the season palette.
    const mats = groundMaterials();
    groundMatsRef.mats = mats;
    seasonApplied = null;

    // ONE tilled-soil look: authored `s` tiles and player-hoed tiles are both
    // farmland blocks in the terrain InstancedMesh above, so the two can never
    // diverge. syncPlaced() therefore skips the 'tilled' placed object — it is
    // bookkeeping for the sim, not something to draw on top of the ground.

    for (let row = 0; row < map.grid.height; row++) {
      for (let col = 0; col < map.grid.width; col++) {
        if (codeAt(map, col, row) !== 't') continue;
        const tree = buildTreeAsset(col, row);
        tree.position.copy(worldPos(map, col, row));
        groundLayer.add(tree);
      }
    }

    const width = map.grid.width;
    const height = map.grid.height;
    for (const span of collectHouseRegions(map)) {
      const house = buildHouseAsset(span);
      house.position.set(
        ((span.minCol + span.maxCol) / 2 - (width - 1) / 2) * GRID_CELL,
        0,
        ((span.minRow + span.maxRow) / 2 - (height - 1) / 2) * GRID_CELL,
      );
      groundLayer.add(house);
    }
    rebuildVoxels(map, legend);
  }

  function rebuildVoxels(map: MapState, legend: MapLegend): void {
    disposeGroup(voxelGroup);
    for (const box of voxelColumns(map, legend)) {
      const mat = VOXEL_MATERIALS[box.kind];
      const mesh = new THREE.Mesh(new THREE.BoxGeometry(1, box.h, 1), mat);
      const p = worldPos(map, box.col, box.row);
      mesh.position.set(p.x, box.baseY + box.h / 2, p.z);
      mesh.castShadow = box.kind === 'house' || box.kind === 'tree-crown' || box.kind === 'water-wall';
      mesh.receiveShadow = box.kind !== 'water';
      voxelGroup.add(mesh);
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
        placedMesh.delete(key);
      }
    }
    for (const key of nextKeys) {
      if (placedMesh.has(key)) continue;
      const placed = map.placed[key];
      if (!placed) continue;
      // Tilled soil is drawn by the terrain mesh (one look for authored and
      // player-hoed tiles alike), so it must not be drawn a second time here.
      if (placed.id === 'tilled') continue;
      const data = placed.data?.stage;
      const stage = typeof data === 'number' ? data : 0;
      // Pass the crop id so per-crop colours resolve; otherwise default.
      const cropId = placed.id.startsWith('crop:') ? placed.id.slice(5) : 'default';
      const object = buildPlacedAsset(placed.id, stage, hash2(placed.x, placed.y), cropId);
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
    gridKey = map ? groundKey(map) : '';
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
    const key = groundKey(map);
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
      player.position.copy(worldPos(map, pos.x, pos.y));
      lastTileKey = key;
    } else {
      if (key !== lastTileKey) {
        const target = worldPos(map, pos.x, pos.y);
        if (lastTileKey === '') {
          // First frame: no move to ease from, so snap onto the tile. Without
          // this the group stays at the world origin — which put the
          // first-person eye in the middle of the map instead of on the player
          // and put the avatar there in the follow camera.
          lerpFrom.copy(target);
          lerpTo.copy(target);
          lerpT = 1;
          player.position.copy(target);
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

    // Walk cycle. Driven by the distance actually covered this frame on EITHER
    // axis: the old check compared x only, so walking north/south (dy) never
    // swung the legs and the avatar read as sliding. Speed-scaled, so the legs
    // keep stride with the position and never moonwalk, and eased to rest when
    // the player stops (which is what makes a stop read as a stop).
    const stepX = pos.x - lastPlayerX;
    const stepY = pos.y - lastPlayerY;
    const travelled = Math.hypot(stepX, stepY);
    lastPlayerX = pos.x;
    lastPlayerY = pos.y;
    if (travelled > 1e-5) {
      const stride = Math.min(1, travelled / (JOG_UNITS_PER_SEC * (1 / 60)));
      walkPhase += (dt * 9 * (0.35 + 0.65 * stride));
      const swing = Math.sin(walkPhase) * 0.5 * (0.4 + 0.6 * stride);
      if (legL) legL.rotation.x = swing;
      if (legR) legR.rotation.x = -swing;
      // Lean into the step so the body is not perfectly rigid while walking.
      player.position.y = -Math.abs(Math.sin(walkPhase)) * 0.03;
    } else if (legL || legR) {
      if (legL) legL.rotation.x = THREE.MathUtils.damp(legL.rotation.x, 0, 12, dt);
      if (legR) legR.rotation.x = THREE.MathUtils.damp(legR.rotation.x, 0, 12, dt);
      player.position.y = THREE.MathUtils.damp(player.position.y, 0, 12, dt);
    }
  }
  let walkPhase = 0;
  let lastPlayerX = NaN;
  let lastPlayerY = NaN;

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

    // Tint the outline + face shell. A failure is a unmistakable red flash;
    // otherwise a soft gold when the tile is actionable, amber when blocked.
    const outline = highlight.getObjectByName('highlight-outline') as THREE.LineSegments | undefined;
    const face = highlight.getObjectByName('highlight-face') as THREE.Mesh | undefined;
    if (failFlashT > 0) {
      if (outline) (outline.material as THREE.LineBasicMaterial).color.setHex(0xff3b2f);
      if (face) {
        const m = face.material as THREE.MeshBasicMaterial;
        m.color.setHex(0xff3b2f);
        m.opacity = 0.5;
      }
    } else {
      if (outline) (outline.material as THREE.LineBasicMaterial).color.setHex(0x1a1410);
      if (face) {
        const m = face.material as THREE.MeshBasicMaterial;
        m.color.setHex(walkable ? 0xffcf7a : 0xe56b4f);
        m.opacity = walkable ? 0.12 : 0.2;
      }
    }

    highlight.visible = true;
    const p = worldPos(map, tile.x, tile.y);
    highlight.position.set(p.x, 0.5, p.z);
  }

  function updateEffects(dt: number): void {
    for (let i = particles.length - 1; i >= 0; i--) {
      const p = particles[i]!;
      p.life -= dt;
      if (p.life <= 0) {
        fxLayer.remove(p.mesh);
        (p.mesh.material as THREE.Material).dispose();
        particles.splice(i, 1);
        continue;
      }
      p.vel.y -= 6 * dt;
      p.mesh.position.addScaledVector(p.vel, dt);
      const s = Math.max(0.1, p.life / p.max);
      p.mesh.scale.setScalar(s);
    }
    if (swingT > 0) {
      swingT = Math.max(0, swingT - dt);
      const ease = 1 - swingT / SWING_SECONDS;
      const swing = -1.25 * Math.sin(Math.PI * Math.min(1, ease));
      if (armR) armR.rotation.z = swing;
      if (handGroup.visible) {
        handGroup.rotation.x = -0.5 + swing * 0.9;
        handGroup.position.z = -0.7 - Math.sin(Math.PI * Math.min(1, ease)) * 0.12;
      }
    } else {
      if (armR && armR.rotation.z !== 0) armR.rotation.z = 0;
      if (handGroup.visible) {
        handGroup.rotation.x = THREE.MathUtils.damp(handGroup.rotation.x, -0.5, 12, dt);
        handGroup.position.z = THREE.MathUtils.damp(handGroup.position.z, -0.7, 12, dt);
      }
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

  /** Eye-level camera: sits on the player, looks along yaw/pitch, bobs while walking. */
  function updateFirstPersonCamera(dt: number, state: GameState): void {
    const map = state.maps[state.player.position.mapId];
    if (!map) return;
    // The authoritative sim facing re-aims the camera (eased, short way round).
    // A mouse-look already put the camera where it wants to be, so look.syncFacing
    // leaves that alone. This is the whole no-pointer-lock guarantee: the camera
    // follows `facing` whether or not the mouse is captured.
    look.syncFacing(state.player.facing);
    look.update(dt);
    if (player.position.distanceToSquared(prevPlayerEye) > 1e-6) bobPhase += dt * 9;
    prevPlayerEye.copy(player.position);
    const eye = player.position.clone();
    eye.y = player.position.y + EYE_ABOVE_GROUND + headBob(bobPhase);
    const dir = lookVector(look);
    camera.position.copy(eye);
    camera.lookAt(eye.x + dir.x, eye.y + dir.y, eye.z + dir.z);
    // The reticle marks the tile a tool will actually hit, not the middle of the
    // screen: with a one-tile reach the screen centre is about a tile and a half
    // away, so a centre-painted crosshair would promise the wrong tile. Same
    // projection the unit tests pin against three.js; hidden when the target
    // leaves the frame, so it never lies.
    const aim = targetTileNdc(look, state.player.facing, EYE_ABOVE_GROUND, FOV_DEG, camera.aspect);
    crosshair.place(aim.x, aim.y, aim.onScreen);
  }

  /** Toggle 'top' (follow) / 'first' (eye) presentation. */
  function setCameraMode(mode: 'top' | 'first'): void {
    const on = mode === 'first';
    if (on === firstPerson) return;
    firstPerson = on;
    // The real cubic terrain (groundLayer) is the world in BOTH cameras. The
    // legacy voxel rim/crown columns (voxelGroup) are superseded by
    // buildTreeAsset/buildHouseAsset + the instanced water mesh, so that layer
    // stays hidden to avoid double geometry.
    groundLayer.visible = true;
    voxelGroup.visible = false;
    placedLayer.visible = true;
    // Hide the body you are standing in; show it again in the follow camera.
    player.visible = !firstPerson;
    handGroup.visible = firstPerson;
    crosshair.setVisible(firstPerson);
    if (firstPerson) {
      zoom = 1;
      // Start the look exactly on the compass direction the player faces, at
      // the pitch that keeps the targeted tile on screen.
      look.reset(ctx.store.state.player.facing);
      cameraSettled = false;
    }
    setHint(firstPerson);
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
        if (Array.isArray(material)) return;
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

  /** Bob the float gently; hide it if the player left the bobber's map. */
  function updateBobber(dt: number, state: GameState): void {
    if (!bobber.visible) return;
    if (bobberMapId === null || bobberMapId !== state.player.position.mapId) {
      hideBobber();
      return;
    }
    const map = state.maps[bobberMapId];
    if (!map) {
      hideBobber();
      return;
    }
    bobberBob += dt;
    bobber.position.y = 0.16 + Math.sin(bobberBob * 3.2) * 0.03;
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
    updateBobber(dt, state);
    if (firstPerson) {
      updateFirstPersonCamera(dt, state);
    } else {
      updateCamera(dt);
    }
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
    if (firstPerson) return; // free-look mode: wheel does not zoom
    zoom = THREE.MathUtils.clamp(zoom * Math.exp(-e.deltaY * 0.0016), ZOOM_MIN, ZOOM_MAX);
  }

  /** True when the keydown is aimed at a text field / editable node. */
  function isFormTarget(target: EventTarget | null): boolean {
    if (!(target instanceof HTMLElement)) return false;
    return (
      target.isContentEditable ||
      target instanceof HTMLInputElement ||
      target instanceof HTMLTextAreaElement ||
      target instanceof HTMLSelectElement
    );
  }

  /** Movement keys main.ts + the input feature listen for (held sets). */
  const MOVE_KEYS = ['w', 'a', 's', 'd', 'arrowup', 'arrowdown', 'arrowleft', 'arrowright', 'shift'];

  /**
   * A DOM panel stole focus: release pointer lock (browser Esc also does this)
   * and clear every held movement key so the player stops instantly. A real
   * window `keyup` for each key clears both main.ts's `held` and the input
   * feature's `held` set; repeats are ignored, so movement stays stopped until
   * the user presses the key again.
   */
  function releaseMoveKeys(): void {
    if (document.pointerLockElement === renderer.domElement) document.exitPointerLock();
    for (const key of MOVE_KEYS) {
      window.dispatchEvent(new KeyboardEvent('keyup', { key, bubbles: true, cancelable: true }));
    }
  }

  function onModeKey(e: KeyboardEvent): void {
    if (isFormTarget(e.target)) return;
    if (e.code === 'KeyV' || e.key.toLowerCase() === VIEW_TOGGLE_KEY) {
      setCameraMode(firstPerson ? 'top' : 'first');
    }
  }

  // Pointer lock is a nice-to-have: `./look` owns the rule that turns a pointer
  // event into a look delta for BOTH cases, and nothing below branches on it.
  const lookInput = newLookInput();

  /**
   * Apply a mouse-look delta and push the resulting cardinal into the sim, so
   * the camera and the 4-way `facing` (which decides what a tool hits) can
   * never disagree. `player:face` is the same dispatch path the movement
   * reducers use — one owner of `player.facing`, no second source of truth.
   */
  function applyLook(dx: number, dy: number): void {
    if (dx === 0 && dy === 0) return;
    const facing = look.look(dx, dy);
    const current = ctx.store.state.player.facing;
    if (facing !== current) {
      ctx.store.dispatch({ type: 'player:face', payload: { facing } });
    }
    // Adopt whatever the sim says (it is the authority) so the next frame's
    // syncFacing recognises this as a mouse-driven turn and does not re-aim.
    look.syncFacing(ctx.store.state.player.facing);
  }

  function onMouseDown(e: MouseEvent): void {
    if (!firstPerson || e.button !== 0) return;
    lookInputPress(lookInput, e);
  }

  function onMouseUp(): void {
    lookInputRelease(lookInput);
  }

  function onLook(e: MouseEvent): void {
    if (!firstPerson) return;
    const { dx, dy } = lookInputDelta(lookInput, e);
    applyLook(dx, dy);
  }

  // Pointer lock: request on canvas click; Esc (browser default) releases it.
  // If a UI panel has focus, we release the lock and stop moving so the panel
  // is usable.
  function onCanvasClick(e: MouseEvent): void {
    if (!firstPerson) return;
    if (lookInputSwallowsClick(lookInput, DRAG_LOOK_PIXELS)) {
      // That was a look drag, not a click: swallow it so the swing does not
      // fire at a tile the player was only aiming at.
      e.stopPropagation();
      return;
    }
    if (lookInput.locked) return; // already captured: this click swings the tool
    const el = document.activeElement;
    if (el instanceof HTMLElement && el !== document.body && el !== renderer.domElement) {
      // A DOM panel owns focus — don't grab the mouse.
      if (lookInput.locked) document.exitPointerLock();
      return;
    }
    // Grabbing the mouse is not using the tool: swallow this click so the
    // input feature's document-level handler does not swing the hoe at nothing.
    e.stopPropagation();
    // Optimistic: the lock normally lands in the same task, and a mousemove
    // between here and the event should already treat the mouse as captured.
    // Both refusal paths below take the flag back.
    lookInput.locked = true;
    const req = renderer.domElement.requestPointerLock() as unknown as Promise<void> | undefined;
    if (req && typeof req.then === 'function') {
      // Chrome returns a promise that REJECTS when the grab is refused (no user
      // gesture, a policy, a sandboxed frame). Hand the flag back so the
      // unlocked drag fallback keeps working instead of faking a capture.
      req.catch(() => {
        lookInput.locked = false;
        lookInputRelease(lookInput);
      });
    }
  }

  /**
   * Pointer lock refused (no user gesture, a policy, a browser without it): the
   * camera keeps working — the keyboard still turns it, drag-to-look still
   * looks — so nothing has to be unlocked or repaired. `lookInput.locked` is
   * driven by the browser's own answer, not by the fact that we asked, so a
   * failed request can never leave the input in a fake-locked state.
   */
  function onPointerLockChange(): void {
    lookInput.locked = document.pointerLockElement === renderer.domElement;
    if (!lookInput.locked) lookInputRelease(lookInput);
  }

  /** The other refusal signal: the grab was denied, so nothing is captured. */
  function onPointerLockError(): void {
    lookInput.locked = false;
    lookInputRelease(lookInput);
  }

  function onFocusIn(e: FocusEvent): void {
    const t = e.target;
    if (!(t instanceof HTMLElement)) return;
    if (t === document.body || t === renderer.domElement) return;
    // A panel/UI element gained focus: stop any in-flight movement and release
    // pointer lock so the panel is usable. Even though the input feature keeps
    // its own flag/held set, clearing it via window keyup stops the player.
    releaseMoveKeys();
  }

  window.addEventListener('resize', onResize);
  renderer.domElement.addEventListener('wheel', onWheel, { passive: false });
  renderer.domElement.addEventListener('mousedown', onMouseDown);
  window.addEventListener('mouseup', onMouseUp);
  renderer.domElement.addEventListener('click', onCanvasClick);
  window.addEventListener('keydown', onModeKey);
  window.addEventListener('mousemove', onLook);
  document.addEventListener('pointerlockchange', onPointerLockChange);
  document.addEventListener('pointerlockerror', onPointerLockError);
  document.addEventListener('focusin', onFocusIn);

  function dispose(): void {
    if (disposed) return;
    disposed = true;
    window.removeEventListener('resize', onResize);
    renderer.domElement.removeEventListener('wheel', onWheel);
    renderer.domElement.removeEventListener('mousedown', onMouseDown);
    window.removeEventListener('mouseup', onMouseUp);
    renderer.domElement.removeEventListener('click', onCanvasClick);
    window.removeEventListener('keydown', onModeKey);
    window.removeEventListener('mousemove', onLook);
    document.removeEventListener('pointerlockchange', onPointerLockChange);
    document.removeEventListener('pointerlockerror', onPointerLockError);
    document.removeEventListener('focusin', onFocusIn);
    cameraHint.remove();
    crosshair.el.remove();
    offWarp();
    offUsed();
    offFail();
    offMode();
    offCast();
    offBite();
    offHide();
    offEscape();
    offCancel();
    offNoFish();
    clearDevHandle();
    scene.remove(bobber);
    bobber.geometry.dispose();
    bobberMat.dispose();
    for (const p of particles) {
      fxLayer.remove(p.mesh);
      (p.mesh.material as THREE.Material).dispose();
    }
    particles.length = 0;
    fragGeo.dispose();
    scene.remove(fxLayer);
    camera.remove(handGroup);
    handGroup.traverse((node) => {
      if (node instanceof THREE.Mesh) {
        node.geometry.dispose();
        (node.material as THREE.Material).dispose();
      }
    });
    disposePrecip();
    disposedPlaced();
    npcView.dispose();
    disposeTerrain(terrain);
    terrain = null;
    disposeGroup(groundLayer);
    disposeGroup(voxelGroup);
    for (const mat of Object.values(VOXEL_MATERIALS)) mat.dispose();
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
    highlight.traverse((node) => {
      if (node instanceof THREE.Mesh || node instanceof THREE.LineSegments) {
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

  // The first-person camera is the DEFAULT presentation. Apply it once now that
  // the layers exist so the very first frame is eye-level.
  setCameraMode('first');

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

// Keep a reference so block registry materials are constructed once at module
// import in a browser; in headless this is a no-op that returns a cached map.
export function viewBlockRegistry(): ReturnType<typeof blockRegistry> {
  return blockRegistry();
}

/** Resolve a BlockKind definition (re-export for tests + view consumers). */
export { getBlock };
