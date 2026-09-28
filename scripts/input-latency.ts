/**
 * Input latency, measured INSIDE the page.
 *
 * The first attempt polled `player.position` from outside with repeated
 * page.evaluate round-trips and read 244-277ms. That number cannot be trusted:
 * at 8fps the main thread is saturated by SwiftShader rendering, so the polling
 * callbacks queue behind the render task exactly like the input callback does.
 * The measurement was competing for the same starved thread it was measuring.
 *
 * Here the keydown timestamp and the position-change timestamp are both taken
 * by code inside the page, in the same task queue, so the difference is real
 * input-to-movement latency rather than harness round-trip cost.
 */
import { observe, faceTile, neighbourhood } from './observe-lib';

const o = await observe();
const { page } = o;

await page.evaluate(() => {
  const w = window as unknown as {
    __EH__: { store: { state: { player: { position: { x: number; y: number } } } } };
    __LAT__?: { down: number; moved: number; samples: number[] };
  };
  w.__LAT__ = { down: 0, moved: 0, samples: [] };
  // The store is immutable, so the state object must be re-read on every check.
  // Caching it once (the first version of this probe) never sees the position
  // change at all, because the captured object is a snapshot that is replaced.
  const posY = (): number =>
    (w.__EH__ as unknown as { store: { state: { player: { position: { y: number } } } } }).store.state.player
      .position.y;

  window.addEventListener(
    'keydown',
    (e: KeyboardEvent) => {
      if (e.key !== 'w' || e.repeat) return;
      w.__LAT__!.down = performance.now();
      const startY = posY();
      const check = (): void => {
        if (w.__LAT__!.moved !== 0) return;
        if (posY() !== startY) {
          w.__LAT__!.moved = performance.now();
          w.__LAT__!.samples.push(Math.round(w.__LAT__!.moved - w.__LAT__!.down));
          return;
        }
        requestAnimationFrame(check);
      };
      requestAnimationFrame(check);
    },
    true,
  );
});

const nb = await neighbourhood(page, 6);
const open = nb.cells.filter((c) => c.walkable && c.code === 'g');
for (let i = 0; i < 5; i += 1) {
  const c = open[i];
  if (!c) break;
  await faceTile(page, c.x, c.y + 1, 'up');
  await page.waitForTimeout(400);
  await page.keyboard.down('w');
  await page.waitForTimeout(350);
  await page.keyboard.up('w');
  await page.waitForTimeout(250);
}

const lat = await page.evaluate(() => {
  const w = window as unknown as { __LAT__: { samples: number[] } };
  return w.__LAT__.samples;
});
console.log('in-page keydown -> first movement, ms:');
console.log('  ' + (lat.length ? lat.join(', ') : 'NO SAMPLES COLLECTED'));
if (lat.length) {
  const avg = Math.round(lat.reduce((a, b) => a + b, 0) / lat.length);
  console.log(`  mean ${avg}ms`);
  console.log(`  => ${avg < 50 ? 'responsive' : 'LATE - the main thread is saturated'}`);
}
await o.close();
