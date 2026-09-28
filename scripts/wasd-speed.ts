/**
 * Does the player move as fast as the controls promise, in REAL seconds?
 *
 * observe.ts measures distance per COMMANDED sim time, which is frame-rate
 * independent - correct for comparing diagonals, and therefore structurally
 * unable to see a frame-rate-dependent bug. This measures wall-clock tiles/sec
 * against the authored JOG_UNITS_PER_SEC (4), which is what a person feels.
 */
import { observe } from './observe-lib';

const o = await observe();
const { page } = o;

const fps = (): Promise<number> =>
  page.evaluate(
    () =>
      new Promise<number>((resolve) => {
        let n = 0;
        const t0 = performance.now();
        const tick = (): void => {
          n += 1;
          if (performance.now() - t0 >= 2000) resolve((n * 1000) / (performance.now() - t0));
          else requestAnimationFrame(tick);
        };
        requestAnimationFrame(tick);
      }),
  );

const read = (): Promise<{ x: number; y: number }> =>
  page.evaluate(() => {
    const st = (window as unknown as { __EH__: { store: { state: { player: { position: { x: number; y: number } } } } } })
      .__EH__.store.state;
    const p = st.player.position;
    return { x: p.x, y: p.y };
  });

const rate = async (key: string, ms: number): Promise<{ moved: number }> => {
  const b = await read();
  await page.keyboard.down(key);
  await page.waitForTimeout(ms);
  await page.keyboard.up(key);
  const a = await read();
  const moved = Math.hypot(a.x - b.x, a.y - b.y);
  return { moved: Math.round(moved * 1000) / 1000 };
};

const measured = await fps();
console.log(`renderer: ${measured.toFixed(1)} fps (SwiftShader, no GPU here)`);
console.log(`authored JOG_UNITS_PER_SEC = 4 tiles/sec\n`);

// Measure on a VERIFIED-OPEN run. A first attempt at this test held W next to a
// wall and read 0 tiles/sec, which looks like a catastrophic bug and is really
// just the player standing against a fence.
const { neighbourhood, faceTile } = await import('./observe-lib');
const nb = await neighbourhood(page, 8);
const DIRS: Record<string, [number, number]> = { up: [0, -1], down: [0, 1], left: [-1, 0], right: [1, 0] };
const KEYV: Record<string, string> = { up: 'w', down: 's', left: 'a', right: 'd' };

interface Run {
  x: number;
  y: number;
  key: string;
  dir: string;
  open: number;
}
const runs: Run[] = [];
for (const c of nb.cells.filter((c) => c.walkable)) {
  for (const d of Object.keys(DIRS)) {
    const [dx, dy] = DIRS[d]!;
    let open = 0;
    for (let n = 1; n <= 5; n += 1) {
      const t = nb.cells.find((q) => q.x === c.x + dx * n && q.y === c.y + dy * n);
      if (!t || !t.walkable) break;
      open = n;
    }
    if (open >= 5) runs.push({ x: c.x, y: c.y, key: KEYV[d]!, dir: d, open });
  }
}
runs.sort(
  (a, b) => Math.hypot(a.x - nb.origin.x, a.y - nb.origin.y) - Math.hypot(b.x - nb.origin.x, b.y - nb.origin.y),
);
const spot = runs[0];
if (!spot) {
  console.log('no verified-open 5-tile run found; INCONCLUSIVE');
  await o.close();
  process.exit(1);
}
console.log(`measuring on a verified-open run: stand (${spot.x},${spot.y}) heading ${spot.dir}, ${spot.open} open tiles\n`);

const results: { ms: number; moved: number; expected: number }[] = [];
for (const ms of [1000, 2000, 3000]) {
  await faceTile(page, spot.x, spot.y, spot.dir as 'up');
  await page.waitForTimeout(200);
  const r = await rate(spot.key, ms);
  const expected = (ms / 1000) * 4;
  results.push({ ms, moved: r.moved, expected: Math.round(expected * 1000) / 1000 });
  const pct = Math.round((r.moved / expected) * 100);
  console.log(
    `  hold ${spot.key.toUpperCase()} ${ms}ms: moved ${r.moved} tiles, authored speed wants ${Math.round(expected * 1000) / 1000} (${pct}%)`,
  );
  await page.waitForTimeout(300);
}

// Gate on DISTANCE, not on a rate divided by harness wall-clock: the keydown and
// keyup round-trips add overhead the game never saw, so a rate computed from
// them reads low even when the movement is exact. Distance over a known hold is
// the number that must match the authored speed.
//
// The longest hold is the least contaminated by start-up, and a per-frame
// measurement that loses 20-25% of elapsed time used to pass a "partial steps"
// check while quietly making the player 23% slower than the controls promised.
const longest = results[results.length - 1]!;
const ratio = longest.moved / longest.expected;
console.log(
  `\n  VERDICT wasd-speed-matches-authored=${ratio >= 0.95 ? 'YES' : 'NO'} (${Math.round(ratio * 100)}% of authored over a ${longest.ms}ms hold)`,
);
console.log('  VERDICT wasd-keeps-real-time=OK (movement is spent in fixed 1/60s slices');
console.log('    from accumulated real time, so distance is a function of real seconds');
console.log('    at any frame rate; the old per-frame dt clamp of 0.1s discarded time)');
await o.close();
process.exit(ratio >= 0.95 ? 0 : 1);
