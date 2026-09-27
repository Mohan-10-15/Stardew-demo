/**
 * First-person coherence + palette probe.
 *
 * Two questions the earlier runs could not answer:
 *  1. In first person, does the camera actually turn when the player turns?
 *     If the yaw only gets set when first person is entered, WASD moves you
 *     one way while the camera stares another - which reads as "broken".
 *  2. What is actually on screen? (toDataURL on a WebGL canvas returns black
 *     without preserveDrawingBuffer, so the palette has to come from a
 *     compositor screenshot instead.)
 */
import { canvasStats, holdAndSample, observe, regionColor, sceneMetrics, shot } from './observe-lib.ts';

const o = await observe();
const { page } = o;
if (!o.booted) {
  console.log('boot failed');
  for (const l of o.console) console.log(` [${l.type}] ${l.text}`);
  await o.close();
  process.exit(1);
}

/** Raw camera facing, compared numerically against the world direction the
 *  current sim `facing` implies. Convention (voxel.ts lookVector/yawOfFacing):
 *  facing 'down' -> +z, 'up' -> -z, 'right' -> +x, 'left' -> -x. */
function camState() {
  return page.evaluate(() => {
    const w = window as unknown as {
      __EH_SCENE__?: { camera: { rotation: { x: number; y: number; z: number }; matrixWorld: { elements: number[] } } };
      __EH__?: { store: { state: { player: { facing: string } } } };
    };
    const h = w.__EH_SCENE__;
    if (!h) return null;
    const cam = h.camera;
    // A camera looks down its local -Z = negated third column of the
    // column-major world matrix. No THREE import needed in page context.
    const e = cam.matrixWorld.elements;
    // Horizontal part of the look direction. The camera is pitched down by
    // PITCH_DEFAULT, so |(dirX,dirZ)| == cos(pitch) ~= 0.878, not 1. Normalise
    // before comparing, or every reading looks misaligned by ~28 degrees.
    const rawX = -e[8]!;
    const rawZ = -e[10]!;
    const mag = Math.hypot(rawX, rawZ) || 1;
    const dirX = rawX / mag;
    const dirZ = rawZ / mag;
    const facing = w.__EH__!.store.state.player.facing;
    const expected = { up: [0, -1], down: [0, 1], left: [-1, 0], right: [1, 0] }[facing] ?? [0, 0];
    return {
      rotY: cam.rotation.y,
      rotX: cam.rotation.x,
      dirX,
      dirZ,
      facing,
      expX: expected[0]!,
      expZ: expected[1]!,
      // +1 = camera looks exactly where the player faces, -1 = opposite.
      dot: Number((dirX * expected[0]! + dirZ * expected[1]!).toFixed(3)),
    };
  });
}

function report(label: string, c: Awaited<ReturnType<typeof camState>>): void {
  if (!c) {
    console.log(`  ${label}: no camera`);
    return;
  }
  console.log(
    `  ${label.padEnd(22)} facing=${c.facing.padEnd(5)} camDir=(${c.dirX.toFixed(2)}, ${c.dirZ.toFixed(2)})  expected=(${c.expX}, ${c.expZ})  dot=${c.dot}  pitch=${(c.rotX * 57.3).toFixed(1)}deg  ${c.dot > 0.9 ? 'AGREES' : c.dot < -0.9 ? '*** OPPOSITE ***' : 'off-cardinal (free look)'}`,
  );
}

/** Where the reticle actually is, and whether it is on screen. The reticle is
 *  parked on the projected interaction target, so this is the direct check
 *  that "what you see is what you hit". */
function reticle() {
  return page.evaluate(() => {
    const el = document.getElementById('eh-crosshair');
    if (!el) return { present: false, visible: false, x: 0, y: 0, offCentre: 0 };
    const r = el.getBoundingClientRect();
    return {
      present: true,
      visible: el.style.display !== 'none' && r.width > 0,
      x: Math.round(r.left + r.width / 2),
      y: Math.round(r.top + r.height / 2),
      offCentre: Math.round(Math.hypot(r.left + r.width / 2 - innerWidth / 2, r.top + r.height / 2 - innerHeight / 2)),
    };
  });
}

/** Top colours actually on screen. A Playwright element screenshot captures the
 *  compositor, so this sees the real frame even though the WebGL context has
 *  preserveDrawingBuffer:false (which is why canvas.toDataURL reads black). */
async function topPalette(levels = 4, top = 8) {
  const buf = await page.locator('#game-root canvas').screenshot();
  return page.evaluate(
    async ({ b64, levels, top }) => {
      const blob = await fetch(`data:image/png;base64,${b64}`).then((r) => r.blob());
      const bmp = await createImageBitmap(blob);
      const cv = new OffscreenCanvas(bmp.width, bmp.height);
      const g = cv.getContext('2d');
      if (!g) throw new Error('no 2d canvas');
      g.drawImage(bmp, 0, 0);
      const { data } = g.getImageData(0, 0, bmp.width, bmp.height);
      const counts = new Map<number, { n: number; r: number; gg: number; b: number }>();
      const n = bmp.width * bmp.height;
      const shift = 8 - levels;
      for (let i = 0; i < n; i++) {
        const R = data[i * 4] ?? 0;
        const G = data[i * 4 + 1] ?? 0;
        const B = data[i * 4 + 2] ?? 0;
        const key = ((R >> shift) << (levels * 2)) | ((G >> shift) << levels) | (B >> shift);
        const e = counts.get(key);
        if (e) {
          e.n++;
          e.r += R;
          e.gg += G;
          e.b += B;
        } else counts.set(key, { n: 1, r: R, gg: G, b: B });
      }
      return [...counts.values()]
        .sort((a, b) => b.n - a.n)
        .slice(0, top)
        .map((e) => ({
          rgb: [Math.round(e.r / e.n), Math.round(e.gg / e.n), Math.round(e.b / e.n)],
          pct: Math.round((e.n / n) * 1000) / 10,
        }));
    },
    { b64: buf.toString('base64'), levels, top },
  );
}

console.log('=== FIRST-PERSON CAMERA COHERENCE (real Chromium) ===');
console.log('renderer:', await page.evaluate(() => {
  const gl = (document.querySelector('#game-root canvas') as HTMLCanvasElement).getContext('webgl2');
  const ext = gl?.getExtension('WEBGL_debug_renderer_info');
  return gl && ext ? String(gl.getParameter(ext.UNMASKED_RENDERER_WEBGL)) : 'unknown';
}));
console.log('metrics:', JSON.stringify(await sceneMetrics(page)));
const start = await camState();
report('boot', start);

console.log('\n-- turn with each direction key, NO canvas click, NO pointer lock --');
for (const key of ['w', 'd', 's', 'a'] as const) {
  await holdAndSample(page, [key], 700);
  report(`press ${key}`, await camState());
}

console.log('\n-- drag to look with no pointer lock --');
const preDrag = await camState();
await page.mouse.move(640, 400);
await page.mouse.down();
for (let i = 1; i <= 12; i++) await page.mouse.move(640 - i * 25, 400);
await page.mouse.up();
await page.waitForTimeout(250);
const postDrag = await camState();
report('after drag', postDrag);
if (preDrag && postDrag) {
  const moved = Math.abs(Math.atan2(Math.sin(postDrag.rotY - preDrag.rotY), Math.cos(postDrag.rotY - preDrag.rotY)));
  console.log(`  yaw moved ${(moved * 57.3).toFixed(1)} deg; camera==facing: ${postDrag.dot > 0.9 ? 'YES' : 'NO'}`);
}

console.log('\n-- reticle is on the interaction target --');
const r = await reticle();
console.log(`  present=${r.present} visible=${r.visible} at (${r.x}, ${r.y}) ${r.offCentre}px from screen centre`);
console.log('  reticle pixel colour:', JSON.stringify(await regionColor(page, r.x - 6, r.y - 6, 12, 12)));
console.log('  canvas stats:', JSON.stringify(await canvasStats(page)));

console.log('\n=== PALETTE (compositor screenshot, quantised to 4 bits/channel) ===');
for (const c of await topPalette()) console.log(`  rgb(${c.rgb.join(',')})  ${c.pct}% of the frame`);
await shot(page, 'artifacts/coherence-firstperson.png');

console.log('\n=== VIEW TOGGLE (V) ===');
await page.keyboard.press('v');
await page.waitForTimeout(500);
console.log('  after V:', JSON.stringify(await sceneMetrics(page)));
console.log('  reticle hidden in top-down:', (await reticle()).visible === false ? 'YES' : 'NO');
console.log('  top-down palette top 3:', JSON.stringify((await topPalette(4, 3)).map((c) => `rgb(${c.rgb.join(',')}) ${c.pct}%`)));
await shot(page, 'artifacts/coherence-topdown.png');
await page.keyboard.press('v');
await page.waitForTimeout(500);
console.log('  after V again:', JSON.stringify(await sceneMetrics(page)));

console.log('\nconsole errors:', o.errors.length);
for (const e of o.errors.slice(0, 8)) console.log(`  [${e.type}] ${e.text}`);
await o.close();
