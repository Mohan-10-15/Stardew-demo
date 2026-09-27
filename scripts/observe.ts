/**
 * scripts/observe.ts - drive the real game in a real browser and print what
 * actually happened. Usage:
 *
 *   npm run dev            # in another shell
 *   npx vite-node scripts/observe.ts
 *
 * Every number in the output is measured, not assumed: player positions are
 * sampled per animation frame, colours are read back out of a compositor
 * screenshot of the WebGL canvas, and the audio lines come from the audio
 * lane's own per-cue SFX recorder (the raw oscillator count is reported too,
 * but only as a CONTROL: the soundtrack plays continuously, so raw note
 * counting cannot distinguish an SFX from the music).
 */
import {
  audioIdleControl,
  canvasStats,
  eventsSince,
  eventMark,
  faceTile,
  holdAndSample,
  neighbourhood,
  observe,
  placedObjects,
  playerState,
  projectTile,
  regionColor,
  sceneMetrics,
  sfxCueMark,
  sfxCuesSince,
  shot,
  startAxisRateProbe,
  stopAxisRateProbe,
  waitForScene,
} from './observe-lib.ts';

/** Every SFX cue name seen across the tool actions, so the success and failure
 *  paths can be proven to be different cues rather than the same one twice. */
const cueNamesSeen: string[] = [];

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

head('MOVEMENT - diagonal, measured in verified open ground');
{
  // The invariant: holding two keys must advance BOTH axes at the full
  // single-axis walk speed. The old code normalised by Math.hypot(dx, dy),
  // which capped the combined diagonal at one axis worth of distance, so each
  // axis only got 1/sqrt(2) of the speed and diagonals felt sluggish.
  //
  // Method notes, because three plausible-looking measurements were wrong here:
  //  - wall-clock tiles/sec is unusable: this box has no GPU, the renderer runs
  //    at 2-11fps, and the frame delta is clamped, so two time-boxed holds
  //    integrate different amounts of simulated time (measured 3x apart).
  //  - displacement per rendered frame is also unusable: a hold that clips a
  //    wall reports a nonsense average.
  //  - summing the unit direction vector is worse than useless: it is 1.0 by
  //    construction and would "prove" a fix that never happened.
  // What is left is honest: tap the store's dispatch, read the player position
  // either side of each real `player:walk`, and divide the distance the sim
  // ACTUALLY moved by the time it was COMMANDED to move, per axis.
  //
  // Both holds are started from a tile with verified open tiles ahead on both
  // axes, so collision cannot masquerade as a speed difference.
  const DIRS = { right: [1, 0], left: [-1, 0], down: [0, 1], up: [0, -1] } as const;
  type DirName = keyof typeof DIRS;
  const nb = await neighbourhood(page, 6);
  const openRun = (x: number, y: number, dx: number, dy: number, need: number): boolean => {
    for (let i = 1; i <= need; i++) {
      const cell = nb.cells.find((c) => c.x === x + dx * i && c.y === y + dy * i);
      if (!cell || !cell.walkable) return false;
    }
    return true;
  };
  // The tile with open ground on the two most open axes. The starting tile
  // itself must be walkable (stepping out of a wall tile is blocked outright),
  // and the nearest such tile is preferred so the measurement happens where the
  // player already is rather than across the map.
  let spot: { x: number; y: number; a: DirName; b: DirName } | null = null;
  const candidates = nb.cells
    .filter((c) => c.walkable)
    .map((c) => ({
      c,
      open: (Object.keys(DIRS) as DirName[]).filter((d) => openRun(c.x, c.y, DIRS[d][0], DIRS[d][1], 5)),
    }))
    .filter((e) => e.open.length >= 2)
    .sort(
      (p, q) =>
        Math.hypot(p.c.x - nb.origin.x, p.c.y - nb.origin.y) - Math.hypot(q.c.x - nb.origin.x, q.c.y - nb.origin.y),
    );
  const best = candidates[0];
  if (best) spot = { x: best.c.x, y: best.c.y, a: best.open[0]!, b: best.open[1]! };
  if (!spot) {
    say('  VERDICT diagonals-not-slower=INCONCLUSIVE (no tile with 5 open tiles on two axes)');
  } else {
    const KEY: Record<DirName, string> = { up: 'w', down: 's', left: 'a', right: 'd' };
    const HORIZONTAL: Record<DirName, 'x' | 'y'> = { left: 'x', right: 'x', up: 'y', down: 'y' };
    say(`  open ground at (${spot.x}, ${spot.y}); single-axis reference ${spot.a}, diagonal ${spot.a}+${spot.b}`);

    await faceTile(page, spot.x, spot.y, spot.a);
    await page.waitForTimeout(250);
    await startAxisRateProbe(page);
    await holdAndSample(page, [KEY[spot.a]], 1500);
    const single = await stopAxisRateProbe(page);

    await faceTile(page, spot.x, spot.y, spot.a);
    await page.waitForTimeout(250);
    await startAxisRateProbe(page);
    await holdAndSample(page, [KEY[spot.a], KEY[spot.b]], 1500);
    const diag = await stopAxisRateProbe(page);

    const singleRate = HORIZONTAL[spot.a] === 'x' ? single.rateX : single.rateY;
    const diagA = HORIZONTAL[spot.a] === 'x' ? diag.rateX : diag.rateY;
    const diagB = HORIZONTAL[spot.b] === 'x' ? diag.rateX : diag.rateY;
    kv('single-axis rate (tiles per s)', Math.round(singleRate * 100) / 100);
    kv('diagonal rate on axis A (tiles per s)', Math.round(diagA * 100) / 100);
    kv('diagonal rate on axis B (tiles per s)', Math.round(diagB * 100) / 100);
    kv('diagonal commanded time (x / y s)', `${Math.round(diag.secX * 100) / 100} / ${Math.round(diag.secY * 100) / 100}`);
    kv('diagonal dispatches', diag.dispatches);

    if (singleRate <= 0 || diagA <= 0 || diagB <= 0) {
      say('  VERDICT diagonals-not-slower=INCONCLUSIVE (no commanded movement recorded)');
    } else {
      const ra = diagA / singleRate;
      const rb = diagB / singleRate;
      kv('per-axis ratio vs single', `A=${Math.round(ra * 1000) / 1000} B=${Math.round(rb * 1000) / 1000}`);
      // Guard against a bogus PASS: if the single-axis reference was itself
      // obstructed it reads far too slow and the ratio is inflated. Require the
      // reference to be within 20% of the diagonal before trusting the ratio.
      const referenceValid = Math.max(diagA, diagB) / singleRate < 1.25;
      if (!referenceValid) {
        say('  VERDICT diagonals-not-slower=INCONCLUSIVE (single-axis reference was obstructed)');
      } else {
        const TOLERANCE = 0.95;
        const ok = ra >= TOLERANCE && rb >= TOLERANCE;
        say(
          `  VERDICT diagonals-not-slower=${ok ? `YES (A=${ra.toFixed(2)}, B=${rb.toFixed(2)} of single-axis speed)` : `NO (A=${ra.toFixed(2)}, B=${rb.toFixed(2)} < ${TOLERANCE})`}`,
        );
      }
    }
  }
}
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
  // Step uniformity is the frame-rate independent part of "smooth". A frame that
  // clips geometry legitimately ends on a partial MAX_STEP sub-step, so a couple
  // of short frames are fine; a majority of them would be a visible stutter.
  // Wall-clock tiles/sec is NOT used as evidence: a 2s hold on this software
  // renderer has been observed sampling anywhere from 2.4 to 11 frames, so
  // tiles/sec swings by 3x between runs on identical code.
  const partialPct = trace.movingFrames > 0 ? trace.partialSteps / trace.movingFrames : 1;
  const uniform = trace.movingFrames > 0 && partialPct <= 0.25;
  kv('frames with a partial step', `${trace.partialSteps} of ${trace.movingFrames}`);
  say(
    `  VERDICT step-uniform=${uniform ? `YES (${Math.round(partialPct * 100)}% partial, from the collision sampler)` : `NO (${Math.round(partialPct * 100)}% partial, steps ranged ${trace.minStep}..${trace.maxStep})`}`,
  );
  kv('per-frame step', Math.round((trace.distance / Math.max(1, trace.movingFrames)) * 10000) / 10000);
}
await shot(page, 'artifacts/observe-02-after-walk.png');

head('MOVEMENT - shift walk vs jog (compared per frame, not per second)');
{
  // Frame-rate independent: compare displacement per MOVING FRAME. tiles/sec
  // is unusable as evidence here because the two windows collect different
  // amounts of simulated time when the renderer is starved (measured 1.21 and
  // 0.74 on identical code, purely from frame quantisation).
  const jog = await holdAndSample(page, ['a'], 2000);
  const walk = await holdAndSample(page, ['Shift', 'a'], 2000);
  const jogStep = jog.movingFrames > 0 ? jog.distance / jog.movingFrames : 0;
  const walkStep = walk.movingFrames > 0 ? walk.distance / walk.movingFrames : 0;
  kv('jog per-frame step', Math.round(jogStep * 10000) / 10000);
  kv('shift per-frame step', Math.round(walkStep * 10000) / 10000);
  kv('ratio', walkStep > 0 ? Math.round((walkStep / jogStep) * 100) / 100 : 'n/a');
  kv('jog moving frames', jog.movingFrames);
  kv('shift moving frames', walk.movingFrames);
  say(`  VERDICT shift-is-slower=${walkStep < jogStep ? 'YES' : 'NO'} (per-frame, frame-rate independent)`);
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
    const cueMarkBefore = await sfxCueMark(page);
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
    const cues = await sfxCuesSince(page, cueMarkBefore);
    kv('new placed key', Object.keys(placedAfter).find((k) => !placedBefore[k]) ?? 'none');
    kv('sim events', evs.types.filter((t) => t.startsWith('tool:') || t.startsWith('farming:')));
    kv('sfx cues', cues.map((c) => c.cue).join(', ') || 'none');
    for (const c of cues) say(`      ${c.cue} <- ${c.source ?? '?'} :: ${c.tones.map((t) => `${t.freq}Hz${t.glide ? '->' + t.glide : ''} ${t.type}`).join(' + ')}`);
    kv('metrics after settle', await sceneMetrics(page));
    await shot(page, 'artifacts/observe-05-after-swing.png');
    say(`  VERDICT tilled-soil-created=${Object.keys(placedAfter).some((k) => !placedBefore[k]) ? 'YES' : 'NO'}`);
    say(`  VERDICT swing-animation=${swing.matched && (metricsDuring?.swinging ?? false) ? 'YES' : 'NO'}`);
    say(`  VERDICT particle-burst=${(metricsDuring?.particles ?? 0) > 0 ? `YES (${metricsDuring?.particles} particles)` : 'NO'}`);
    say(`  VERDICT success-audio=${cues.some((c) => c.cue === 'tool:success') ? 'YES (tool:success cue)' : 'NO (no tool:success cue)'}`);
    cueNamesSeen.push(...cues.map((c) => c.cue));
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
    const cueMarkBefore = await sfxCueMark(page);
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
    const cues = await sfxCuesSince(page, cueMarkBefore);
    const placedAfter = await placedObjects(page);
    const metricsAfter = await sceneMetrics(page);
    kv('sim events', evs.types.filter((t) => t.startsWith('tool:')));
    kv('failure reasons', evs.payloads.filter((p) => p.type === 'tool:failed').map((p) => (p.payload as { reason?: string }).reason));
    kv('sfx cues', cues.map((c) => c.cue).join(', ') || 'none');
    for (const c of cues) say(`      ${c.cue} <- ${c.source ?? '?'} :: ${c.tones.map((t) => `${t.freq}Hz${t.glide ? '->' + t.glide : ''} ${t.type}`).join(' + ')}`);
    kv('metrics after settle', metricsAfter);
    kv('world unchanged', Object.keys(placedAfter).length === Object.keys(placedBefore).length ? 'YES' : 'NO');
    say(`  VERDICT red-flash=${flash.matched ? 'YES' : 'NO'}`);
    say(`  VERDICT no-swing-on-failure=${metricsDuring?.swinging === false ? 'YES' : `NO (swinging=${metricsDuring?.swinging})`}`);
    say(`  VERDICT no-particles-on-failure=${(metricsDuring?.particles ?? 0) === 0 ? 'YES' : `NO (${metricsDuring?.particles})`}`);
    say(`  VERDICT fail-audio=${cues.some((c) => c.cue === 'tool:failure') ? 'YES (tool:failure cue)' : 'NO (no tool:failure cue)'}`);
    cueNamesSeen.push(...cues.map((c) => c.cue));
  }
}

head('AUDIO - the control that makes the audio verdicts honest');
{
  // The soundtrack plays continuously, so "we scheduled some oscillators" proves
  // nothing. Sitting still must add ZERO sfx cues while the music keeps going.
  const idle = await audioIdleControl(page, 4000);
  kv('idle window', '4s, no input at all');
  kv('sfx cues while idle', idle.count);
  kv('music bars scheduled', idle.music.bars);
  kv('music notes scheduled', idle.music.notes);
  kv('raw oscillators while idle', idle.oscillators);
  kv('bus / context', `${idle.audio.bus ?? 'none'} / ${idle.audio.state} / ${idle.audio.contexts} contexts`);
  say(`  VERDICT idle-is-silent-on-sfx=${idle.count === 0 ? 'YES (0 cues)' : `NO (${idle.count} cues: ${idle.cues.map((c) => c.cue).join(', ')})`}`);
  say(`  VERDICT idle-still-has-music=${idle.oscillators > 0 ? `YES (${idle.oscillators} oscillators - this is why raw note counting was worthless)` : 'NO (music also silent)'}`);
  const distinct = [...new Set(cueNamesSeen)];
  kv('distinct cues across both tool actions', distinct.join(', ') || 'none');
  say(`  VERDICT success-and-failure-are-different-cues=${distinct.includes('tool:success') && distinct.includes('tool:failure') ? 'YES' : `NO (saw ${distinct.join(', ') || 'nothing'})`}`);
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
