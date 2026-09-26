/**
 * textures.ts — procedural 16x16 pixel-art block textures (WORKER-1, lane
 * 'world'). No external image files: every texture is painted at runtime on an
 * HTMLCanvasElement and wrapped in a THREE.CanvasTexture with NearestFilter so
 * the world reads as Minecraft-style blocky pixel art.
 *
 * Determinism: each texture is painted by a seeded PRNG derived from the
 * texture key, so a given block always generates the SAME pixels — no per-frame
 * flicker. A tiny 2-4 tone noise pass varies pixels within a block, which is
 * what sells the "Minecraft" look more than anything else.
 *
 * The pixel source of truth is a Uint8ClampedArray (16x16 RGBA). In a browser
 * that array is uploaded to a real canvas and wrapped in a CanvasTexture; in a
 * headless test (no DOM) the identical CanvasTexture is built over a
 * width/height stub so the registry and filter settings stay testable.
 */
import * as THREE from 'three';

/** Every block texture is a 16x16 pixel-art tile (the Minecraft default). */
export const TEX_SIZE = 16;

/** Deterministic 32-bit hash used to seed each texture's PRNG from its key. */
function keySeed(key: string): number {
  let h = 2166136261;
  for (let i = 0; i < key.length; i++) {
    h ^= key.charCodeAt(i);
    h = Math.imul(h, 16777619);
  }
  return h >>> 0;
}

/** Mulberry32-style tiny seeded PRNG (deterministic per key). */
function seeded(seed: number): () => number {
  let s = seed >>> 0;
  return () => {
    s = (s + 0x6d2b79f5) >>> 0;
    let t = s;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

/** A mutable 16x16 RGBA pixel buffer with tiny painting helpers. */
class Pixels {
  readonly size = TEX_SIZE;
  readonly data = new Uint8ClampedArray(TEX_SIZE * TEX_SIZE * 4);

  set(x: number, y: number, r: number, g: number, b: number, a = 255): void {
    if (x < 0 || y < 0 || x >= TEX_SIZE || y >= TEX_SIZE) return;
    const i = (y * TEX_SIZE + x) * 4;
    this.data[i] = r;
    this.data[i + 1] = g;
    this.data[i + 2] = b;
    this.data[i + 3] = a;
  }

  fill(r: number, g: number, b: number, a = 255): void {
    for (let y = 0; y < TEX_SIZE; y++) for (let x = 0; x < TEX_SIZE; x++) this.set(x, y, r, g, b, a);
  }

  get(x: number, y: number): [number, number, number, number] {
    const cx = (x + TEX_SIZE) % TEX_SIZE;
    const cy = (y + TEX_SIZE) % TEX_SIZE;
    const i = (cy * TEX_SIZE + cx) * 4;
    return [this.data[i] ?? 0, this.data[i + 1] ?? 0, this.data[i + 2] ?? 0, this.data[i + 3] ?? 0];
  }

  /** Multiply the brightness of an existing pixel (tone variation). */
  shade(x: number, y: number, factor: number): void {
    const [r, g, b, a] = this.get(x, y);
    this.set(x, y, r * factor, g * factor, b * factor, a);
  }
}

type Painter = (p: Pixels, rnd: () => number) => void;

// --- Colour helpers -------------------------------------------------------

function hex(value: number): [number, number, number] {
  return [(value >> 16) & 255, (value >> 8) & 255, value & 255];
}

function noiseShade(p: Pixels, rnd: () => number, tones: readonly number[], weights?: readonly number[]): void {
  // Weighted per-pixel brightness tone — the core "not flat colour" pass.
  for (let y = 0; y < p.size; y++) {
    for (let x = 0; x < p.size; x++) {
      const r = rnd();
      let tone = tones[0] ?? 1;
      if (weights) {
        let acc = 0;
        const roll = rnd();
        for (let i = 0; i < tones.length; i++) {
          acc += weights[i] ?? 0;
          if (roll <= acc) {
            tone = tones[i] ?? 1;
            break;
          }
        }
      } else {
        tone = tones[Math.floor(r * tones.length)] ?? 1;
      }
      p.shade(x, y, tone);
    }
  }
}

function speckle(p: Pixels, rnd: () => number, count: number, r: number, g: number, b: number): void {
  for (let i = 0; i < count; i++) {
    const x = Math.floor(rnd() * p.size);
    const y = Math.floor(rnd() * p.size);
    p.set(x, y, r, g, b);
  }
}

// --- Block painters -------------------------------------------------------

/** Grass top: dense green with 2-4 tone noise. */
function paintGrassTop(p: Pixels, rnd: () => number): void {
  const [r, g, b] = hex(0x61913d);
  p.fill(r, g, b);
  noiseShade(p, rnd, [0.86, 0.94, 1.0, 1.08], [0.28, 0.34, 0.24, 0.14]);
  speckle(p, rnd, 10, r * 0.82, g * 0.85, b * 0.8);
}

/** Grass side: dirt body with a green lip along the top rows. */
function paintGrassSide(p: Pixels, rnd: () => number): void {
  const [dr, dg, db] = hex(0x7a5637);
  const [gr, gg, gb] = hex(0x61913d);
  for (let y = 0; y < p.size; y++) {
    for (let x = 0; x < p.size; x++) {
      if (y < 3 + (rnd() < 0.5 ? 1 : 0)) p.set(x, y, gr, gg, gb);
      else p.set(x, y, dr, dg, db);
    }
  }
  noiseShade(p, rnd, [0.88, 0.96, 1.04, 1.1], [0.3, 0.34, 0.22, 0.14]);
  // A couple of grass blades dangling below the lip.
  for (let i = 0; i < 5; i++) {
    const x = Math.floor(rnd() * p.size);
    const y = 3 + Math.floor(rnd() * 2);
    p.set(x, y, gr * 0.9, gg * 0.9, gb * 0.9);
  }
}

/** Plain dirt. */
function paintDirt(p: Pixels, rnd: () => number): void {
  const [r, g, b] = hex(0x7a5637);
  p.fill(r, g, b);
  noiseShade(p, rnd, [0.84, 0.92, 1.0, 1.1], [0.3, 0.32, 0.24, 0.14]);
  speckle(p, rnd, 8, r * 0.78, g * 0.78, b * 0.78);
}

/** Tilled soil: darker damp dirt with cross furrow grooves. */
function paintFarmland(p: Pixels, rnd: () => number): void {
  const [r, g, b] = hex(0x5b4028);
  p.fill(r, g, b);
  noiseShade(p, rnd, [0.86, 0.95, 1.04, 1.12], [0.3, 0.32, 0.24, 0.14]);
  // Horizontal furrows: alternate darker grooves.
  for (let y = 1; y < p.size; y += 3) {
    for (let x = 0; x < p.size; x++) p.shade(x, y, 0.78);
  }
  for (let y = 2; y < p.size; y += 3) {
    for (let x = 0; x < p.size; x++) p.shade(x, y, 1.1);
  }
  speckle(p, rnd, 6, r * 0.7, g * 0.7, b * 0.7);
}

/** Stone: cool grey mottled. */
function paintStone(p: Pixels, rnd: () => number): void {
  const [r, g, b] = hex(0x8a8f96);
  p.fill(r, g, b);
  noiseShade(p, rnd, [0.86, 0.94, 1.02, 1.08], [0.3, 0.32, 0.24, 0.14]);
  speckle(p, rnd, 12, r * 0.86, g * 0.86, b * 0.86);
}

/** Cobblestone: chunky stone bricks with mortar lines. */
function paintCobblestone(p: Pixels, rnd: () => number): void {
  const [r, g, b] = hex(0x7f848a);
  p.fill(r * 0.8, g * 0.8, b * 0.8); // mortar
  noiseShade(p, rnd, [0.95, 1.0, 1.05], [0.4, 0.4, 0.2]);
  // Irregular cobbles in a loose grid.
  const cells: Array<[number, number]> = [];
  for (let gy = 0; gy < 4; gy++) for (let gx = 0; gx < 4; gx++) cells.push([gx * 4, gy * 4]);
  for (const [ox, oy] of cells) {
    const jitterX = Math.floor(rnd() * 2);
    const jitterY = Math.floor(rnd() * 2);
    const tone = 0.9 + rnd() * 0.18;
    for (let y = 0; y < 3; y++) {
      for (let x = 0; x < 3; x++) {
        const px = ox + x + jitterX;
        const py = oy + y + jitterY;
        p.set(px, py, r * tone, g * tone, b * tone);
      }
    }
  }
}

/** Sand: pale warm grains. */
function paintSand(p: Pixels, rnd: () => number): void {
  const [r, g, b] = hex(0xcfbd93);
  p.fill(r, g, b);
  noiseShade(p, rnd, [0.9, 0.96, 1.02, 1.06], [0.3, 0.34, 0.24, 0.12]);
  speckle(p, rnd, 14, r * 0.9, g * 0.9, b * 0.84);
}

/** Path / gravel: mixed small stones on dirt. */
function paintPath(p: Pixels, rnd: () => number): void {
  const [dr, dg, db] = hex(0x8a7350);
  p.fill(dr, dg, db);
  noiseShade(p, rnd, [0.88, 0.95, 1.02, 1.08], [0.3, 0.32, 0.24, 0.14]);
  for (let i = 0; i < 10; i++) {
    const x = Math.floor(rnd() * p.size);
    const y = Math.floor(rnd() * p.size);
    const tone = 1.1 + rnd() * 0.12;
    p.set(x, y, dr * tone, dg * tone, db * tone);
    p.set((x + 1) % p.size, y, dr * tone, dg * tone, db * tone);
  }
}

/** Oak log side: vertical bark strips. */
function paintLogSide(p: Pixels, rnd: () => number): void {
  const [r, g, b] = hex(0x6b4a2f);
  p.fill(r, g, b);
  for (let x = 0; x < p.size; x++) {
    const tone = 0.86 + 0.28 * ((x * 7919) % 3) / 2;
    for (let y = 0; y < p.size; y++) p.shade(x, y, tone);
  }
  noiseShade(p, rnd, [0.92, 1.0, 1.06], [0.4, 0.4, 0.2]);
  for (let i = 0; i < 4; i++) {
    const x = Math.floor(rnd() * p.size);
    const y0 = Math.floor(rnd() * p.size);
    for (let y = 0; y < 5; y++) p.set(x, (y0 + y) % p.size, r * 0.74, g * 0.74, b * 0.74);
  }
}

/** Oak log top: concentric rings. */
function paintLogTop(p: Pixels, rnd: () => number): void {
  const [r, g, b] = hex(0x8a6440);
  const cx = 7.5;
  const cy = 7.5;
  for (let y = 0; y < p.size; y++) {
    for (let x = 0; x < p.size; x++) {
      const d = Math.hypot(x - cx, y - cy);
      const ring = Math.sin(d * 1.9) * 0.5 + 0.5;
      const tone = 0.82 + ring * 0.24;
      p.set(x, y, r * tone, g * tone, b * tone);
    }
  }
  noiseShade(p, rnd, [0.94, 1.0, 1.05], [0.4, 0.4, 0.2]);
  speckle(p, rnd, 5, r * 0.8, g * 0.8, b * 0.8);
}

/** Oak planks: horizontal boards with seams. */
function paintPlanks(p: Pixels, rnd: () => number): void {
  const [r, g, b] = hex(0x9a6a3e);
  p.fill(r, g, b);
  for (let y = 0; y < p.size; y++) {
    for (let x = 0; x < p.size; x++) {
      const board = Math.floor(y / 4);
      const tone = 0.9 + 0.16 * (((board * 2654435761) % 3) / 2);
      p.shade(x, y, tone);
    }
  }
  for (let y = 3; y < p.size; y += 4) {
    for (let x = 0; x < p.size; x++) p.set(x, y, r * 0.7, g * 0.7, b * 0.7);
  }
  noiseShade(p, rnd, [0.94, 1.0, 1.05], [0.4, 0.4, 0.2]);
  // plank end nails/grain
  for (let i = 0; i < 4; i++) {
    const x = Math.floor(rnd() * p.size);
    const y = Math.floor(rnd() * p.size);
    p.set(x, y, r * 0.8, g * 0.8, b * 0.8);
  }
}

/** Oak leaves: dense clumps with holes (Minecraft-ish alpha-free green). */
function paintLeaves(p: Pixels, rnd: () => number): void {
  const [r, g, b] = hex(0x4a6b31);
  p.fill(r, g, b);
  noiseShade(p, rnd, [0.78, 0.88, 0.98, 1.1], [0.26, 0.32, 0.26, 0.16]);
  for (let i = 0; i < 14; i++) {
    const x = Math.floor(rnd() * p.size);
    const y = Math.floor(rnd() * p.size);
    p.set(x, y, r * 0.7, g * 0.78, b * 0.7);
  }
  for (let i = 0; i < 6; i++) {
    const x = Math.floor(rnd() * p.size);
    const y = Math.floor(rnd() * p.size);
    p.set(x, y, r * 1.18, g * 1.18, b * 1.1);
  }
}

/** Water: soft blue with a wave pattern. */
function paintWater(p: Pixels, rnd: () => number): void {
  const [r, g, b] = hex(0x2f6f8f);
  p.fill(r, g, b);
  for (let y = 0; y < p.size; y++) {
    for (let x = 0; x < p.size; x++) {
      const wave = Math.sin((x + y * 0.6) * 0.9) * 0.5 + 0.5;
      p.shade(x, y, 0.9 + wave * 0.2);
    }
  }
  noiseShade(p, rnd, [0.94, 1.0, 1.06], [0.4, 0.4, 0.2]);
  for (let i = 0; i < 5; i++) {
    const x = Math.floor(rnd() * p.size);
    const y = Math.floor(rnd() * p.size);
    p.set(x, y, r * 1.2, g * 1.2, b * 1.25);
  }
}

/** Brick: red bricks with light mortar. */
function paintBrick(p: Pixels, rnd: () => number): void {
  const [r, g, b] = hex(0x9c4a34);
  const mortar = 0.78;
  for (let y = 0; y < p.size; y++) {
    for (let x = 0; x < p.size; x++) {
      const row = Math.floor(y / 4);
      const offset = row % 2 === 0 ? 0 : 4;
      const isMortar = y % 4 === 3 || (x + offset) % 8 === 7;
      const tone = 0.9 + 0.2 * (((x * 31 + y * 17) % 5) / 4);
      if (isMortar) p.set(x, y, r * mortar, g * mortar, b * mortar);
      else p.set(x, y, r * tone, g * tone, b * tone);
    }
  }
  noiseShade(p, rnd, [0.94, 1.0, 1.05], [0.4, 0.4, 0.2]);
  void rnd;
}

/** Glass: mostly transparent with a bright frame and a highlight streak. */
function paintGlass(p: Pixels, rnd: () => number): void {
  const [r, g, b] = hex(0xcfe3e8);
  p.fill(r, g, b, 0);
  for (let x = 0; x < p.size; x++) {
    p.set(x, 0, r, g, b, 200);
    p.set(x, p.size - 1, r, g, b, 200);
  }
  for (let y = 0; y < p.size; y++) {
    p.set(0, y, r, g, b, 200);
    p.set(p.size - 1, y, r, g, b, 200);
  }
  for (let i = 0; i < 4; i++) {
    p.set(3 + i, 11 - i, 255, 255, 255, 120);
    p.set(4 + i, 11 - i, 255, 255, 255, 120);
  }
  void rnd;
}

/** Ore stone: a stone base with coloured ore blobs. */
function paintOre(base: number, ore: number): Painter {
  return (p, rnd) => {
    const [br, bg, bb] = hex(base);
    const [or, og, ob] = hex(ore);
    p.fill(br, bg, bb);
    noiseShade(p, rnd, [0.86, 0.94, 1.02, 1.08], [0.3, 0.32, 0.24, 0.14]);
    const blobs = 4 + Math.floor(rnd() * 3);
    for (let i = 0; i < blobs; i++) {
      const bx = 1 + Math.floor(rnd() * (p.size - 3));
      const by = 1 + Math.floor(rnd() * (p.size - 3));
      const s = 1 + Math.floor(rnd() * 2);
      for (let y = 0; y <= s; y++) {
        for (let x = 0; x <= s; x++) p.set(bx + x, by + y, or, og, ob);
      }
    }
  };
}

/** Per-crop leafy stem: green stem with leaf blocks for a given crop colour. */
function makeCropPainter(foliage: number, accent: number): Painter {
  return (p, rnd) => {
    const [fr, fg, fb] = hex(foliage);
    const [ar, ag, ab] = hex(accent);
    p.fill(0, 0, 0, 0);
    // central stem column
    for (let y = 3; y < p.size; y++) {
      p.set(7, y, fr * 0.7, fg * 0.7, fb * 0.7);
      p.set(8, y, fr * 0.7, fg * 0.7, fb * 0.7);
    }
    // leaf blocks alternating sides
    for (let y = 4; y < p.size - 2; y += 3) {
      for (let x = 2; x < 6; x++) p.set(x, y, fr, fg, fb);
      for (let x = 10; x < 14; x++) p.set(x, y, fr, fg, fb);
    }
    // accent fruit/flower near the top
    for (let y = 2; y < 5; y++) {
      for (let x = 6; x < 10; x++) p.set(x, y, ar, ag, ab);
    }
    noiseShade(p, rnd, [0.88, 0.96, 1.04, 1.1], [0.3, 0.32, 0.24, 0.14]);
  };
}

// --- Texture keys ---------------------------------------------------------

export type TextureKey =
  | 'grass_top'
  | 'grass_side'
  | 'dirt'
  | 'farmland'
  | 'stone'
  | 'cobblestone'
  | 'sand'
  | 'path'
  | 'log_side'
  | 'log_top'
  | 'planks'
  | 'leaves'
  | 'water'
  | 'brick'
  | 'glass'
  | 'ore_coal'
  | 'ore_iron'
  | 'ore_gold'
  | 'ore_copper'
  | 'crop_leaf_default'
  | 'crop_stem_default';

/** Per-crop-colour leaf/stem keys: `<colour>_leaf` / `<colour>_stem`. */
export type CropTextureKey = `${string}_leaf` | `${string}_stem`;

/** Ore stone variants keyed by mineral. */
export const ORE_TEXTURE_KEYS: Record<string, TextureKey> = {
  coal: 'ore_coal',
  iron: 'ore_iron',
  gold: 'ore_gold',
  copper: 'ore_copper',
};

const PAINTERS: Record<string, Painter> = {
  grass_top: paintGrassTop,
  grass_side: paintGrassSide,
  dirt: paintDirt,
  farmland: paintFarmland,
  stone: paintStone,
  cobblestone: paintCobblestone,
  sand: paintSand,
  path: paintPath,
  log_side: paintLogSide,
  log_top: paintLogTop,
  planks: paintPlanks,
  leaves: paintLeaves,
  water: paintWater,
  brick: paintBrick,
  glass: paintGlass,
  ore_coal: paintOre(0x8a8f96, 0x2a2a2a),
  ore_iron: paintOre(0x8a8f96, 0xd8af93),
  ore_gold: paintOre(0x8a8f96, 0xf2d13c),
  ore_copper: paintOre(0x8a8f96, 0xd2793a),
};

/** Crop colour table: cropId -> { foliage, accent }. */
export const CROP_COLOURS: Record<string, { foliage: number; accent: number }> = {
  parsnip: { foliage: 0x5aa03a, accent: 0xf0e6a0 },
  potato: { foliage: 0x4d8a34, accent: 0xc9a06a },
  garlic: { foliage: 0x6fb04a, accent: 0xf2f0e0 },
  cauliflower: { foliage: 0x53a044, accent: 0xf2f0e0 },
  strawberry: { foliage: 0x3f8a34, accent: 0xd4413f },
  'green-bean': { foliage: 0x4f9a34, accent: 0x7fc44f },
  blueberry: { foliage: 0x3d7a52, accent: 0x4a5fc4 },
  tomato: { foliage: 0x3f8a30, accent: 0xd44a2a },
  'hot-pepper': { foliage: 0x3d8a30, accent: 0xe04020 },
};

// --- Texture construction ------------------------------------------------

function painterFor(key: string): Painter {
  if (PAINTERS[key]) return PAINTERS[key]!;
  if (key.endsWith('_leaf')) {
    const colour = key.slice(0, -5);
    const spec = CROP_COLOURS[colour] ?? { foliage: 0x5aa03a, accent: 0xf0e6a0 };
    return makeCropPainter(spec.foliage, spec.accent);
  }
  if (key.endsWith('_stem')) {
    const colour = key.slice(0, -5);
    const spec = CROP_COLOURS[colour] ?? { foliage: 0x4a7a2e, accent: 0x6a9a3a };
    return makeCropPainter(spec.foliage * 0.8 | 0, spec.accent);
  }
  return paintDirt; // safe fallback
}

/**
 * Paint a texture key into a fresh 16x16 RGBA pixel buffer. Pure and
 * deterministic: same key -> same bytes, every time.
 */
export function paintTexture(key: string): Uint8ClampedArray {
  const painter = painterFor(key);
  const p = new Pixels();
  painter(p, seeded(keySeed(key)));
  return p.data;
}

/** Wrap a 16x16 pixel buffer in a CanvasTexture (NearestFilter, no mipmaps). */
function toCanvasTexture(pixels: Uint8ClampedArray, key: string): THREE.CanvasTexture {
  let image: HTMLCanvasElement | { width: number; height: number };
  if (typeof document !== 'undefined' && typeof document.createElement === 'function') {
    const canvas = document.createElement('canvas');
    canvas.width = TEX_SIZE;
    canvas.height = TEX_SIZE;
    const ctx = canvas.getContext('2d');
    if (ctx) {
      const img = new ImageData(new Uint8ClampedArray(pixels), TEX_SIZE, TEX_SIZE);
      ctx.putImageData(img, 0, 0);
    }
    image = canvas;
  } else {
    // Headless: same CanvasTexture semantics, minimal image stub.
    image = { width: TEX_SIZE, height: TEX_SIZE };
  }
  const tex = new THREE.CanvasTexture(image as HTMLCanvasElement);
  tex.magFilter = THREE.NearestFilter;
  tex.minFilter = THREE.NearestFilter;
  tex.generateMipmaps = false;
  tex.wrapS = THREE.RepeatWrapping;
  tex.wrapT = THREE.RepeatWrapping;
  tex.colorSpace = THREE.SRGBColorSpace;
  tex.name = key;
  tex.needsUpdate = true;
  return tex;
}

// --- Cached texture set ---------------------------------------------------

export type BlockTextureSet = Readonly<Record<string, THREE.CanvasTexture>>;

let cachedSet: BlockTextureSet | null = null;

/** All texture keys the game uses (base blocks + ores + per-crop sets). */
export function allTextureKeys(): string[] {
  const keys = Object.keys(PAINTERS);
  for (const colour of Object.keys(CROP_COLOURS)) {
    keys.push(`${colour}_leaf`, `${colour}_stem`);
  }
  keys.push('crop_leaf_default', 'crop_stem_default');
  return keys;
}

/**
 * Build (once) and cache the full block texture set, keyed by texture key.
 * Never rebuilt per frame. Returns the same object on every call.
 */
export function blockTextureSet(): BlockTextureSet {
  if (cachedSet) return cachedSet;
  const out: Record<string, THREE.CanvasTexture> = {};
  for (const key of allTextureKeys()) {
    out[key] = toCanvasTexture(paintTexture(key), key);
  }
  cachedSet = out;
  return cachedSet;
}

/** Fetch a single cached texture by key (builds the set on first use). */
export function blockTexture(key: string): THREE.CanvasTexture {
  const set = blockTextureSet();
  const found = set[key];
  if (found) return found;
  return toCanvasTexture(paintTexture(key), key);
}

/** Resolve a cropId (or colour token) to its leaf/stem texture keys. */
export function cropTextureKeys(cropId: string): { leaf: string; stem: string } {
  const colour = cropId in CROP_COLOURS ? cropId : 'default';
  return { leaf: `${colour}_leaf`, stem: `${colour}_stem` };
}

/** Release cached GPU textures (called on engine dispose). */
export function disposeBlockTextures(): void {
  if (!cachedSet) return;
  for (const tex of Object.values(cachedSet)) tex.dispose();
  cachedSet = null;
}
