/**
 * T-0501 verification: boot the real game in a real Chromium and MEASURE the
 * Minecraft-look work. Prints observed numbers only — no assertions.
 *
 * Dev-only harness: it cross-references the DOM/global game handle with
 * structural `any` types on purpose (WebGL scene introspection).
 */
/* eslint-disable @typescript-eslint/no-explicit-any */
import { chromium, type Page } from 'playwright';

const URL = process.env['EH_URL'] ?? 'http://localhost:2026/';
const out: string[] = [];
const say = (s = ''): void => {
  out.push(s);
  console.log(s);
};

interface SceneReport {
  hasHandle: boolean;
  instancedMeshes: number;
  totalInstances: number;
  meshNames: string[];
  materialsWithMap: number;
  materialsTotal: number;
  nearestFiltered: number;
  texturedMaterials: number;
  flatShaded: number;
  cameraType: string;
  cameraY: number;
  cameraFov: number;
  playerVisible: boolean;
  playerParts: string[];
  armRFound: boolean;
  handVisible: boolean;
  lineSegments: number;
  treeBlockCount: number;
  highlightChildren: string[];
}

async function readScene(page: Page): Promise<SceneReport> {
  return page.evaluate(() => {
    const g = window as unknown as { __EH_SCENE__?: any };
    const h = g.__EH_SCENE__;
    if (!h) {
      return {
        hasHandle: false,
        instancedMeshes: 0,
        totalInstances: 0,
        meshNames: [],
        materialsWithMap: 0,
        materialsTotal: 0,
        nearestFiltered: 0,
        texturedMaterials: 0,
        flatShaded: 0,
        cameraType: 'none',
        cameraY: 0,
        cameraFov: 0,
        playerVisible: false,
        playerParts: [],
        armRFound: false,
        handVisible: false,
        lineSegments: 0,
        treeBlockCount: 0,
        highlightChildren: [],
      };
    }
    const scene = h.scene;
    const instanced: any[] = [];
    const allMats: any[] = [];
    const lines: any[] = [];
    let treeBlocks = 0;
    let playerVisible = false;
    let playerParts: string[] = [];
    let armRFound = false;
    let handVisible = false;
    const highlightChildren: string[] = [];
    scene.traverse((n: any) => {
      if (n.isInstancedMesh) instanced.push(n);
      if (n.isMesh || n.isLine || n.isLineSegments) {
        const m = n.material;
        if (Array.isArray(m)) allMats.push(...m);
        else if (m) allMats.push(m);
        if (n.isLineSegments) lines.push(n);
      }
      if (n.isGroup && n.name === 'npcs') return;
      if (n.isMesh && n.geometry?.type === 'BoxGeometry') {
        const p = n.parent;
        if (p && p.type === 'Group' && p.children.length > 20) treeBlocks++;
      }
      if (n.name === 'player-arm-r') armRFound = true;
      if (n.name === 'fp-hand-group') handVisible = n.visible === true;
      if (n.parent?.name === 'player-root' || n.name === 'player-torso') playerVisible = true;
    });
    // find the player root group (built by buildPlayer)
    scene.traverse((n: any) => {
      if (n.isGroup && n.children.some((c: any) => c.name === 'player-arm-r')) {
        playerVisible = n.visible;
        playerParts = n.children.map((c: any) => c.name || c.type);
      }
    });
    scene.traverse((n: any) => {
      if (n.isGroup && n.children.some((c: any) => c.name === 'highlight-outline')) {
        highlightChildren.push(...n.children.map((c: any) => c.name || c.type));
      }
    });
    const unique = new Map<any, any>();
    for (const m of allMats) unique.set(m.uuid, m);
    const mats = [...unique.values()];
    return {
      hasHandle: true,
      instancedMeshes: instanced.length,
      totalInstances: instanced.reduce((a, m) => a + m.count, 0),
      meshNames: instanced.map((m) => `${m.name}:${m.count}`),
      materialsWithMap: mats.filter((m) => !!m.map).length,
      materialsTotal: mats.length,
      nearestFiltered: mats.filter((m) => m.map && m.map.magFilter === 1003).length,
      texturedMaterials: mats.filter((m) => !!m.map).length,
      flatShaded: mats.filter((m) => m.flatShading === true).length,
      cameraType: h.camera.type,
      cameraY: Math.round(h.camera.position.y * 1000) / 1000,
      cameraFov: h.camera.fov,
      playerVisible,
      playerParts,
      armRFound,
      handVisible,
      lineSegments: lines.length,
      treeBlockCount: treeBlocks,
      highlightChildren,
    };
  });
}

const browser = await chromium.launch({ args: ['--autoplay-policy=no-user-gesture-required'] });
const page = await browser.newPage({ viewport: { width: 1280, height: 800 } });
const errors: string[] = [];
page.on('console', (m) => {
  if (m.type() === 'error') errors.push(`[${m.type()}] ${m.text()}`);
});
page.on('pageerror', (e) => errors.push(`[pageerror] ${e.message}`));

await page.goto(URL, { waitUntil: 'load' });
await page.waitForFunction(() => Boolean((window as any).__EH__), undefined, { timeout: 25000 });
await page.waitForTimeout(1200);

// Install an event log so tool feedback is measured (not inferred).
await page.evaluate(() => {
  const eh = (window as any).__EH__;
  (window as any).__EH_EVENTS__ = [];
  for (const name of ['tool:used', 'tool:failed', 'player:interact', 'fishing:cast', 'view:camera-mode']) {
    eh.bus.on(name, (payload: any) => {
      ((window as any).__EH_EVENTS__ ?? []).push({ type: name, tile: payload?.tile ?? null, t: performance.now() });
    });
  }
});

say('=== BOOT ===');
say(`console errors: ${errors.length}`);
for (const e of errors.slice(0, 8)) say(`  ${e}`);

const boot = await readScene(page);
say(`__EH_SCENE__ published: ${boot.hasHandle}`);
say(`instanced meshes: ${boot.instancedMeshes}, total instances: ${boot.totalInstances}`);
say(`instance meshes: ${boot.meshNames.join(', ')}`);
say(`materials: ${boot.materialsTotal} total, ${boot.texturedMaterials} textured, ${boot.nearestFiltered} NearestFilter`);
say(`flat-shaded materials: ${boot.flatShaded}`);
say(`camera: ${boot.cameraType} fov=${boot.cameraFov} y=${boot.cameraY} (eye-level default => y near 1.3)`);
say(`player visible: ${boot.playerVisible}, parts: ${boot.playerParts.join('|')}`);
say(`player-arm-r found: ${boot.armRFound}`);
say(`first-person hand visible: ${boot.handVisible}`);
say(`line segments (block outline): ${boot.lineSegments}`);
say(`highlight children: ${boot.highlightChildren.join(', ')}`);

const canvas = await page.locator('#game-root canvas').count();
say(`canvas count: ${canvas}`);

const stats = await page.evaluate(async () => {
  const el = document.querySelector('#game-root canvas') as HTMLCanvasElement;
  if (!el) return null;
  return { w: el.width, h: el.height };
});
say(`canvas backing store: ${JSON.stringify(stats)}`);

// screenshot for the record
await page.locator('#game-root canvas').screenshot({ path: 'artifacts/t0501-fp-boot.png' });

say('');
say('=== MOVEMENT (hold d for 2s, first person) ===');
const before = await page.evaluate(() => (window as any).__EH__.store.state.player.position);
await page.evaluate(() => {
  (window as any).__EH_SAMPLE__ = true;
  (window as any).__EH_SAMPLES__ = [];
  const tick = (): void => {
    const pos = (window as any).__EH__.store.state.player.position;
    (window as any).__EH_SAMPLES__.push({ t: performance.now(), x: pos.x, y: pos.y });
    if ((window as any).__EH_SAMPLE__) requestAnimationFrame(tick);
  };
  requestAnimationFrame(tick);
});
await page.keyboard.down('d');
await page.waitForTimeout(2000);
await page.keyboard.up('d');
const samples = await page.evaluate(() => {
  (window as any).__EH_SAMPLE__ = false;
  return (window as any).__EH_SAMPLES__ ?? [];
});
const after = await page.evaluate(() => (window as any).__EH__.store.state.player.position);
let movingFrames = 0;
for (let i = 1; i < samples.length; i++) {
  if (Math.hypot(samples[i].x - samples[i - 1].x, samples[i].y - samples[i - 1].y) > 1e-6) movingFrames++;
}
const dist = Math.hypot(after.x - before.x, after.y - before.y);
say(`from ${JSON.stringify(before)} to ${JSON.stringify(after)}`);
say(`distance: ${Math.round(dist * 100) / 100} tiles, moving frames: ${movingFrames}/${samples.length - 1}`);

say('');
say('=== TOOL: successful hoe on grass (first person) ===');
const nb = await page.evaluate(() => {
  const eh = (window as any).__EH__;
  const st = eh.store.state;
  const pos = st.player.position;
  const map = st.maps[pos.mapId];
  const legend = eh.runtime.content.maps.get(pos.mapId)?.legend ?? {};
  const cx = Math.floor(pos.x);
  const cy = Math.floor(pos.y);
  const cells: any[] = [];
  for (let y = cy - 5; y <= cy + 5; y++) {
    for (let x = cx - 5; x <= cx + 5; x++) {
      if (x < 0 || y < 0 || x >= map.grid.width || y >= map.grid.height) continue;
      const code = map.grid.tiles[y * map.grid.width + x];
      cells.push({ x, y, code, walkable: legend[code]?.walkable === true, planted: map.placed[`${x},${y}`] });
    }
  }
  return { origin: { x: cx, y: cy }, cells };
});
const target = nb.cells.find((c) => c.walkable && c.code === 'g' && !c.planted);
say(`player tile ${JSON.stringify(nb.origin)}, target ${target ? `(${target.x},${target.y})` : 'NONE'}`);
if (target) {
  await page.evaluate(
    ({ x, y }) => {
      const eh = (window as any).__EH__;
      const st = eh.store.state;
      st.player.position.x = x;
      st.player.position.y = y + 1;
      st.player.facing = 'up';
      eh.store.replaceState({ ...st });
    },
    { x: target.x, y: target.y },
  );
await page.waitForTimeout(200);
  const mark = await page.evaluate(() => ((window as any).__EH_EVENTS__ ?? []).length);
  await page.locator('#game-root canvas').screenshot({ path: 'artifacts/t0501-before-swing.png' });
  await page.keyboard.press('Space');
  await page.waitForTimeout(80);
  const midMetrics = await page.evaluate(() => (window as any).__EH_SCENE__.metrics());
  const fx = midMetrics.particles;
  const swinging = midMetrics.swinging;
  await page.locator('#game-root canvas').screenshot({ path: 'artifacts/t0501-swing.png' });
  await page.waitForTimeout(600);
  const evs = await page.evaluate((m) => ((window as any).__EH_EVENTS__ ?? []).slice(m), mark);
  const toolEvents = evs.filter((e: any) => e.type === 'tool:used' || e.type === 'tool:failed').map((e: any) => e.type);
  const placedNow = await page.evaluate(
    ({ x, y }) => {
      const st = (window as any).__EH__.store.state;
      const m = st.maps[st.player.position.mapId];
      return m.placed[`${x},${y}`]?.id ?? null;
    },
    { x: target.x, y: target.y },
  );
  say(`tool events: ${JSON.stringify(toolEvents)}`);
  say(`particles alive 80ms after swing: ${fx}, arm swinging: ${swinging}`);
  say(`tile (${target.x},${target.y}) is now: ${placedNow}`);
  await page.locator('#game-root canvas').screenshot({ path: 'artifacts/t0501-after-till.png' });
}

say('');
say('=== TOOL: failed swing (hoe on an occupied/blocked tile) ===');
{
  // Wait for any success-burst particles (life 0.55s) to expire first, so the
  // failure feedback can be measured uncontaminated.
  await page.waitForTimeout(700);
  const blocked = nb.cells.find((c) => !c.walkable && c.code !== '?');
  say(`blocked candidate: ${blocked ? `(${blocked.x},${blocked.y}) code=${blocked.code}` : 'none'}`);
  // Use a tile that already holds a placed object so the hoe fails.
  const occupied = nb.cells.find((c) => c.planted);
  const failTarget = occupied ?? blocked;
  if (failTarget) {
    await page.evaluate(
      ({ x, y }) => {
        const eh = (window as any).__EH__;
        const st = eh.store.state;
        st.player.position.x = x;
        st.player.position.y = y + 1;
        st.player.facing = 'up';
        eh.store.replaceState({ ...st });
      },
      { x: failTarget.x, y: failTarget.y },
    );
    await page.waitForTimeout(200);
    const mark = await page.evaluate(() => ((window as any).__EH_EVENTS__ ?? []).length);
    await page.locator('#game-root canvas').screenshot({ path: 'artifacts/t0501-before-fail.png' });
    await page.keyboard.press('Space');
    await page.waitForTimeout(70);
    const failMetrics = await page.evaluate(() => (window as any).__EH_SCENE__.metrics());
    const flash = await page.evaluate(() => {
      const h = (window as any).__EH_SCENE__;
      let red = 0;
      h.scene.traverse((n: any) => {
        const m = n.material;
        if (!m) return;
        const c = m.color;
        if (c && c.r > 0.85 && c.g < 0.35 && c.b < 0.3) red++;
      });
      return red;
    });
    await page.locator('#game-root canvas').screenshot({ path: 'artifacts/t0501-fail-flash.png' });
    await page.waitForTimeout(500);
    const evs = await page.evaluate((m) => ((window as any).__EH_EVENTS__ ?? []).slice(m), mark);
    const toolEvents = evs.filter((e: any) => e.type === 'tool:used' || e.type === 'tool:failed').map((e: any) => e.type);
    say(`tool events: ${JSON.stringify(toolEvents)}`);
    say(`red-flash materials live at 70ms: ${flash} (2 = outline + face flash)`);
    say(`particles during failure (must be 0): ${failMetrics.particles}, arm swinging: ${failMetrics.swinging}`);
  }
}

say('');
say('=== CAMERA TOGGLE (V) ===');
{
  const camBefore = await readScene(page);
  await page.keyboard.press('v');
  await page.waitForTimeout(300);
  const camAfter = await readScene(page);
  say(`before: y=${camBefore.cameraY} fov=${camBefore.cameraFov}`);
  say(`after V:  y=${camAfter.cameraY} fov=${camAfter.cameraFov}`);
  await page.locator('#game-root canvas').screenshot({ path: 'artifacts/t0501-top-down.png' });
  await page.keyboard.press('v');
  await page.waitForTimeout(300);
  const camBack = await readScene(page);
  say(`after V again: y=${camBack.cameraY} fov=${camBack.cameraFov} (back to first person)`);
  await page.locator('#game-root canvas').screenshot({ path: 'artifacts/t0501-back-to-fp.png' });
}

say('');
say('=== POINTER LOCK ===');
{
  const lockBefore = await page.evaluate(() => document.pointerLockElement !== null);
  await page.mouse.click(640, 400);
  await page.waitForTimeout(300);
  const lockAfter = await page.evaluate(() => document.pointerLockElement !== null);
  say(`pointer locked before click: ${lockBefore}, after click: ${lockAfter}`);
  // Esc release is a Chrome user-gesture path; in headless it can be ignored,
  // so also verify programmatic release (the app's onFocusIn path) works.
  await page.keyboard.press('Escape');
  await page.waitForTimeout(300);
  const lockEsc = await page.evaluate(() => document.pointerLockElement !== null);
  await page.evaluate(() => document.exitPointerLock());
  await page.waitForTimeout(300);
  const lockProg = await page.evaluate(() => document.pointerLockElement !== null);
  say(`locked after Escape (browser gesture, may differ headless): ${lockEsc}`);
  say(`locked after document.exitPointerLock(): ${lockProg} (false = releasable)`);
}

say('');
say('=== CAMERA HINT OVERLAY ===');
{
  const hint = await page.evaluate(() => {
    const el = document.getElementById('eh-camera-hint');
    if (!el) return null;
    return { text: el.textContent, pointerEvents: el.style.pointerEvents };
  });
  const topHint = await page.evaluate(() => document.getElementById('eh-camera-hint')?.textContent ?? null);
  await page.keyboard.press('v');
  await page.waitForTimeout(250);
  const hintAfterToggle = await page.evaluate(() => document.getElementById('eh-camera-hint')?.textContent ?? null);
  await page.keyboard.press('v');
  await page.waitForTimeout(250);
  say(`hint present: ${Boolean(hint)}, pointer-events: ${hint?.pointerEvents}`);
  say(`hint (first): ${hint?.text ?? ''}`);
  say(`hint (top after V): ${hintAfterToggle} (should mention 'first person')`);
  say(`hint (first again): ${topHint}`);
}

say('');
say('=== PANEL FOCUS STOPS MOVEMENT ===');
{
  // Continuous in-page tracer: hold 'd', then focus a plain button and verify
  // the sim position freezes at the focus moment (no drifting afterwards).
  await page.evaluate(() => {
    (window as any).__focusTrace__ = [];
    const trace = (): void => {
      const pos = (window as any).__EH__.store.state.player.position;
      (window as any).__focusTrace__.push({ t: performance.now(), x: pos.x, y: pos.y, focus: document.activeElement?.tagName ?? null });
      requestAnimationFrame(trace);
    };
    requestAnimationFrame(trace);
  });
  await page.keyboard.down('d');
  await page.waitForTimeout(400);
  await page.evaluate(() => {
    const ghost = document.createElement('button');
    ghost.id = 'focus-probe';
    document.body.appendChild(ghost);
    ghost.focus();
  });
  await page.waitForTimeout(400);
  await page.keyboard.up('d');
  await page.evaluate(() => document.getElementById('focus-probe')?.remove());
  const trace = await page.evaluate(() => (window as any).__focusTrace__ ?? []);
  // Find the first sample after the button (BODY/BUTTON focus) took over.
  let focusAt = -1;
  for (let i = 0; i < trace.length; i++) {
    if (trace[i].focus === 'BUTTON') {
      focusAt = i;
      break;
    }
  }
  const before = focusAt > 0 ? trace[focusAt - 1]! : null;
  const after = focusAt >= 0 ? trace[focusAt]! : null;
  const drifted = after ? Math.hypot(trace[trace.length - 1]!.x - after.x, trace[trace.length - 1]!.y - after.y) : -1;
  say(`samples: ${trace.length}`);
  say(`last pre-focus sample: ${before ? `x=${before.x.toFixed(2)} y=${before.y.toFixed(2)}` : 'none'}`);
  say(`first focused sample: ${after ? `x=${after.x.toFixed(2)} y=${after.y.toFixed(2)}` : 'none'}`);
  say(`drift after focus (tiles): ${drifted.toFixed(3)} -> player stopped: ${drifted < 0.01}`);
}

say('');
say('=== FINAL CONSOLE ERROR COUNT ===');
say(`${errors.length}`);
for (const e of errors.slice(0, 10)) say(`  ${e}`);

await browser.close();

const { writeFile, mkdir } = await import('node:fs/promises');
await mkdir('artifacts', { recursive: true });
await writeFile('artifacts/t0501-transcript.txt', out.join('\n'), 'utf8');
say('');
say('transcript written to artifacts/t0501-transcript.txt');
