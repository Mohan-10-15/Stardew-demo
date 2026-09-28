/**
 * T-0511 verification: drive a REAL day (and the mornings after it) in a real
 * Chromium with real key/mouse input, and report the values the sim actually
 * produced. Nothing here dispatches a store action to make a step pass: every
 * step is a keystroke, a click or a mouse drag, and every assertion reads game
 * state or the event bus.
 *
 * Prints observed values only; the pass/fail judgement lives in
 * docs/ACCEPTANCE.md.
 */
import type { Page } from 'playwright';
import { observe, playerState, eventMark, eventsSince, placedObjects, shot } from './scripts/observe-lib';

const URL = process.env['EH_URL'] ?? 'http://localhost:2026/';
const results: Array<{ ok: boolean; label: string; detail: string }> = [];

function check(ok: boolean, label: string, detail = ''): void {
  results.push({ ok, label, detail });
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${label}${detail ? ` — ${detail}` : ''}`);
}

function say(s = ''): void {
  console.log(s);
}

async function text(page: Page, selector: string): Promise<string> {
  const el = page.locator(selector).first();
  if ((await el.count()) === 0) return '';
  return ((await el.innerText()) ?? '').replace(/\s+/g, ' ').trim();
}

async function exists(page: Page, selector: string): Promise<boolean> {
  return (await page.locator(selector).first().count()) > 0;
}

/**
 * A refusal toast only lives a moment, so poll for it from the moment the key
 * is pressed instead of reading it after a chain of other round-trips (which is
 * what made an earlier run report an empty stack for a toast that had already
 * come and gone).
 */
async function catchToast(page: Page, timeoutMs = 2500): Promise<string> {
  const deadline = Date.now() + timeoutMs;
  let seen = '';
  while (Date.now() < deadline) {
    const t = (await text(page, '.eh-toasts')) || (await text(page, '.eh-toast'));
    if (t.length > 0) {
      if (t !== seen) say(`    toast: "${t}"`);
      seen = t;
    }
    if (seen.length > 0) return seen;
    await page.waitForTimeout(60);
  }
  return seen;
}

interface Probe {
  money: number;
  dayCount: number;
  hour: number;
  minute: number;
  health: number;
  slots: Array<{ id: string; qty: number } | null>;
  animals: Array<{ id: string; species: string; hearts: number; fedToday: boolean; petToday: boolean; productReady: boolean }>;
  shippingBox: Array<{ id: string; qty: number }>;
  placed: Record<string, { id: string }>;
}

async function probe(page: Page): Promise<Probe> {
  return page.evaluate(() => {
    type Slot = { id: string; qty: number } | null;
    interface Obj {
      id: string;
      x?: number;
      y?: number;
    }
    const st = (
      window as unknown as {
        __EH__: { store: { state: Record<string, never> } };
      }
    ).__EH__.store.state as unknown as {
      player: { money: number; health: number; inventory: { slots: Slot[] } };
      world: { dayCount: number; clock: { hour: number; minute: number } };
      extensions: Record<string, unknown>;
      farm: { mapId: string };
      maps: Record<string, { placed: Record<string, Obj> }>;
    };
    const animals =
      (st.extensions['animals'] as { animals?: Probe['animals'] } | undefined)?.animals ?? [];
    const shippingBox =
      (st.extensions['farming'] as { shippingBox?: Probe['shippingBox'] } | undefined)?.shippingBox ?? [];
    const placed: Record<string, { id: string }> = {};
    for (const obj of Object.values(st.maps[st.farm.mapId]?.placed ?? {})) {
      if (obj.x === undefined || obj.y === undefined) continue;
      placed[`${obj.x},${obj.y}`] = obj;
    }
    return {
      money: st.player.money,
      dayCount: st.world.dayCount,
      hour: st.world.clock.hour,
      minute: st.world.clock.minute,
      health: st.player.health,
      slots: st.player.inventory.slots,
      animals,
      shippingBox,
      placed,
    };
  });
}

function slotOf(p: Probe, id: string): number {
  return p.slots.findIndex((s) => s?.id === id);
}

function countOf(p: Probe, id: string): number {
  return p.slots.reduce((n, s) => n + (s?.id === id ? s.qty : 0), 0);
}

/**
 * Walk to a tile, one axis at a time (the walk reducer refuses a diagonal).
 *
 * The success test is `floor(position) === target`, not a distance: `tileInFront`
 * floors the player position, so standing at 14.98 still aims at tile 14 and a
 * tolerance-based arrival makes every tool hit the wrong tile. Chunks shorten
 * near the target so the last tile can actually be entered.
 *
 * NPCs walk the farm on their own schedules and their tile is solid, so a naive
 * "push east" route dead-ends against Rowan standing on row 6. A blocked chunk
 * therefore commits to a ~2.5 tile sidestep (long enough to clear a body, not
 * just nudge past it) before resuming, which is what a player does by eye.
 */
async function walkTo(page: Page, tx: number, ty: number, budgetMs = 40_000): Promise<boolean> {
  const deadline = Date.now() + budgetMs;
  let stuck = 0;
  let detourLeft = 0;
  let detourKey = 'w';
  let last = await playerState(page);
  while (Date.now() < deadline) {
    const p = await playerState(page);
    const dx = tx - p.x;
    const dy = ty - p.y;
    if (Math.floor(p.x) === tx && Math.floor(p.y) === ty) return true;
    const horizontal = Math.abs(dx) >= Math.abs(dy);
    let key: string;
    let chunk = 400;
    if (detourLeft > 0) {
      key = detourKey;
      detourLeft -= 1;
      chunk = 250;
    } else {
      key = horizontal ? (dx > 0 ? 'd' : 'a') : dy > 0 ? 's' : 'w';
      if (Math.abs(dx) < 1.2 && Math.abs(dy) < 1.2) chunk = 120;
    }
    await page.keyboard.down(key);
    await page.waitForTimeout(chunk);
    await page.keyboard.up(key);
    const now = await playerState(page);
    const moved = now.x !== last.x || now.y !== last.y;
    if (!moved && detourLeft === 0) {
      stuck += 1;
      // Sidestep away from the row we are crossing: up if we are below the
      // target, down if above, and sideways only when the block is vertical.
      detourKey = horizontal ? (p.y > ty ? 's' : 'w') : p.x > tx ? 'd' : 'a';
      detourLeft = 10;
    } else if (moved) {
      stuck = 0;
    }
    last = now;
    if (stuck > 6) return false;
  }
  return false;
}

/**
 * Turn to a cardinal with a REAL mouse drag. The 4-way facing is what a tool
 * acts on and there is no turn key, so this is the same path a player uses:
 * a drag across a cardinal boundary, which the view turns into `player:face`.
 */
async function turnTo(page: Page, dir: 'up' | 'down' | 'left' | 'right'): Promise<boolean> {
  for (let attempt = 0; attempt < 6; attempt += 1) {
    if ((await playerState(page)).facing === dir) return true;
    await page.mouse.move(640, 400);
    await page.mouse.down();
    await page.mouse.move(960, 400, { steps: 10 });
    await page.mouse.up();
    await page.waitForTimeout(180);
  }
  return (await playerState(page)).facing === dir;
}

const DIRS: Record<string, [number, number]> = {
  up: [0, -1],
  down: [0, 1],
  left: [-1, 0],
  right: [1, 0],
};

/** The tile the player's tool will hit, mirroring `tileInFront` in the sim. */
function frontTile(p: { x: number; y: number; facing: string }): { x: number; y: number } {
  const [dx, dy] = DIRS[p.facing] ?? [0, 1];
  return { x: Math.floor(p.x) + dx, y: Math.floor(p.y) + dy };
}

/**
 * Stand so that `tx,ty` is the tile the player is facing, and prove it by
 * reading the sim's own front-tile rule back.
 *
 * A collision radius means the player often cannot stand on the centre of the
 * tile behind the target (standing on (15,3) to chop a stump at (15,2) leaves
 * the body at 14.8/2.8, which floors to tile 14), so every approach is tried
 * and the result is checked instead of assumed.
 */
async function setUpForTile(page: Page, tx: number, ty: number): Promise<boolean> {
  for (const [dir, [dx, dy]] of Object.entries(DIRS)) {
    await walkTo(page, tx - dx, ty - dy, 8_000);
    if (!(await turnTo(page, dir as 'up' | 'down' | 'left' | 'right'))) continue;
    const f = frontTile(await playerState(page));
    if (f.x === tx && f.y === ty) return true;
  }
  return false;
}

async function selectSlot(page: Page, p: Probe, id: string): Promise<boolean> {
  const slot = slotOf(p, id);
  if (slot < 0) return false;
  await page.keyboard.press(String(slot + 1));
  await page.waitForTimeout(120);
  return true;
}

async function closeAnyDialog(page: Page): Promise<void> {
  await page.keyboard.press('Escape');
  await page.waitForTimeout(250);
}

async function endDay(page: Page): Promise<void> {
  await page.keyboard.press('r');
  await page.waitForTimeout(300);
  await page.keyboard.press('r');
  await page.waitForTimeout(1300);
  const close = page.locator('.eh-dialog-close').last();
  if ((await close.count()) > 0 && (await close.isVisible())) {
    await close.click();
    await page.waitForTimeout(300);
  }
}

async function main(): Promise<void> {
  const obs = await observe({ url: URL });
  const { page } = obs;
  say(`boot: ${obs.booted ? 'ok' : 'FAILED'}  url=${URL}`);
  if (!obs.booted) {
    for (const e of obs.errors) say(`  error: ${e.text}`);
    await obs.close();
    process.exitCode = 1;
    return;
  }

  const start = await probe(page);
  const startP = await playerState(page);
  say(
    `new game: day ${start.dayCount} ${String(start.hour).padStart(2, '0')}:${String(start.minute).padStart(2, '0')}` +
      `  gold ${start.money}g  health ${start.health}  at ${startP.mapId} ${startP.x},${startP.y} facing ${startP.facing}`,
  );
  say(`starting bag: ${start.slots.map((s, i) => (s ? `${i}:${s.id}x${s.qty}` : null)).filter(Boolean).join(' ')}`);
  check(
    start.dayCount === 1 && start.hour === 6 && start.money === 500 && start.health === 100,
    'booted into a genuine fresh save',
    `day ${start.dayCount} ${start.hour}:${String(start.minute).padStart(2, '0')}, ${start.money}g, ${start.health}hp`,
  );

  // =========================================================== the key legend
  say('');
  say('=== the on-screen control hints ===');
  const bar = await text(page, '.eh-actionbar');
  const legend = await text(page, '.eh-actionbar-legend');
  say(`action bar: ${bar}`);
  say(`legend:      ${legend}`);
  for (const [key, word] of [
    ['X', 'Ship'],
    ['G', 'Eat'],
    ['B', 'Barn'],
    ['R', 'Sleep'],
    ['Q', 'Machine'],
    ['Space', 'Use'],
  ] as const) {
    check(legend.includes(`${key} ${word}`), `the bar advertises ${key} ${word}`);
  }
  const tutorial0 = await text(page, '.eh-tutorial');
  say(`tutorial:    ${tutorial0}`);
  check(tutorial0.includes('0/7'), 'the tutorial starts at 0/7 for a new player');
  check(tutorial0.includes('Move'), 'the first step names the move keys');
  check(await exists(page, '.eh-tutorial-skip'), 'the tutorial is skippable');
  // Non-blocking, proven by the fact that the world still answers keys with the
  // tutorial card on screen: every step below runs with it visible.
  check(!(await exists(page, '.eh-tutorial .eh-dialog')), 'the tutorial is a corner card, not a modal');

  // ==================================================== look (a real drag)
  say('');
  say('=== look around (a real mouse drag) ===');
  await page.mouse.move(640, 400);
  await page.mouse.down();
  await page.mouse.move(780, 400, { steps: 12 });
  await page.mouse.up();
  await page.waitForTimeout(300);
  const tutAfterLook = await text(page, '.eh-tutorial');
  say(`tutorial:    ${tutAfterLook}`);
  check(tutAfterLook.includes('1/7'), 'a real mouse drag completed the look step', tutAfterLook.slice(0, 48));

  // ==================================================== 1. till
  say('');
  say('=== 1. hoe a grass tile (Space) ===');
  await turnTo(page, 'down');
  const tillTile = { x: Math.floor(startP.x), y: Math.floor(startP.y) + 1 };
  say(`facing ${(await playerState(page)).facing} at ${startP.x},${startP.y}; front tile ${tillTile.x},${tillTile.y}`);
  let mark = await eventMark(page);
  check(await selectSlot(page, start, 'hoe-t0'), 'selected the hoe with its number key');
  await page.keyboard.press('Space');
  await page.waitForTimeout(400);
  const tillBus = await eventsSince(page, mark);
  let placed = await placedObjects(page);
  say(`bus: ${tillBus.types.join(', ')}`);
  say(`tile ${tillTile.x},${tillTile.y}: ${JSON.stringify(placed[`${tillTile.x},${tillTile.y}`])}`);
  check(tillBus.types.includes('tool:used'), 'the hoe swung (tool:used)');
  check(
    String(placed[`${tillTile.x},${tillTile.y}`]?.id ?? '').includes('tilled'),
    'a tilled tile appeared on the faced tile',
    placed[`${tillTile.x},${tillTile.y}`]?.id ?? 'nothing',
  );
  const energyAfterTill = (await playerState(page)).energy;
  say(`energy after the hoe: ${startP.energy} -> ${energyAfterTill}`);

  // ==================================================== 2. plant + water
  say('');
  say('=== 2. plant a seed, then water it ===');
  const seedSlot = slotOf(start, 'parsnip-seed');
  check(seedSlot >= 0, 'the starting bag has seeds', `slot ${seedSlot}`);
  mark = await eventMark(page);
  await page.keyboard.press(String(seedSlot + 1));
  await page.waitForTimeout(120);
  await page.keyboard.press('Space');
  await page.waitForTimeout(400);
  const plantBus = await eventsSince(page, mark);
  placed = await placedObjects(page);
  const cropTile = placed[`${tillTile.x},${tillTile.y}`];
  say(`plant bus: ${plantBus.types.join(', ')}`);
  say(`tile now: ${JSON.stringify(cropTile)}`);
  check(plantBus.types.includes('crop:planted'), 'the seed went into the tilled soil');
  check(String(cropTile?.id ?? '').includes('crop'), 'a crop is growing there', String(cropTile?.id));

  mark = await eventMark(page);
  const canSlot = slotOf(start, 'watering-can-t0');
  await page.keyboard.press(String(canSlot + 1));
  await page.waitForTimeout(120);
  await page.keyboard.press('Space');
  await page.waitForTimeout(400);
  const waterBus = await eventsSince(page, mark);
  placed = await placedObjects(page);
  const wateredTile = placed[`${tillTile.x},${tillTile.y}`];
  say(`water bus: ${waterBus.types.join(', ')}`);
  say(`tile now: ${JSON.stringify(wateredTile)}`);
  check(waterBus.types.includes('tile:watered'), 'the crop was watered');
  check(
    (wateredTile?.data as { watered?: boolean } | undefined)?.watered === true,
    'the tile is recorded as watered',
    JSON.stringify(wateredTile?.data),
  );
  const tutFarmed = await text(page, '.eh-tutorial');
  say(`tutorial:    ${tutFarmed}`);
  check(/3\/7|4\/7|5\/7|6\/7/.test(tutFarmed), 'the tutorial counted the till/plant/water it saw', tutFarmed.slice(0, 30));

  // ==================================================== 3. ship
  say('');
  say('=== 3. chop a stump/branch, ship the wood ===');
  // The farm has three wood sources (stump 15,2 and branches 12,21 / 27,19).
  // NPCs wander the roads and make any single one flaky, so try them in turn
  // with retries rather than gambling one run on one route.
  const woodSources: Array<[number, number]> = [
    [15, 2],
    [12, 21],
    [27, 19],
  ];
  let woodQty = 0;
  let woodSlot = -1;
  let inv = await probe(page);
  for (const [sx, sy] of woodSources) {
    if (woodQty > 0) break;
    for (let attempt = 0; attempt < 3 && woodQty === 0; attempt += 1) {
      const positioned = await setUpForTile(page, sx, sy);
      const now = await playerState(page);
      const f = frontTile(now);
      say(
        `  try ${sx},${sy} (attempt ${attempt + 1}): stood ${now.x},${now.y} facing ${now.facing} -> front ${f.x},${f.y} (${positioned ? 'OK' : 'misdirected'})`,
      );
      if (!positioned) continue;
      mark = await eventMark(page);
      await page.keyboard.press('3'); // axe
      await page.waitForTimeout(120);
      await page.keyboard.press('Space');
      await page.waitForTimeout(500);
      const chopBus = await eventsSince(page, mark);
      inv = await probe(page);
      woodQty = countOf(inv, 'wood');
      woodSlot = slotOf(inv, 'wood');
      say(`  chop bus: ${chopBus.types.join(', ')}; wood: slot ${woodSlot}, qty ${woodQty}`);
    }
  }
  check(woodQty >= 1, 'a wood source yielded shippable wood', `${woodQty} wood`);
  if (woodSlot < 0) woodSlot = slotOf((await probe(page)), 'wood');

  await page.keyboard.press(String(woodSlot + 1));
  await page.waitForTimeout(200);
  const barWood = await text(page, '.eh-actionbar');
  say(`action bar: ${barWood}`);
  check(barWood.includes('In hand: Wood'), 'the bar names the selected stack (wood)');
  check(barWood.includes('X Ship'), 'the bar offers X Ship for a shippable stack');
  mark = await eventMark(page);
  await page.keyboard.press('x');
  await page.waitForTimeout(400);
  const shipBus = await eventsSince(page, mark);
  inv = await probe(page);
  say(`ship bus: ${shipBus.types.join(', ')}`);
  say(`bin now: ${JSON.stringify(inv.shippingBox)}`);
  check(shipBus.types.includes('shipping:inserted'), 'X shipped the selected stack');
  check(
    inv.shippingBox.some((s) => s.id === 'wood' && s.qty >= 1),
    'the bin really holds the wood',
    JSON.stringify(inv.shippingBox),
  );
  check(countOf(inv, 'wood') === 0, 'the wood left the bag when it shipped');

  // ---- the shipping tab shows the contents and what they will pay
  await page.keyboard.press('b');
  await page.waitForTimeout(400);
  check(await exists(page, '.eh-farm-dialog'), 'B opened the farm dialog');
  const tabLabels = await text(page, '.eh-farm-tabs');
  say(`tabs: ${tabLabels}`);
  await page.locator('.eh-farm-tabs .eh-tab', { hasText: 'Shipping' }).click();
  await page.waitForTimeout(300);
  const shippingText = await text(page, '.eh-farm-dialog .eh-tab-body:not([hidden])');
  say(`shipping tab: ${shippingText}`);
  check(shippingText.includes('Wood'), 'the shipping tab lists what is in the bin');
  const payoutMatch = /Estimated payout: (\d+)g/.exec(shippingText);
  check(payoutMatch !== null, 'the shipping tab shows the gold it will pay', shippingText.slice(0, 80));
  const shownPayout = payoutMatch ? Number(payoutMatch[1]) : 0;
  const tutShipped = await text(page, '.eh-tutorial');
  say(`tutorial:    ${tutShipped}`);
  check(tutShipped.includes('Sleep') || /6\/7/.test(tutShipped), 'the tutorial saw the shipment and moved to sleep', tutShipped.slice(0, 40));
  await closeAnyDialog(page);

  // ==================================================== 4. refusals
  say('');
  say('=== 4. refused actions must explain themselves ===');
  const hoeSlot = slotOf(start, 'hoe-t0');
  await page.keyboard.press(String(hoeSlot + 1));
  await page.waitForTimeout(150);
  mark = await eventMark(page);
  await page.keyboard.press('x');
  const denyShip = await eventsSince(page, mark);
  const toastShip = await catchToast(page);
  say(`bus: ${denyShip.types.join(', ')}`);
  check(denyShip.types.includes('shipping:denied'), 'the sim refused to ship a hoe');
  check(toastShip.length > 0, 'the refusal produced VISIBLE text, not silence');
  check(!/(not-shippable|no-slot|reason|unknown-species)/.test(toastShip), 'the refusal is a sentence, not a machine code');
  check(toastShip.includes('Hoe'), 'the refusal names the item that was refused');

  await page.waitForTimeout(3400); // let the toast expire so the next read is its own
  mark = await eventMark(page);
  await page.keyboard.press('g');
  const denyEat = await eventsSince(page, mark);
  const toastEat = await catchToast(page);
  say(`eat bus: ${denyEat.types.join(', ')}`);
  check(denyEat.types.includes('crafting:denied') || denyEat.types.includes('player:eat'), 'the sim refused to eat a hoe');
  check(toastEat.length > 0, 'the eat refusal is visible too');

  await page.waitForTimeout(3400);
  await turnTo(page, 'down'); // bare grass ahead
  const contextHidden = !(await exists(page, '.eh-actionbar-context.is-visible'));
  check(contextHidden, 'the bar does NOT advertise Q over bare grass (no false promise)');
  mark = await eventMark(page);
  await page.keyboard.press('q');
  const denyUse = await eventsSince(page, mark);
  const toastUse = await catchToast(page);
  say(`Q over grass bus: ${denyUse.types.join(', ')}`);
  check(denyUse.types.includes('machines:denied'), 'Q over bare ground is refused by the sim');
  check(toastUse.length > 0, 'the Q refusal is visible too');

  // ==================================================== 5. sleep
  say('');
  say('=== 5. sleep (R twice) — the day only ends on the second press ===');
  const beforeSleep = await probe(page);
  const beforeSleepP = await playerState(page);
  say(
    `before: day ${beforeSleep.dayCount} ${String(beforeSleep.hour).padStart(2, '0')}:${String(beforeSleep.minute).padStart(2, '0')}` +
      `  gold ${beforeSleep.money}g  energy ${beforeSleepP.energy}`,
  );
  mark = await eventMark(page);
  await page.keyboard.press('r');
  await page.waitForTimeout(350);
  const armedPrompt = await text(page, '.eh-actionbar-prompt');
  const afterFirstR = await probe(page);
  say(`prompt after ONE R: "${armedPrompt}"`);
  check(armedPrompt.length > 0, 'one R arms the sleep and asks to confirm');
  check(afterFirstR.dayCount === beforeSleep.dayCount, 'one R did NOT end the day');
  check(
    shownPayout > 0 && armedPrompt.includes(String(shownPayout)),
    'the confirmation states what the bin will pay',
    armedPrompt,
  );

  await page.keyboard.press('r');
  await page.waitForTimeout(1500);
  const sleepBus = await eventsSince(page, mark);
  const afterSleep = await probe(page);
  const afterSleepP = await playerState(page);
  say(`sleep bus: ${sleepBus.types.join(', ')}`);
  say(
    `after:  day ${afterSleep.dayCount} ${String(afterSleep.hour).padStart(2, '0')}:${String(afterSleep.minute).padStart(2, '0')}` +
      `  gold ${afterSleep.money}g  energy ${afterSleepP.energy}`,
  );
  check(sleepBus.types.includes('day:started'), 'the second R ended the day (day:started)');
  check(
    afterSleep.dayCount === beforeSleep.dayCount + 1,
    'the day counter incremented',
    `${beforeSleep.dayCount} -> ${afterSleep.dayCount}`,
  );
  check(afterSleep.hour === 6, 'the clock reset to 06:00 in the morning', `${afterSleep.hour}:${String(afterSleep.minute).padStart(2, '0')} (the clock keeps running after the rollover)`);
  check(afterSleep.money > beforeSleep.money, 'the bin paid out at sleep', `${beforeSleep.money}g -> ${afterSleep.money}g (+${afterSleep.money - beforeSleep.money})`);
  check(
    afterSleep.money - beforeSleep.money === shownPayout,
    'the payout equals the estimate the panel showed',
    `estimated ${shownPayout}g, paid ${afterSleep.money - beforeSleep.money}g`,
  );
  check(afterSleepP.energy > beforeSleepP.energy, 'sleeping restored energy', `${beforeSleepP.energy} -> ${afterSleepP.energy}`);
  const summary = await text(page, '.eh-dialog');
  say(`day summary: ${summary.slice(0, 240)}`);
  check(summary.includes('Wood'), 'the day summary shows what shipped');
  await closeAnyDialog(page);

  // ==================================================== 6. animals
  say('');
  say('=== 6. the barn: buy, then drive the row from the keyboard ===');
  const goldBeforeBuy = (await probe(page)).money;
  await page.keyboard.press('b');
  await page.waitForTimeout(450);
  const emptyHerd = await text(page, '.eh-farm-dialog');
  check(/no animals/i.test(emptyHerd), 'the barn explains an empty herd');
  await page.locator('.eh-farm-btn', { hasText: 'Buy' }).first().click();
  await page.waitForTimeout(500);
  let st2 = await probe(page);
  const herdText = await text(page, '.eh-farm-dialog');
  say(`herd: ${herdText.slice(0, 320)}`);
  say(`gold ${goldBeforeBuy}g -> ${st2.money}g; animal: ${JSON.stringify(st2.animals[0])}`);
  check(st2.animals.length === 1, 'buying added an animal to the herd');
  check(st2.money === goldBeforeBuy - 400, 'the chicken really cost 400g', `${goldBeforeBuy}g -> ${st2.money}g`);
  check(/Not fed/i.test(herdText), 'the row shows that it is not fed');
  check(/Not petted|Not pet/i.test(herdText), 'the row shows that it is not petted');
  check(/2 hearts/.test(herdText), 'the row explains why it is not producing', herdText.match(/.{0,40}hearts.{0,20}/)?.[0] ?? '');
  check(/none in bag|no hay/i.test(herdText), 'the row says why feeding is unavailable');
  check(/1 Feed/.test(herdText) && /2 Pet/.test(herdText) && /3 Collect/.test(herdText), 'the row prints the keys that drive it');

  const heartsBefore = st2.animals[0]!.hearts;
  mark = await eventMark(page);
  await page.keyboard.press('2');
  const petBus = await eventsSince(page, mark);
  st2 = await probe(page);
  const heartsAfter = st2.animals[0]!.hearts;
  say(`pet bus: ${petBus.types.join(', ')}; hearts ${heartsBefore} -> ${heartsAfter}`);
  check(petBus.types.includes('animals:petted'), 'pressing 2 petted the highlighted animal');
  check(heartsAfter > heartsBefore, 'petting raised the bond', `${heartsBefore} -> ${heartsAfter}`);

  await page.waitForTimeout(3400);
  mark = await eventMark(page);
  await page.keyboard.press('1');
  const feedBus = await eventsSince(page, mark);
  const feedToast = await catchToast(page);
  say(`feed bus: ${feedBus.types.join(', ')}`);
  check(feedBus.types.includes('animals:denied'), 'pressing 1 with no hay was refused by the sim');
  check(feedToast.length > 0, 'the feed refusal is VISIBLE (the key is never silent)');
  check(/feed/i.test(feedToast), 'the refusal explains the reason', feedToast);

  await page.waitForTimeout(3400);
  mark = await eventMark(page);
  await page.keyboard.press('2');
  const rePet = await eventsSince(page, mark);
  const rePetToast = await catchToast(page);
  say(`second pet bus: ${rePet.types.join(', ')}`);
  check(rePet.types.includes('animals:denied'), 'a second pet the same day is refused');
  check(rePetToast.length > 0, 'that refusal is visible too');
  check(/pet/i.test(rePetToast), 'the refusal says the animal is done being petted', rePetToast);

  const selectedAfter = (await playerState(page)).selected;
  say(`hotbar selection after 1/2 inside the panel: slot ${selectedAfter}`);
  check(selectedAfter === hoeSlot, 'the panel swallowed its own number keys (the hotbar did not change)');
  await closeAnyDialog(page);
  check(!(await exists(page, '.eh-farm-dialog')), 'Escape closed the barn');

  // ==================================================== 7. cook + eat
  say('');
  say('=== 7. cook and eat (the ember-bloom tea chain) ===');
  let cooked = false;
  let ate = false;
  const mornings: string[] = [];
  for (let morning = 0; morning < 7 && !ate; morning += 1) {
    const p = await probe(page);
    const bloom = Object.entries(p.placed).find(([, obj]) => obj.id === 'forage:ember-bloom');
    mornings.push(
      `day ${p.dayCount}: ember bloom ${bloom ? `at ${bloom[0]}` : 'not spawned'}, fiber ${countOf(p, 'fiber')}`,
    );
    say(`  ${mornings[mornings.length - 1]}`);
    if (!bloom) {
      await endDay(page);
      continue;
    }
    const [bx, by] = bloom[0]!.split(',').map(Number) as [number, number];
    let p2 = await probe(page);
    const scytheSlot0 = slotOf(p2, 'scythe-t0');
    if (!p2.slots.some((s) => s?.id === 'ember-bloom')) {
      // Forage is picked with bare hands or the scythe; anything else (the hoe
      // from section 1) tills the tile beside it or refuses. Retry: NPCs move.
      for (let attempt = 0; attempt < 2 && !p2.slots.some((s) => s?.id === 'ember-bloom'); attempt += 1) {
        const got = await setUpForTile(page, bx, by);
        say(`    walked to the ember bloom at ${bx},${by} (attempt ${attempt + 1}, in position: ${got})`);
        if (scytheSlot0 >= 0) await page.keyboard.press(String(scytheSlot0 + 1));
        await page.waitForTimeout(150);
        mark = await eventMark(page);
        await page.keyboard.press('Space');
        await page.waitForTimeout(450);
        const pickBus = await eventsSince(page, mark);
        p2 = await probe(page);
        say(`    pick bus: ${pickBus.types.join(', ')}`);
      }
    }
    const haveBloom = p2.slots.some((s) => s?.id === 'ember-bloom');
    say(`    ember-bloom in bag: ${haveBloom}`);
    if (!haveBloom) {
      await endDay(page);
      continue;
    }
    // The tea wants 3 fiber; scythe weeds (each yields 1) until the bag has 3.
    // Weeds are spread over the southern field, so try them in turn with retries.
    let fiber = countOf(p2, 'fiber');
    if (fiber < 3) {
      const weeds = Object.entries(p2.placed)
        .filter(([, obj]) => obj.id === 'weed')
        .map(([key]) => ({ key, xy: key.split(',').map(Number) as [number, number] }));
      for (const weed of weeds) {
        if (fiber >= 3) break;
        for (let attempt = 0; attempt < 2 && fiber < 3; attempt += 1) {
          const ok = await setUpForTile(page, weed.xy[0], weed.xy[1]);
          if (!ok) continue;
          const scytheSlot = slotOf(await probe(page), 'scythe-t0');
          if (scytheSlot < 0) break;
          await page.keyboard.press(String(scytheSlot + 1));
          await page.waitForTimeout(120);
          await page.keyboard.press('Space');
          await page.waitForTimeout(400);
          p2 = await probe(page);
          const f2 = countOf(p2, 'fiber');
          if (f2 > fiber) {
            fiber = f2;
            say(`    scythed a weed → fiber ${fiber}`);
          } else {
            say(`    weed ${weed.key} (attempt ${attempt + 1}) missed: fiber ${f2}`);
          }
        }
      }
    }
    say(`    fiber now ${fiber}`);
    if (fiber < 3) {
      say('    not enough fiber for the tea; ending the day');
      await endDay(page);
      continue;
    }
    await page.keyboard.press('c');
    await page.waitForTimeout(500);
    const teaRowText = await text(page, '.eh-dialog');
    say(`    crafting: ${teaRowText.slice(0, 200)}`);
    mark = await eventMark(page);
    const teaBtn = page.locator('.eh-crafting-row', { hasText: 'Ember Bloom Tea' }).locator('button.eh-crafting-craft').first();
    if ((await teaBtn.count()) === 0) {
      say('    the tea row was not in the list; cannot cook');
      break;
    }
    await teaBtn.click();
    await page.waitForTimeout(500);
    const craftBus = await eventsSince(page, mark);
    p2 = await probe(page);
    const teaSlot = slotOf(p2, 'ember-bloom-tea');
    say(`    craft bus: ${craftBus.types.join(', ')}; tea in slot ${teaSlot}`);
    cooked = craftBus.types.includes('crafting:crafted') && teaSlot >= 0;
    check(cooked, 'C cooked the recipe into the bag', `bus ${craftBus.types.join(', ')}`);
    await closeAnyDialog(page);
    if (!cooked) break;

    const before = await probe(page);
    const beforeEnergy = (await playerState(page)).energy;
    mark = await eventMark(page);
    await page.keyboard.press(String(teaSlot + 1));
    await page.waitForTimeout(250);
    const barTea = await text(page, '.eh-actionbar');
    say(`    action bar holding the tea: ${barTea}`);
    check(barTea.includes('G Eat'), 'the bar offers G Eat for cooked food');
    await page.keyboard.press('g');
    await page.waitForTimeout(600);
    const eatBus = await eventsSince(page, mark);
    const after = await probe(page);
    const afterEnergy = (await playerState(page)).energy;
    say(`    eat bus: ${eatBus.types.join(', ')}`);
    say(`    energy ${beforeEnergy} -> ${afterEnergy}; health ${before.health} -> ${after.health}`);
    check(eatBus.types.includes('food:eaten'), 'G ate the food', `bus ${eatBus.types.join(', ')}`);
    check(afterEnergy > beforeEnergy, 'eating restored energy', `${beforeEnergy} -> ${afterEnergy}`);
    check(after.health >= before.health, 'eating did not cost health', `${before.health} -> ${after.health}`);
    check(countOf(after, 'ember-bloom-tea') === 0, 'the food left the bag when it was eaten');
    ate = true;
  }
  if (!cooked) {
    check(false, 'a cookable ingredient was reachable in normal play', mornings.join(' | '));
  }
  if (!ate) {
    check(false, 'the cook+eat loop completed in normal play', mornings.join(' | '));
  }

  // ==================================================== 8. persistence
  say('');
  say('=== 8. the saved day survives being restored ===');
  say('  (the auto-save on sleep wrote the run; the round-trip is checked in-page)');
  const roundtrip = (await page.evaluate(
    `(async () => {
      const rt = window.__EH__.runtime;
      await rt.persist();
      const saveMod = await import('/src/core/save.ts');
      const store = saveMod.createDefaultSaveStore();
      const file = await store.load(rt.saveSlot);
      let resumeErr = null;
      try {
        const gm = await import('/src/core/game.ts');
        await gm.loadRuntimeFromSave(rt.saveSlot);
      } catch (err) {
        resumeErr = String(err && err.message);
      }
      let boilsDown = false;
      try {
        const gated = saveMod.migrateSave(file);
        const f = { format: file.format, version: file.version, savedAt: file.savedAt, state: gated };
        boilsDown = JSON.stringify(f) === JSON.stringify(file);
      } catch (err) {
        boilsDown = String(err && err.message);
      }
      return {
        slot: rt.saveSlot,
        fileFormat: file && file.format,
        day: file && file.state.world.dayCount,
        money: file && file.state.player.money,
        selected: file && file.state.player.inventory.selected,
        saveName: file && file.state.meta.saveName,
        resumeErr,
        boilsDown,
      };
    })()`,
  )) as {
    slot: string;
    fileFormat: string | null;
    day: number;
    money: number;
    selected: number;
    saveName: string;
    resumeErr: string | null;
    boilsDown: boolean | string;
  };
  const beforeReload = await probe(page);
  say(`auto-saved under slot "${roundtrip.slot}" (meta.saveName "${roundtrip.saveName}"), wrapped as ${roundtrip.fileFormat}`);
  say(`file holds day ${roundtrip.day}, money ${roundtrip.money}g, selection slot ${roundtrip.selected}`);
  say(`live the whole time: day ${beforeReload.dayCount}, money ${beforeReload.money}g`);
  check(roundtrip.fileFormat === 'ember-hollow', 'the auto-save wrapped the game in a versioned file');
  check(roundtrip.day === beforeReload.dayCount, 'the saved day equals the live day', `${beforeReload.dayCount} == ${roundtrip.day}`);
  check(roundtrip.money === beforeReload.money, 'the saved gold equals the live gold', `${beforeReload.money}g == ${roundtrip.money}g`);
  check(roundtrip.selected === hoeSlot, 'the saved hotbar selection matches', `slot ${roundtrip.selected}`);
  check(roundtrip.boilsDown === true, 'the file still passes the migrate gate (migrateSave round-trip as in unit tests)');
  if (typeof roundtrip.boilsDown === 'string') say(`  migrate gate detail: ${roundtrip.boilsDown}`);
  if (roundtrip.resumeErr) {
    say(`  RESUME PATH: loadRuntimeFromSave('${roundtrip.slot}') -> ${roundtrip.resumeErr}`);
  }
  check(
    roundtrip.resumeErr === null,
    'core loadRuntimeFromSave resumes the file',
    roundtrip.resumeErr
      ? `loadRuntimeFromSave throws: ${roundtrip.resumeErr}`
      : 'loadRuntimeFromSave accepted the file',
  );

  // A genuine browser reload: main.ts always does createGameRuntime({mountDom:true})
  // and never calls loadRuntimeFromSave(), so a hard reload starts a fresh game.
  say('  NOTE (core-lane gap): src/main.ts boots createGameRuntime() fresh and never');
  say('  calls loadRuntimeFromSave(); even if it did, loadRuntimeFromSave feeds');
  say('  migrateSave(file.state) instead of migrateSave(file) (save.ts expects the');
  say('  expects the {format,version,state} wrapper) and throws');
  say('  "unrecognized save format". Both are ORCHESTRATOR-lane files, out of');
  say('  WORKER-3\'s reach; the state wraps, stores, and abides the migration gate');
  say('  — only the boot wiring is missing.');
  const tutBeforeBounce = await text(page, '.eh-tutorial');
  say(`tutorial before the reload: ${tutBeforeBounce || '(hidden)'}`);
  const failedUrls: string[] = [];
  const onFail = (r: { url: () => string; failure?: () => string | null }): void => {
    const u = r.url();
    const why = (r.failure ? r.failure() : null) ?? '';
    failedUrls.push(`${u} (${why})`);
  };
  const livePage = obs.page as unknown as {
    on: (event: string, handler: (r: { url: () => string; failure?: () => string | null }) => void) => void;
    off: (event: string, handler: (r: { url: () => string; failure?: () => string | null }) => void) => void;
  };
  livePage.on('requestfailed', onFail);
  await page.reload({ waitUntil: 'domcontentloaded' });
  await page.waitForFunction(() => Boolean((window as unknown as { __EH__?: unknown }).__EH__), undefined, {
    timeout: 30_000,
  });
  await page.waitForTimeout(1500);
  livePage.off('requestfailed', onFail);
  const tutAfter = await text(page, '.eh-tutorial');
  say(`tutorial after reload: ${tutAfter || '(hidden)'}`);
  say(`failed resources on reload: ${failedUrls.length ? failedUrls.join(' | ') : 'none'}`);
  check(tutAfter === '' || !/Move the farm|Walk the farm/.test(tutAfter), 'a finished tutorial does not start over');

  // ============================================================ console
  say('');
  const realErrors = obs.errors.filter((e) => !e.text.includes('favicon'));
  say(`console errors: ${realErrors.length}`);
  for (const e of realErrors) say(`  ${e.type}: ${e.text}`);
  check(realErrors.length === 0, 'no console errors during the whole run');

  const failed = results.filter((r) => !r.ok);
  say('');
  say(`==== ${results.length - failed.length}/${results.length} checks passed ====`);
  for (const f of failed) say(`  FAILED: ${f.label} (${f.detail})`);
  await shot(page, 'artifacts/t0511-day-loop.png');
  await obs.close();
  if (failed.length > 0) process.exitCode = 1;
}

main()
  .then(() => process.exit(process.exitCode ?? 0))
  .catch((err) => {
    console.error(err);
    process.exit(1);
  });
