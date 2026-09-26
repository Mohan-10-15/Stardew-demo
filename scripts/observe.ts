/**
 * scripts/observe.ts - drive the real game in a real browser and print what
 * actually happened. Usage:
 *
 *   npm run dev            # in another shell
 *   npx vite-node scripts/observe.ts
 *
 * Every number in the output is measured, not assumed: player positions are
 * sampled per animation frame, colours are read back out of the WebGL canvas,
 * and the audio lines are a transcript of the oscillators the game scheduled.
 */
import {
  audioMark,
  audioSince,
  canvasStats,
  eventsSince,
  eventMark,
  faceTile,
  holdAndSample,
  neighbourhood,
  observe,
  placedObjects,
  playerState,
  regionColor,
  shot,
} from './observe-lib.ts';

const out: string[] = [];
function say(line = ''): void {
  out.push(line);
  console.log(line);
}
function head(title: string): void {
  say();
  say(`=== ${title} ===`);
}
function kv(k: string, v: unknown): void {
  say(`  ${k.padEnd(22)} ${typeof v === 'string' ? v : JSON.stringify(v)}`);
}

const o = await observe();
const { page } = o;

head('BOOT');
kv('booted', o.booted);
kv('url', process.env['EH_URL'] ?? 'http://localhost:2026/');
if (!o.booted) {
  say('  console:');
  for (const l of o.console) say(`    [${l.type}] ${l.text}`);
  await shot(page, 'artifacts/observe-boot-fail.png');
  await o.close();
  process.exit(1);
}
kv('console errors', o.errors.length);
for (const e of o.errors.slice(0, 10)) say(`    [${e.type}] ${e.text}`);
kv('info lines', o.console.filter((l) => l.type === 'info').length);
for (const l of o.console.filter((l) => l.type === 'info').slice(0, 12)) say(`    ${l.text}`);
kv('audio contexts', await page.evaluate(() => (window as never as { __EH_AUDIO_CTX_COUNT__?: number }).__EH_AUDIO_CTX_COUNT__ ?? 0));
kv('start state', await playerState(page));
const canvas = await page.locator('#game-root canvas').count();
kv('canvas count', canvas);
kv('canvas pixels', await canvasStats(page));
await shot(page, 'artifacts/observe-01-boot.png');

head('MOVEMENT - hold D for 2s');
{
  const before = await playerState(page);
  const trace = await holdAndSample(page, ['d'], 2000);
  kv('from', trace.from);
  kv('to', trace.to);
  kv('distance (tiles)', trace.distance);
  kv('frames sampled', trace.frames);
  kv('frames that moved', trace.movingFrames);
  kv('largest single-frame step', trace.maxStep);
  kv('smallest non-zero step', trace.minStep);
  kv('frames on an exact integer tile', trace.integerPositions);
  kv('elapsed ms', trace.elapsedMs);
  kv('tiles/sec', trace.speedPerSec);
  kv('facing now', (await playerState(page)).facing);
  kv('energy before', before.energy);
  kv('energy after', (await playerState(page)).energy);
  say(
    `  VERDICT smooth=${trace.movingFrames > 8 && trace.integerPositions < trace.frames * 0.5 ? 'YES' : 'NO (snapping)'}`,
  );
}
await shot(page, 'artifacts/observe-02-after-walk.png');

head('MOVEMENT - shift walk vs jog over 1s each');
{
  const jog = await holdAndSample(page, ['a'], 1000);
  const walk = await holdAndSample(page, ['Shift', 'a'], 1000);
  kv('jog tiles/sec', jog.speedPerSec);
  kv('shift tiles/sec', walk.speedPerSec);
  kv('ratio', walk.speedPerSec > 0 ? Math.round((walk.speedPerSec / jog.speedPerSec) * 100) / 100 : 'n/a');
  say(`  VERDICT shift-is-slower=${walk.speedPerSec < jog.speedPerSec ? 'YES' : 'NO'}`);
}

head('MOVEMENT - diagonal (W+D) for 1s');
{
  const diag = await holdAndSample(page, ['w', 'd'], 1000);
  const single = await holdAndSample(page, ['s'], 1000);
  kv('diagonal distance', diag.distance);
  kv('single-axis distance', single.distance);
  kv('diagonal speed tiles/sec', diag.speedPerSec);
  kv('single speed tiles/sec', single.speedPerSec);
  say(
    `  VERDICT diagonals-not-slower=${diag.speedPerSec >= single.speedPerSec * 0.95 ? 'YES (normalised)' : 'NO (diagonal penalty)'}`,
  );
}

head('TOOL - successful hoe on a walkable tile');
{
  const nb = await neighbourhood(page, 6);
  const target = nb.cells.find(
    (c) => c.walkable && c.code === 'g' && Math.abs(c.x - nb.origin.x) <= 2 && Math.abs(c.y - nb.origin.y) <= 2,
  );
  say(`  player at ${JSON.stringify(nb.origin)}; target ${target ? `(${target.x},${target.y}) code=${target.code}` : 'NONE FOUND'}`);
  if (target) {
    await faceTile(page, target.x, target.y + 1, 'up');
    await page.waitForTimeout(300);
    const st = await playerState(page);
    const projected = await projectTile(page, target.x, target.y, st.mapId);
    const placedBefore = await placedObjects(page);
    const audioMarkBefore = await audioMark(page);
    const evMark = await eventMark(page);
    const metricsBefore = await sceneMetrics(page);
    kv('renderer metrics before', metricsBefore);
    kv('target tile projected to', projected);
    const tileColorBefore = projected
      ? await regionColor(page, projected.x - 12, projected.y - 12, 24, 24)
      : null;
    await shot(page, 'artifacts/observe-03-before-swing.png');
    await page.keyboard.press('Space');
    const swing = await waitForScene(page, (m) => m.swinging || m.particles > 0, 1500);
    const metricsDuring = swing.samples[swing.samples.length - 1] ?? null;
    kv('swing observed', swing.matched);
    kv('renderer metrics during', metricsDuring);
    if (projected) {
      kv('tile colour before', tileColorBefore);
      kv('tile colour during', await regionColor(page, projected.x - 12, projected.y - 12, 24, 24));
    }
    await shot(page, 'artifacts/observe-04-swing.png');
    await page.waitForTimeout(600);
    const placedAfter = await placedObjects(page);
    const evs = await eventsSince(page, evMark);
    const aud = await audioSince(page, audioMarkBefore);
    kv('new placed key', Object.keys(placedAfter).find((k) => !placedBefore[k]) ?? 'none');
    kv('sim events', evs.types.filter((t) => t.startsWith('tool:') || t.startsWith('farming:')));
    kv('audio notes played', aud.count);
    for (const n of aud.notes) say(`      ${n.type} ${n.freqStart}Hz @${n.at}ms`);
    kv('metrics after settle', await sceneMetrics(page));
    await shot(page, 'artifacts/observe-05-after-swing.png');
    say(`  VERDICT tilled-soil-created=${Object.keys(placedAfter).some((k) => !placedBefore[k]) ? 'YES' : 'NO'}`);
    say(`  VERDICT swing-animation=${swing.matched && (metricsDuring?.swinging ?? false) ? 'YES' : 'NO'}`);
    say(`  VERDICT particle-burst=${(metricsDuring?.particles ?? 0) > 0 ? `YES (${metricsDuring?.particles} particles)` : 'NO'}`);
    say(`  VERDICT success-audio=${aud.count > 0 ? `YES (${aud.count} notes)` : 'NO (silent)'}`);
  }
}

head('TOOL - failed interact (hoe on a blocked tile)');
{
  const nb = await neighbourhood(page, 6);
  const blocked = nb.cells.find((c) => !c.walkable && c.code !== '?');
  say(`  blocked candidates: ${nb.cells.filter((c) => !c.walkable).map((c) => `${c.code}@${c.x},${c.y}`).join(' ') || 'none'}`);
  if (blocked) {
    const stand = { x: blocked.x, y: blocked.y + 1 };
    await faceTile(page, stand.x, stand.y, 'up');
    await page.waitForTimeout(300);
    const st = await playerState(page);
    const projected = await projectTile(page, blocked.x, blocked.y, st.mapId);
    const audioMarkBefore = await audioMark(page);
    const evMark = await eventMark(page);
    const placedBefore = await placedObjects(page);
    const metricsBefore = await sceneMetrics(page);
    kv('renderer metrics before', metricsBefore);
    kv('target tile projected to', projected);
    const before = projected ? await regionColor(page, projected.x - 12, projected.y - 12, 24, 24) : null;
    await shot(page, 'artifacts/observe-06-before-fail.png');
    await page.keyboard.press('Space');
    const flash = await waitForScene(page, (m) => m.failFlash, 1500);
    const metricsDuring = flash.samples[flash.samples.length - 1] ?? null;
    kv('fail flash observed', flash.matched);
    kv('renderer metrics during', metricsDuring);
    if (projected) {
      kv('tile colour before', before);
      kv('tile colour during flash', await regionColor(page, projected.x - 12, projected.y - 12, 24, 24));
    }
    await shot(page, 'artifacts/observe-07-fail-flash.png');
    await page.waitForTimeout(600);
    const evs = await eventsSince(page, evMark);
    const aud = await audioSince(page, audioMarkBefore);
    const placedAfter = await placedObjects(page);
    const metricsAfter = await sceneMetrics(page);
    kv('sim events', evs.types.filter((t) => t.startsWith('tool:')));
    kv('failure reasons', evs.payloads.filter((p) => p.type === 'tool:failed').map((p) => (p.payload as { reason?: string }).reason));
    kv('audio notes played', aud.count);
    for (const n of aud.notes) say(`      ${n.type} ${n.freqStart}Hz @${n.at}ms`);
    kv('metrics after settle', metricsAfter);
    kv('world unchanged', Object.keys(placedAfter).length === Object.keys(placedBefore).length ? 'YES' : 'NO');
    say(`  VERDICT red-flash=${flash.matched ? 'YES' : 'NO'}`);
    say(`  VERDICT no-swing-on-failure=${metricsDuring?.swinging === false ? 'YES' : `NO (swinging=${metricsDuring?.swinging})`}`);
    say(`  VERDICT no-particles-on-failure=${(metricsDuring?.particles ?? 0) === 0 ? 'YES' : `NO (${metricsDuring?.particles})`}`);
    say(`  VERDICT fail-audio=${aud.count > 0 ? `YES (${aud.count} notes)` : 'NO (silent)'}`);
  }
}

head('AUDIO - context created on a real gesture');
{
  const t = await page.evaluate(() => {
    const w = window as unknown as { __EH_AUDIO_CTX_COUNT__?: number; __EH_CTX__?: { state: string } };
    return { contexts: w.__EH_AUDIO_CTX_COUNT__ ?? 0, state: w.__EH_CTX__?.state ?? 'none' };
  });
  kv('AudioContexts created', t.contexts);
  kv('context state', t.state);
  const total = await page.evaluate(() => (window as unknown as { __EH_AUDIO__?: unknown[] }).__EH_AUDIO__?.length ?? 0);
  kv('total synthesis calls', total);
}

head('UI PANELS');
{
  const panels = await page.evaluate(() => {
    const out: Array<{ cls: string; text: string }> = [];
    for (const el of Array.from(document.querySelectorAll('#ui-root *'))) {
      const cls = el.className;
      if (typeof cls !== 'string') continue;
      if (!cls.includes('eh-')) continue;
      out.push({ cls, text: (el.textContent ?? '').trim().slice(0, 40) });
    }
    return out;
  });
  const classes = [...new Set(panels.map((p) => p.cls))].slice(0, 25);
  kv('eh- classes present', classes);
  const font = await page.evaluate(() => {
    const el = document.querySelector('#ui-root .eh-panel, #ui-root .eh-button, #ui-root *');
    if (!el) return 'none';
    const cs = getComputedStyle(el as Element);
    return { family: cs.fontFamily, size: cs.fontSize, bg: cs.backgroundColor, border: cs.borderTopWidth + ' ' + cs.borderTopStyle + ' ' + cs.borderTopColor };
  });
  kv('computed UI font', font);
  const loaded = await page.evaluate(() =>
    Array.from(document.fonts).map((f) => `${f.family} ${f.weight} ${f.status}`),
  );
  kv('webfonts loaded', loaded);
}
await shot(page, 'artifacts/observe-08-ui.png');

head('SUMMARY OF MEASUREMENTS');
say('  (each VERDICT line above is the pass/fail signal)');

await o.close();

const target = 'artifacts/observe-transcript.txt';
const { writeFile, mkdir } = await import('node:fs/promises');
await mkdir('artifacts', { recursive: true });
await writeFile(target, out.join('\n'), 'utf8');
console.log(`\ntranscript written to ${target}`);
