/**
 * Day-loop playtest (ORCHESTRATOR, core lane - test infra).
 *
 * `observe.ts` proves the game LOOKS and MOVES right. This proves it is a GAME:
 * that a player can, with real keystrokes, till -> plant -> water -> wait ->
 * harvest -> ship -> cook -> eat -> sleep, and that the day actually advances.
 *
 * Everything here is an observation harness: it drives the real build in a real
 * Chromium and prints what happened. The pass/fail judgement is recorded in
 * docs/ACCEPTANCE.md, checked on top of this.
 *
 * Two things are deliberately NOT faked:
 *  - Every game action is a real `keyboard.press`. Nothing dispatches a sim
 *    action directly, because that is exactly the shortcut that hid the
 *    missing-mapId bug: the unit tests dispatched the payload and never
 *    exercised the emitter the player actually presses.
 *  - Growth is waited out with real sleeps over real days. The script never
 *    fast-forwards a crop stage to save time.
 *
 * `faceTile` teleports the player to line up a camera on a tile. That is
 * harness setup, and it is called out in the transcript wherever it is used;
 * it cannot fake an action, only a stance.
 */
import { observe, playerState, faceTile, neighbourhood, shot } from './observe-lib';

type DirName = 'up' | 'down' | 'left' | 'right';

const DIRS: Record<DirName, [number, number]> = {
  up: [0, -1],
  down: [0, 1],
  left: [-1, 0],
  right: [1, 0],
};

interface Placed {
  id: string;
  x: number;
  y: number;
  data?: Record<string, unknown>;
}

interface Snap {
  money: number;
  energy: number;
  selected: number;
  slots: ({ id: string; qty: number; quality: number } | null)[];
  placed: Record<string, Placed>;
}

const o = await observe();
const { page } = o;
if (!o.booted) {
  console.log('FAIL not-booted');
  await o.close();
  process.exit(1);
}

/** Read the fields the day loop turns on, straight out of the live store. */
async function snap(): Promise<Snap> {
  return page.evaluate(() => {
    interface LiveStack {
      id: string;
      qty: number;
      quality: number;
    }
    interface LiveState {
      player: {
        money: number;
        energy: number;
        inventory: { selected: number; slots: (LiveStack | null)[] };
      };
      maps: { farm: { placed: Record<string, Placed> } };
    }
    const w = window as unknown as { __EH__: { store: { state: LiveState } } };
    const st = w.__EH__.store.state;
    return {
      money: st.player.money,
      energy: st.player.energy,
      selected: st.player.inventory.selected,
      slots: st.player.inventory.slots.map((s) =>
        s ? { id: s.id, qty: s.qty, quality: s.quality } : null,
      ),
      placed: st.maps.farm.placed,
    };
  });
}

const verdicts: { name: string; pass: boolean; detail: string }[] = [];
function verdict(name: string, pass: boolean, detail: string): void {
  verdicts.push({ name, pass, detail });
  console.log(`  ${pass ? 'PASS' : 'FAIL'} ${name} :: ${detail}`);
}
function kv(k: string, v: unknown): void {
  console.log(`  ${k}: ${typeof v === 'object' ? JSON.stringify(v) : String(v)}`);
}
function head(s: string): void {
  console.log(`\n=== ${s} ===`);
}
/** Read the live toast stack, which is the game's own "that did not work" line. */
async function toasts(): Promise<string[]> {
  return page.evaluate(() =>
    [...document.querySelectorAll('.eh-toast')].map((e) => (e.textContent ?? '').trim()),
  );
}
const key = async (k: string): Promise<void> => {
  await page.keyboard.press(k);
  await page.waitForTimeout(220);
};
/** The end of the day is a two-press confirm, so a sleep is two presses. */
const sleepNight = async (): Promise<void> => {
  await key('r');
  await page.waitForTimeout(200);
  await key('r');
  await page.waitForTimeout(500);
};

// --------------------------------------------------------------------- start
head('BOOT');
const p0 = await playerState(page);
const s0 = await snap();
kv('day', p0.dayCount);
kv('clock', `${String(p0.hour).padStart(2, '0')}:${String(p0.minute).padStart(2, '0')}`);
kv('money', s0.money);
kv('energy', s0.energy);
kv('hotbar', s0.slots.map((sl, i) => (sl ? `${i}:${sl.id}x${sl.qty}` : null)).filter(Boolean).join(' '));

// ------------------------------------------------------- find a bare grass tile
head('TILL');
// A hoe only bites GRASS. Tilling a path, a wall edge or a tilled tile is
// correctly refused, so the plot has to be picked by its terrain code, not just
// "walkable" - picking any walkable tile makes the whole playtest look broken
// when the sim is behaving properly.
const nb = await neighbourhood(page, 8);
const bare = nb.cells
  .filter((c) => c.walkable && c.code === 'g' && !s0.placed[`${c.x},${c.y}`])
  .map((c) => ({
    x: c.x,
    y: c.y,
    open: (['up', 'down', 'left', 'right'] as DirName[]).filter((d) => {
      const [dx, dy] = DIRS[d];
      return nb.cells.some((n) => n.x === c.x + dx && n.y === c.y + dy && n.walkable);
    }),
  }))
  .filter((c) => c.open.length >= 1)
  .sort(
    (a, b) =>
      Math.hypot(a.x - nb.origin.x, a.y - nb.origin.y) - Math.hypot(b.x - nb.origin.x, b.y - nb.origin.y),
  );

const plot = bare[0];
if (!plot) {
  verdict('till', false, 'no bare walkable tile with a walkable neighbour found near spawn');
  console.log(JSON.stringify(verdicts, null, 2));
  await o.close();
  process.exit(1);
}
// Stand on the neighbour and face the plot. The stance is `plot - dir`, not
// `plot + dir`: standing one step PAST the plot and facing the same way points
// the tool two tiles away, at nothing, and the till is correctly refused.
const stand = plot.open[0]!;
const [sdx, sdy] = DIRS[stand];
await faceTile(page, plot.x - sdx, plot.y - sdy, stand);
kv(
  'teleport-setup',
  `stand (${plot.x - sdx},${plot.y - sdy}) facing ${stand} at plot (${plot.x},${plot.y})`,
);

// Slot 1 is the hoe on a fresh save.
await key('1');
const heldHoe = (await snap()).slots[(await playerState(page)).selected];
kv('held', heldHoe?.id);
await key('Space');
const afterTill = await snap();
const tilled = afterTill.placed[`${plot.x},${plot.y}`];
verdict(
  'till',
  tilled?.id === 'tilled',
  `Space on bare grass at (${plot.x},${plot.y}) -> placed.id=${tilled?.id ?? 'none'}`,
);
await shot(page, 'artifacts/dayloop-01-tilled.png');

// ------------------------------------------------------------------- plant
head('PLANT + WATER');
const seedSlot = afterTill.slots.findIndex((sl) => sl?.id.endsWith('-seed'));
if (seedSlot < 0) {
  verdict('plant', false, 'no seed in the hotbar on a fresh save');
} else {
  await key(String(seedSlot + 1));
  await key('Space');
  const afterPlant = await snap();
  const planted = afterPlant.placed[`${plot.x},${plot.y}`];
  verdict(
    'plant',
    typeof planted?.id === 'string' && planted.id.startsWith('crop:'),
    `seed slot ${seedSlot} (${afterTill.slots[seedSlot]?.id}) -> placed.id=${planted?.id ?? 'none'}`,
  );

  // Slot 2 is the watering can.
  const canSlot = afterPlant.slots.findIndex((sl) => sl?.id.startsWith('watering-can'));
  if (canSlot >= 0) {
    await key(String(canSlot + 1));
    await key('Space');
    const afterWater = await snap();
    const w = afterWater.placed[`${plot.x},${plot.y}`];
    verdict(
      'water',
      w?.data?.['watered'] === true || w?.data?.['watered'] === 1,
      `watering can -> tilled data=${JSON.stringify(w?.data ?? {})}`,
    );
  } else {
    verdict('water', false, 'no watering can in the hotbar');
  }
}

// ------------------------------------------------- wait out the growth, for real
// A crop with `waterNeed: 1` dies if a morning is skipped, so this waters EVERY
// morning. Sleeping six nights and hoping is not how the game is played, and
// treating the resulting withered crop as a bug would be wrong: the sim is
// correctly punishing an unattended field.
head('GROW (water every morning, real days)');
let ripe = false;
let nights = 0;
let withered = false;
for (let night = 1; night <= 8; night += 1) {
  const before = await playerState(page);
  await sleepNight();
  nights = night;
  const after = await playerState(page);
  if (after.dayCount !== before.dayCount + 1) {
    verdict('sleep-advances-day', false, `night ${night}: day went ${before.dayCount} -> ${after.dayCount}`);
    break;
  }
  const cropNow = (await snap()).placed[`${plot.x},${plot.y}`];
  if (!cropNow) {
    withered = true;
    kv(`night ${night}`, `day ${after.dayCount}, crop is GONE (withered after skipped waterings)`);
    break;
  }
  // Water it again before doing anything else, exactly as a player must.
  const can = (await snap()).slots.findIndex((sl) => sl?.id.startsWith('watering-can'));
  if (can >= 0) {
    await key(String(can + 1));
    await key('Space');
  }
  const crop = (await snap()).placed[`${plot.x},${plot.y}`];
  kv(
    `night ${night}`,
    `day ${before.dayCount} -> ${after.dayCount}, clock ${String(after.hour).padStart(2, '0')}:${String(after.minute).padStart(2, '0')}, energy ${after.energy}, stage=${String(crop?.data?.['stage'] ?? '-')}, watered=${String(crop?.data?.['watered'])}`,
  );
  // Try a harvest with an empty hand every morning.
  const emptySlot = (await snap()).slots.findIndex((sl) => sl === null);
  const handSlot = emptySlot >= 0 ? emptySlot : 8;
  await key(String(handSlot + 1));
  const invBefore = (await snap()).slots.filter((sl) => sl !== null).length;
  await key('Space');
  const invAfter = (await snap()).slots.filter((sl) => sl !== null).length;
  if (invAfter > invBefore) {
    ripe = true;
    verdict('sleep-advances-day', true, `day ${before.dayCount} -> ${after.dayCount}, day advanced on every one of ${nights} night(s)`);
    break;
  }
}
verdict(
  'grow-to-ripe',
  ripe,
  ripe
    ? `harvested a ripe crop by hand after ${nights} night(s)`
    : withered
      ? `the crop withered - the sim killed an unwatered field, which is correct`
      : `no crop ripened within ${nights} night(s)`,
);
await shot(page, 'artifacts/dayloop-02-harvest.png');

// -------------------------------------------------------------------- ship
head('SHIP');
// Pick a real harvest, not a tool and not a seed: tools end in '-t0' and seeds
// in '-seed'. Shipping a seed here would "pass" while proving nothing about
// selling a crop.
const isTool = (id: string): boolean => /-t\d+$/.test(id);
const grown = (await snap()).slots.findIndex(
  (sl) => sl !== null && !isTool(sl.id) && !sl.id.endsWith('-seed'),
);
const shipSlot = grown >= 0 ? grown : -1;
const preShip = await snap();
if (shipSlot < 0) {
  verdict('ship-into-bin', false, 'no harvested crop in the hotbar to ship');
} else {
  await key(String(shipSlot + 1));
  await key('x');
  const postShip = await snap();
  const binned = postShip.slots[shipSlot];
  verdict(
    'ship-into-bin',
    binned === null || binned === undefined || binned.qty < (preShip.slots[shipSlot]?.qty ?? 0),
    `X on slot ${shipSlot} (${preShip.slots[shipSlot]?.id}) -> slot now ${binned ? `${binned.id}x${binned.qty}` : 'empty'}; money is paid at day close, not on insert`,
  );
}

// Money arrives when the day closes, so sleep once more and check.
const preMoney = (await snap()).money;
await sleepNight();
const postMoney = (await snap()).money;
verdict(
  'ship-pays-out',
  postMoney > preMoney,
  `money ${preMoney} -> ${postMoney} after the day closed`,
);

// --------------------------------------------------------------------- cook
head('COOK + EAT');
await key('c');
await page.waitForTimeout(400);
// The dialog carries classes, not an id, so a [id*=craft] selector finds nothing.
const craftOpen = await page.evaluate(() => document.querySelectorAll('.eh-crafting-dialog.is-open').length);
const recipeRows = await page.evaluate(() => document.querySelectorAll('.eh-crafting-row').length);
verdict('crafting-panel-opens', craftOpen > 0, `C opened ${craftOpen} crafting dialog(s) listing ${recipeRows} recipe row(s)`);
await shot(page, 'artifacts/dayloop-03-crafting.png');
await key('Escape');
await page.waitForTimeout(300);

// Eat: pick real food if the player has any, else prove the refusal is visible.
const foodSlot = (await snap()).slots.findIndex(
  (sl) => sl !== null && !isTool(sl.id) && !sl.id.endsWith('-seed'),
);
const preEat = await snap();
if (foodSlot >= 0) {
  await key(String(foodSlot + 1));
  await key('g');
  const postEat = await snap();
  const gone = postEat.slots[foodSlot] === null || postEat.slots[foodSlot]!.qty < preEat.slots[foodSlot]!.qty;
  const said = await toasts();
  verdict(
    'eat',
    gone,
    `G on slot ${foodSlot} (${preEat.slots[foodSlot]?.id}) -> ${postEat.slots[foodSlot] ? `${postEat.slots[foodSlot]!.id}x${postEat.slots[foodSlot]!.qty}` : 'empty'}; energy ${preEat.energy} -> ${postEat.energy}; toast ${JSON.stringify(said[said.length - 1] ?? '')}`,
  );
} else {
  await key('1');
  await key('g');
  const said = await toasts();
  const refusal = said.find((t) => /not food/i.test(t));
  verdict(
    'eat-refusal-is-visible',
    refusal !== undefined,
    refusal ? `G on a hoe showed: "${refusal}"` : `G on a hoe produced no explanation; toasts=${JSON.stringify(said)}`,
  );
}

// -------------------------------------------------------------- contextual use
head('CONTEXTUAL USE (Q)');
await key('1');
await key('q');
// Read the toast stack only. Scanning the whole HUD for the word "use" matches
// the static control-hint bar ("Space = use tool") and reports a pass for a
// refusal that never happened.
const useToast = (await toasts()).find((t) => /cannot|not a|nothing|no machine|empty|collect/i.test(t));
verdict(
  'use-gives-feedback',
  useToast !== undefined,
  useToast ? `Q explained itself: "${useToast}"` : 'Q gave no on-screen explanation',
);

// ------------------------------------------------------------------- wrap up
head('RESULT');
const finalState = await playerState(page);
kv('final day', finalState.dayCount);
kv('final money', (await snap()).money);
// The harness aborts the Google Fonts stylesheet on purpose (offline, the
// `load` event never fires in time), which Chromium reports as one
// "Failed to load resource: net::ERR_FAILED". Counting that as a game error
// would mean every run ends in permanent, meaningless red, so it is separated
// out and reported on its own rather than quietly dropped.
const realErrors = o.errors.filter(
  (e) => !(e.type === 'error' && /ERR_FAILED|Failed to load resource/i.test(e.text)),
);
kv('console errors (game)', realErrors.length);
kv('console errors (harness font abort)', o.errors.length - realErrors.length);
for (const e of realErrors.slice(0, 6)) kv('  err', e.text);
verdict('no-console-errors', realErrors.length === 0, `${realErrors.length} real game console error(s)`);
const failed = verdicts.filter((v) => !v.pass);
console.log(`\n${verdicts.length - failed.length}/${verdicts.length} verdicts passed`);
console.log(failed.length === 0 ? 'ALL GREEN' : `RED: ${failed.map((f) => f.name).join(', ')}`);
await o.close();
process.exit(failed.length === 0 ? 0 : 1);
