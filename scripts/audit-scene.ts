/**
 * Performance + scene audit. Answers the questions that decide whether the
 * voxel world is viable: how heavy is the scene graph, how many draw calls,
 * and what is the actual frame time in this browser.
 */
import { observe, shot } from './observe-lib.ts';

const o = await observe();
const { page } = o;
if (!o.booted) {
  console.log('boot failed');
  for (const l of o.console) console.log(` [${l.type}] ${l.text}`);
  await o.close();
  process.exit(1);
}

const audit = await page.evaluate(() => {
  const h = (window as unknown as {
    __EH_SCENE__?: { scene: unknown; renderer: unknown; camera: unknown };
  }).__EH_SCENE__;
  if (!h) return null;
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const scene = h.scene as any;
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const renderer = h.renderer as any;

  let meshes = 0;
  let instanced = 0;
  let points = 0;
  let lights = 0;
  const geometryKinds = new Map<string, number>();
  const materialNames = new Set<string>();
  let flatShaded = 0;
  let nonFlat = 0;
  let textured = 0;
  let untextured = 0;
  const texSizes = new Set<string>();
  const nearestFiltered = new Set<boolean>();

  scene.traverse((node: { isMesh?: boolean; isInstancedMesh?: boolean; isPoints?: boolean; isLight?: boolean; geometry?: { type?: string; parameters?: Record<string, unknown> }; material?: unknown }) => {
    if (node.isLight) lights++;
    if (node.isPoints) points++;
    if (!node.isMesh && !node.isInstancedMesh) return;
    if (node.isInstancedMesh) instanced++;
    else meshes++;
    const g = node.geometry;
    if (g?.type) geometryKinds.set(g.type, (geometryKinds.get(g.type) ?? 0) + 1);
    const mats = Array.isArray(node.material) ? node.material : node.material ? [node.material] : [];
    for (const m of mats) {
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const mm = m as any;
      materialNames.add(mm.name ?? mm.type ?? 'unnamed');
      if (mm.flatShading === true) flatShaded++;
      else nonFlat++;
      if (mm.map) {
        textured++;
        const img = mm.map.image;
        texSizes.add(`${img?.width ?? '?'}x${img?.height ?? '?'}`);
        nearestFiltered.add(mm.map.magFilter === 1003 /* NearestFilter */);
      } else untextured++;
    }
  });

  const info = renderer.info;
  return {
    sceneChildren: scene.children.length,
    meshes,
    instanced,
    points,
    lights,
    drawCalls: info.render.calls,
    triangles: info.render.triangles,
    geometries: info.memory.geometries,
    textures: info.memory.textures,
    programs: info.programs?.length ?? 0,
    geometryKinds: Object.fromEntries(geometryKinds),
    materialCount: materialNames.size,
    flatShaded,
    nonFlat,
    textured,
    untextured,
    textureSizes: [...texSizes],
    nearestFilterUsed: [...nearestFiltered],
    pixelRatio: renderer.getPixelRatio(),
  };
});

console.log('=== SCENE AUDIT ===');
console.log(JSON.stringify(audit, null, 2));

// Frame time: measure real rAF deltas over a window.
const frames = await page.evaluate(
  () =>
    new Promise<{ count: number; meanMs: number; p95Ms: number; maxMs: number; fps: number }>((resolve) => {
      const deltas: number[] = [];
      let last = performance.now();
      const start = last;
      const tick = (now: number): void => {
        deltas.push(now - last);
        last = now;
        if (now - start < 4000) requestAnimationFrame(tick);
        else {
          deltas.sort((a, b) => a - b);
          const mean = deltas.reduce((a, b) => a + b, 0) / deltas.length;
          resolve({
            count: deltas.length,
            meanMs: Math.round(mean * 100) / 100,
            p95Ms: Math.round(deltas[Math.floor(deltas.length * 0.95)]! * 100) / 100,
            maxMs: Math.round(deltas[deltas.length - 1]! * 100) / 100,
            fps: Math.round((1000 / mean) * 10) / 10,
          });
        }
      };
      requestAnimationFrame(tick);
    }),
);
console.log('\n=== FRAME TIME (4s, software renderer) ===');
console.log(JSON.stringify(frames, null, 2));

// GPU / renderer identity, so we know whether we are on SwiftShader.
const gl = await page.evaluate(() => {
  const c = document.querySelector('#game-root canvas') as HTMLCanvasElement;
  const ctx = (c.getContext('webgl2') ?? c.getContext('webgl')) as WebGLRenderingContext | null;
  if (!ctx) return null;
  const dbg = ctx.getExtension('WEBGL_debug_renderer_info');
  return {
    vendor: dbg ? ctx.getParameter(dbg.UNMASKED_VENDOR_WEBGL) : ctx.getParameter(ctx.VENDOR),
    renderer: dbg ? ctx.getParameter(dbg.UNMASKED_RENDERER_WEBGL) : ctx.getParameter(ctx.RENDERER),
  };
});
console.log('\n=== GPU ===');
console.log(JSON.stringify(gl, null, 2));

// Palette histogram: is the screen dominated by Minecraft-ish block colours?
const palette = await page.evaluate(async () => {
  const c = document.querySelector('#game-root canvas') as HTMLCanvasElement;
  const url = c.toDataURL('image/png');
  const blob = await fetch(url).then((r) => r.blob());
  const bmp = await createImageBitmap(blob);
  const cv = new OffscreenCanvas(bmp.width, bmp.height);
  const g = cv.getContext('2d');
  if (!g) return null;
  g.drawImage(bmp, 0, 0);
  const { data } = g.getImageData(0, 0, bmp.width, bmp.height);
  const buckets = new Map<string, number>();
  const n = bmp.width * bmp.height;
  for (let i = 0; i < n; i++) {
    const R = (data[i * 4] ?? 0) >> 4;
    const G = (data[i * 4 + 1] ?? 0) >> 4;
    const B = (data[i * 4 + 2] ?? 0) >> 4;
    const key = `${R}${G}${B}`;
    buckets.set(key, (buckets.get(key) ?? 0) + 1);
  }
  const top = [...buckets.entries()].sort((a, b) => b[1] - a[1]).slice(0, 12);
  return {
    totalPixels: n,
    distinct12BitBuckets: buckets.size,
    top: top.map(([k, v]) => {
      const r = Number(k[0]) * 17;
      const gg = Number(k[1]) * 17;
      const b = Number(k[2]) * 17;
      return { rgb: [r, gg, b], pct: Math.round((v / n) * 1000) / 10 };
    }),
  };
});
console.log('\n=== PALETTE (top colours on screen) ===');
console.log(JSON.stringify(palette, null, 2));

await shot(page, 'artifacts/audit-frame.png');
console.log('\nconsole errors:', o.errors.length);
for (const e of o.errors.slice(0, 8)) console.log(`  [${e.type}] ${e.text}`);
await o.close();
