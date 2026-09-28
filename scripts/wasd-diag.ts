/**
 * WASD diagnostic. The movement harness in observe.ts measures RATE, which can
 * be perfect while the controls still feel wrong to a person. This checks the
 * things a rate test cannot see: whether a click is required before the keys
 * respond, whether each key moves the player the way the screen reads, whether
 * the camera turns with the key, and whether a click also swings a tool.
 */
import { observe } from './observe-lib';

const o = await observe();
const { page } = o;

interface LiveState {
  player: { position: { x: number; y: number }; facing: string };
}
interface LiveScene {
  firstPerson?: boolean;
}

const pos = (): Promise<{ x: number; y: number; facing: string }> =>
  page.evaluate(() => {
    const st = (window as unknown as { __EH__: { store: { state: LiveState } } }).__EH__.store.state;
    return { x: st.player.position.x, y: st.player.position.y, facing: st.player.facing };
  });

const camYaw = (): Promise<boolean | null> =>
  page.evaluate(() => {
    const s = (window as unknown as { __EH_SCENE__?: LiveScene }).__EH_SCENE__;
    return s && typeof s.firstPerson !== 'undefined' ? s.firstPerson : null;
  });

console.log('=== A. does WASD respond with NO click first (fresh load) ===');
{
  const before = await pos();
  await page.keyboard.down('w');
  await page.waitForTimeout(700);
  await page.keyboard.up('w');
  await page.waitForTimeout(150);
  const after = await pos();
  const dx = after.x - before.x;
  const dy = after.y - before.y;
  console.log(
    `  held W 700ms, never clicked: (${before.x},${before.y}) -> (${after.x},${after.y}) dx=${dx} dy=${dy} facing=${after.facing}`,
  );
  console.log(`  => ${dx === 0 && dy === 0 ? 'NOTHING MOVED - a click/focus is required' : 'moved without a click'}`);
}

console.log('\n=== B. first-frame latency: how long from keydown to first movement ===');
{
  const samples: number[] = [];
  for (let i = 0; i < 4; i += 1) {
    const b = await pos();
    const t0 = Date.now();
    await page.keyboard.down('s');
    // poll until the store reports movement
    let moved = false;
    for (let k = 0; k < 60; k += 1) {
      const p = await pos();
      if (p.y !== b.y || p.x !== b.x) {
        moved = true;
        break;
      }
      await page.waitForTimeout(8);
    }
    if (moved) samples.push(Date.now() - t0);
    await page.keyboard.up('s');
    await page.waitForTimeout(400);
  }
  console.log(`  keydown -> first movement, ${samples.length} samples: ${samples.join('ms, ')}ms`);
}

console.log('\n=== C. does each key move the way the screen reads, and turn the camera ===');
for (const [k, expect] of [
  ['w', 'up'],
  ['s', 'down'],
  ['a', 'left'],
  ['d', 'right'],
] as const) {
  const b = await pos();
  await page.keyboard.down(k);
  await page.waitForTimeout(650);
  await page.keyboard.up(k);
  await page.waitForTimeout(200);
  const a = await pos();
  const dx = Math.round((a.x - b.x) * 100) / 100;
  const dy = Math.round((a.y - b.y) * 100) / 100;
  const okFacing = a.facing === expect;
  console.log(
    `  ${k.toUpperCase()}: dx=${String(dx).padStart(6)} dy=${String(dy).padStart(6)} facing=${a.facing.padEnd(5)} expect=${expect.padEnd(5)} ${okFacing ? 'OK' : 'MISMATCH'}`,
  );
}

console.log('\n=== D. first person or top down on load ===');
console.log(`  __EH_SCENE__ available: ${(await camYaw()) !== null}`);

console.log('\n=== E. does a click ALSO swing a tool (click to focus costs a swing)? ===');
{
  const placedCount = (): Promise<number> =>
    page.evaluate(() => {
      const st = (window as unknown as { __EH__: { store: { state: { maps: { farm: { placed: object } } } } } })
        .__EH__.store.state;
      return Object.keys(st.maps.farm.placed).length;
    });
  const placedBefore = await placedCount();
  await page.mouse.click(640, 400);
  await page.waitForTimeout(500);
  const placedAfter = await placedCount();
  console.log(`  one left click: placed objects ${placedBefore} -> ${placedAfter} ${placedAfter > placedBefore ? '(CLICK SWUNG A TOOL)' : '(no side effect)'}`);
}

console.log('\n=== F. do the arrow keys also move? ===');
for (const k of ['ArrowUp', 'ArrowLeft']) {
  const b = await pos();
  await page.keyboard.down(k);
  await page.waitForTimeout(600);
  await page.keyboard.up(k);
  await page.waitForTimeout(150);
  const a = await pos();
  console.log(`  ${k}: dx=${Math.round((a.x - b.x) * 100) / 100} dy=${Math.round((a.y - b.y) * 100) / 100}`);
}

console.log('\n=== G. is there an overlay telling the player to click first? ===');
console.log(
  '  ' +
    JSON.stringify(
      await page.evaluate(() => {
        const el = document.querySelector('#game-root');
        const t = (el?.textContent ?? '').replace(/\s+/g, ' ').trim();
        return t.slice(0, 220);
      }),
    ),
);

await o.close();
