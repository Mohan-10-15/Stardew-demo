/**
 * T-0503 verification: boot the real game in a real Chromium and MEASURE the
 * Minecraft-look UI work — the 16x16 pixel item icons, the hard-bevel surfaces,
 * the clear centre viewport, the settings/journal panels, and the single
 * gesture-gated AudioContext with music staged under the cues.
 *
 * Prints observed numbers only — no assertions. Nothing here is imported by the
 * app; it is a dev-only harness, so the structural `any` types are deliberate.
 */
/* eslint-disable @typescript-eslint/no-explicit-any */
import { chromium, type Page } from 'playwright';

const URL = process.env['EH_URL'] ?? 'http://localhost:2026/';
const out: string[] = [];
const say = (s = ''): void => {
  out.push(s);
  console.log(s);
};

// --- PNG header reader: proves the icon canvases really are 16x16 in-browser ---
function pngSize(cssBackground: string): { w: number; h: number } | null {
  const inner = /^url\(["']?(.*?)["']?\)$/.exec(cssBackground.trim())?.[1] ?? cssBackground;
  const m = /^data:image\/png;base64,([A-Za-z0-9+/=]+)$/.exec(inner.trim());
  if (!m) return null;
  const buf = Buffer.from(m[1]!, 'base64');
  if (buf.length < 24) return null;
  return { w: buf.readUInt32BE(16), h: buf.readUInt32BE(20) };
}

interface AudioProbe {
  contexts: number;
  gains: Array<{ value: number; via: string }>;
  listeners: string[];
  ctor?: string;
}

async function readAudioProbe(page: Page): Promise<AudioProbe> {
  return page.evaluate(() => (window as any).__EH_AUDIO__ as AudioProbe);
}

/**
 * The interesting gains are the buses and the per-engine volume. Per-note
 * envelopes also call setValueAtTime(0, ...), so those are dropped or the
 * transcript is unreadable.
 */
function busGains(probe: AudioProbe): Array<{ value: number; via: string }> {
  return probe.gains.filter((g, i) => i < 3 || g.value > 0.001);
}

async function readHotbar(page: Page) {
  return page.evaluate(() => {
    const slots = [...document.querySelectorAll<HTMLElement>('.eh-slot')];
    return slots.map((slot) => {
      const icon = slot.querySelector<HTMLElement>('.eh-slot-icon');
      const name = slot.querySelector<HTMLElement>('.eh-slot-name');
      const count = slot.querySelector<HTMLElement>('.eh-slot-count');
      const iconStyle = icon ? getComputedStyle(icon) : null;
      const box = icon?.getBoundingClientRect();
      const slotBox = slot.getBoundingClientRect();
      return {
        item: icon?.dataset['item'] ?? null,
        background: icon ? (icon.style.backgroundImage || '').slice(0, 24) : '',
        hasImage: Boolean(icon?.style.backgroundImage),
        imageRendering: iconStyle?.imageRendering ?? '',
        iconBox: box ? { w: Math.round(box.width), h: Math.round(box.height) } : null,
        centred:
          box && slotBox
            ? Math.abs(box.left + box.width / 2 - (slotBox.left + slotBox.width / 2)) <= 1 &&
              Math.abs(box.top + box.height / 2 - (slotBox.top + slotBox.height / 2)) <= 12
            : null,
        name: name?.textContent ?? '',
        count: count?.textContent ?? '',
        countPos: count
          ? (() => {
              const c = count.getBoundingClientRect();
              return {
                right: Math.round(slotBox.right - c.right),
                bottom: Math.round(slotBox.bottom - c.bottom),
              };
            })()
          : null,
      };
    });
  });
}

/** Everything that could soften the Minecraft look, measured off the cascade. */
async function readSurfaceStyle(page: Page, selector: string) {
  return page.evaluate((sel) => {
    const el = document.querySelector(sel);
    if (!el) return null;
    const cs = getComputedStyle(el);
    return {
      borderWidth: cs.borderTopWidth,
      borderStyle: cs.borderTopStyle,
      borderRadius: cs.borderRadius,
      boxShadow: cs.boxShadow,
      backgroundImage: cs.backgroundImage,
      filter: cs.filter,
      backdropFilter: cs.backdropFilter,
      fontFamily: cs.fontFamily,
      textShadow: cs.textShadow,
      backgroundColor: cs.backgroundColor,
    };
  }, selector);
}

/** Any HUD cluster is fine at the edges, but nothing may sit over the middle. */
async function readCentreClearance(page: Page) {
  return page.evaluate(() => {
    const vw = window.innerWidth;
    const vh = window.innerHeight;
    const box = { left: vw * 0.3, right: vw * 0.7, top: vh * 0.3, bottom: vh * 0.7 };
    const offenders: string[] = [];
    const clusters: string[] = [];
    for (const sel of [
      '.eh-hud-info',
      '.eh-hud-vitals',
      '.eh-hud-hotbar',
      '.eh-hud-status',
      '.eh-hud-hint',
      '.eh-hud-buffs',
    ]) {
      for (const el of document.querySelectorAll<HTMLElement>(sel)) {
        const cs = getComputedStyle(el);
        if (cs.display === 'none' || cs.visibility === 'hidden') continue;
        const r = el.getBoundingClientRect();
        if (r.width === 0 || r.height === 0) continue;
        clusters.push(
          `${sel} ${Math.round(r.left)},${Math.round(r.top)} ${Math.round(r.width)}x${Math.round(r.height)}`,
        );
        if (r.left < box.right && r.right > box.left && r.top < box.bottom && r.bottom > box.top) {
          offenders.push(sel);
        }
      }
    }
    return { vw, vh, clusters, offenders };
  });
}

/** Pointer lock freezes the cursor at the screen centre, which makes every
 *  later element click land on whatever sits there. Always release it first. */
async function releasePointerLock(page: Page): Promise<void> {
  await page.evaluate(() => {
    if (document.pointerLockElement) document.exitPointerLock();
  });
  await page.waitForTimeout(120);
}

async function openPanel(page: Page, key: string) {
  await releasePointerLock(page);
  await page.keyboard.press(key);
  await page.waitForTimeout(350);
}

async function readDialog(page: Page) {
  return page.evaluate(() => {
    const backdrops = [...document.querySelectorAll<HTMLElement>('.eh-dialog-backdrop')];
    return backdrops.map((b) => {
      const dialog = b.querySelector<HTMLElement>('.eh-dialog');
      const title = b.querySelector<HTMLElement>('.eh-dialog-title')?.textContent ?? '';
      const r = b.getBoundingClientRect();
      const d = dialog?.getBoundingClientRect();
      return {
        classes: b.className,
        open: b.classList.contains('is-open'),
        title,
        text: (dialog?.textContent ?? '').replace(/\s+/g, ' ').trim().slice(0, 220),
        w: d ? Math.round(d.width) : 0,
        h: d ? Math.round(d.height) : 0,
        viewport: { w: Math.round(r.width), h: Math.round(r.height) },
        fitsViewport: d ? d.width <= r.width && d.height <= r.height : false,
      };
    });
  });
}

const browser = await chromium.launch();
const context = await browser.newContext({ viewport: { width: 1280, height: 800 } });
// NOTE: this is a *string*, not a function. esbuild rewrites a function
// argument with its `__name` keepNames helper, and Playwright evaluates the
// stringified body in the page without that helper — which throws
// "__name is not defined" and leaves the counters unhooked.
await context.addInitScript(`
  (function () {
    var w = window;
    w.__EH_AUDIO__ = { contexts: 0, gains: [], listeners: [] };
    var Real = w.AudioContext || w.webkitAudioContext;
    if (!Real) return;
    w.__EH_AUDIO__.ctor = typeof Real;
    function Counted() {
      var ctx = Reflect.construct(Real, Array.prototype.slice.call(arguments), Counted);
      w.__EH_AUDIO__.contexts += 1;
      var createGain = ctx.createGain.bind(ctx);
      ctx.createGain = function () {
        var node = createGain();
        var raw = node.gain;
        var proxy = new Proxy(raw, {
          get: function (t, p) {
            var v = t[p];
            if (p === 'setValueAtTime' && typeof v === 'function') {
              return function (value, when) {
                w.__EH_AUDIO__.gains.push({ value: value, via: 'setValueAtTime' });
                return v.call(t, value, when);
              };
            }
            return typeof v === 'function' ? v.bind(t) : v;
          },
          set: function (t, p, v) {
            t[p] = v;
            if (p === 'value') w.__EH_AUDIO__.gains.push({ value: v, via: 'value' });
            return true;
          },
        });
        // 'gain' is a prototype getter, so plain assignment is a silent no-op.
        Object.defineProperty(node, 'gain', { value: proxy, configurable: true });
        return node;
      };
      return ctx;
    }
    Counted.prototype = Real.prototype;
    w.AudioContext = Counted;
    var add = w.addEventListener.bind(w);
    w.addEventListener = function (type, fn, opts) {
      if (type === 'keydown' || type === 'pointerdown') w.__EH_AUDIO__.listeners.push(type);
      return add(type, fn, opts);
    };
  })();
`);

const page = await context.newPage();
const errors: string[] = [];
page.on('console', (m) => {
  if (m.type() === 'error') errors.push(`[error] ${m.text()}`);
});
page.on('pageerror', (e) => errors.push(`[pageerror] ${e.message}`));

await page.goto(URL, { waitUntil: 'load' });
await page.waitForFunction(() => Boolean((window as any).__EH__), undefined, { timeout: 25000 });
await page.waitForTimeout(1500);

say('=== BOOT ===');
say(`console errors: ${errors.length}`);
for (const e of errors.slice(0, 8)) say(`  ${e}`);

const beforeGesture = await readAudioProbe(page);
say(`AudioContext constructor found: ${beforeGesture.ctor ?? 'none'}`);
say(`gesture listeners installed by the audio lane: ${beforeGesture.listeners.length}`);
say(`AudioContexts before any gesture: ${beforeGesture.contexts} (must be 0 — autoplay policy)`);

say('');
say('=== AUDIO: one context, created by a real gesture ===');
await releasePointerLock(page);
await page.keyboard.press('ArrowRight');
await page.waitForTimeout(400);
await page.keyboard.press('ArrowLeft');
await page.waitForTimeout(600);
const afterGesture = await readAudioProbe(page);
say(`AudioContexts after keydown + movement: ${afterGesture.contexts}`);
say(`gain values set, in creation order: ${JSON.stringify(afterGesture.gains)}`);
say('  expected shape: master 1, sfx 1, music bus 0.35, then the per-engine music volume');
await page.mouse.click(640, 300);
await page.waitForTimeout(500);
const afterClick = await readAudioProbe(page);
say(`AudioContexts after a pointer click: ${afterClick.contexts} (must stay 1)`);

say('');
say('=== HOTBAR: 16x16 procedural icons ===');
const slots = await readHotbar(page);
const filled = slots.filter((s) => s.hasImage);
say(`slots: ${slots.length}, painted: ${filled.length}, empty: ${slots.length - filled.length}`);
for (const s of filled) {
  const bg = await page.evaluate((item) => {
    const el = document.querySelector<HTMLElement>(`.eh-slot-icon[data-item="${item}"]`);
    return el?.style.backgroundImage ?? '';
  }, s.item);
  const size = pngSize(bg);
  say(
    `  ${s.item}: name="${s.name}" count="${s.count}" rendered ${s.iconBox?.w}x${s.iconBox?.h} ` +
      `png=${size ? `${size.w}x${size.h}` : '?'} image-rendering=${s.imageRendering} centred=${s.centred}` +
      (s.count ? ` count-offset(right/bottom)=${s.countPos?.right}/${s.countPos?.bottom}` : '') +
      ` b64len=${bg.length}`,
  );
}
const sizes = new Set<string>();
const renders = new Set<string>();
for (const s of filled) {
  const bg = await page.evaluate(
    (item) =>
      document.querySelector<HTMLElement>(`.eh-slot-icon[data-item="${item}"]`)?.style
        .backgroundImage ?? '',
    s.item,
  );
  const size = pngSize(bg);
  if (size) sizes.add(`${size.w}x${size.h}`);
  renders.add(s.imageRendering);
}
say(`distinct icon sizes: ${[...sizes].join(', ') || 'none'} (all must be 16x16)`);
say(
  `distinct image-rendering values: ${[...renders].join(', ')} (must be pixelated/crisp-edges, never smooth)`,
);
say(
  `distinct item ids in the hotbar: ${new Set(filled.map((s) => s.item)).size} across ${filled.length} painted slots`,
);
await page.locator('.eh-hud-hotbar').screenshot({ path: 'artifacts/t0503-hotbar.png' });

say('');
say('=== SURFACES: hard bevels, no soft edges ===');
for (const sel of ['.eh-slot', '.eh-hud-hotbar', '.eh-hud-info', '.eh-panel']) {
  const style = await readSurfaceStyle(page, sel);
  if (!style) {
    say(`  ${sel}: not present`);
    continue;
  }
  say(
    `  ${sel}: border ${style.borderWidth} ${style.borderStyle}, radius=${style.borderRadius}, ` +
      `filter=${style.filter}, backdrop=${style.backdropFilter}, bg-image=${style.backgroundImage}`,
  );
  say(`     box-shadow: ${style.boxShadow}`);
  say(`     font: ${style.fontFamily}`);
}

say('');
say('=== CENTRE VIEWPORT STAYS CLEAR ===');
const centre = await readCentreClearance(page);
say(`viewport ${centre.vw}x${centre.vh}, centre box = middle 40%`);
for (const c of centre.clusters) say(`  cluster: ${c}`);
say(
  `clusters overlapping the centre: ${centre.offenders.length === 0 ? 'none' : centre.offenders.join(', ')}`,
);
await page.screenshot({ path: 'artifacts/t0503-hud.png' });

say('');
say('=== SETTINGS: K dialog with the music row ===');
await openPanel(page, 'k');
let dialogs = await readDialog(page);
for (const d of dialogs.filter((x) => x.open))
  say(`  open dialog [${d.classes}] title="${d.title}" ${d.w}x${d.h} fits=${d.fitsViewport}`);
say(`  body: ${dialogs.find((d) => d.open)?.text ?? '(none open)'}`);
const settingsSurface = await readSurfaceStyle(page, '.eh-settings-dialog .eh-dialog');
if (settingsSurface) {
  say(
    `  dialog border=${settingsSurface.borderWidth}, radius=${settingsSurface.borderRadius}, shadow=${settingsSurface.boxShadow}`,
  );
}
const settingsUi = await page.evaluate(() => {
  const root = document.querySelector<HTMLElement>('.eh-settings-dialog .eh-dialog');
  if (!root) return null;
  const rows = [...root.querySelectorAll<HTMLElement>('.eh-settings-row')];
  const toggle = root.querySelector<HTMLElement>('.eh-settings-toggle');
  const slider = root.querySelector<HTMLInputElement>('input[type="range"]');
  const value = root.querySelector<HTMLElement>('.eh-settings-value');
  return {
    rowCount: rows.length,
    labels: rows.map((r) => r.querySelector('.eh-settings-label')?.textContent ?? ''),
    toggleText: toggle?.textContent ?? '',
    toggleChecked: toggle?.getAttribute('aria-checked') ?? null,
    toggleWidth: toggle ? Math.round(toggle.getBoundingClientRect().width) : 0,
    sliderValue: slider?.value ?? null,
    sliderMin: slider?.min ?? null,
    sliderMax: slider?.max ?? null,
    valueText: value?.textContent ?? '',
    stored: window.localStorage.getItem('eh.audio'),
  };
});
say(`  rows=${settingsUi?.rowCount} labels=${JSON.stringify(settingsUi?.labels)}`);
say(
  `  toggle="${settingsUi?.toggleText}" aria-checked=${settingsUi?.toggleChecked} width=${settingsUi?.toggleWidth}px`,
);
say(
  `  slider value=${settingsUi?.sliderValue} min=${settingsUi?.sliderMin} max=${settingsUi?.sliderMax} readout="${settingsUi?.valueText}"`,
);
say(`  localStorage eh.audio: ${settingsUi?.stored ?? '(none)'}`);
await page.locator('.eh-settings-dialog').screenshot({ path: 'artifacts/t0503-settings.png' });

say('');
say('=== SETTINGS: toggling music is authoritative ===');
const musicEvents: Array<{ enabled: boolean; volume: number }> = [];
await page.evaluate(() => {
  const eh = (window as any).__EH__;
  (window as any).__EH_MUSIC__ = [];
  eh.bus.on('music:changed', (p: any) =>
    (window as any).__EH_MUSIC__.push({ enabled: p?.enabled, volume: p?.volume }),
  );
});
await releasePointerLock(page);
await page.locator('.eh-settings-dialog .eh-settings-toggle').click();
await page.waitForTimeout(250);
const afterToggle = await page.evaluate(() => {
  const root = document.querySelector<HTMLElement>('.eh-settings-dialog .eh-dialog');
  const toggle = root?.querySelector<HTMLElement>('.eh-settings-toggle');
  return {
    text: toggle?.textContent ?? '',
    checked: toggle?.getAttribute('aria-checked') ?? null,
    stored: window.localStorage.getItem('eh.audio'),
    events: ((window as any).__EH_MUSIC__ ?? []) as Array<{ enabled: boolean; volume: number }>,
  };
});
const gainsAfterToggle = await readAudioProbe(page);
say(`  after click: "${afterToggle.text}" aria-checked=${afterToggle.checked}`);
say(`  localStorage: ${afterToggle.stored}`);
say(`  music:changed events: ${JSON.stringify(afterToggle.events)}`);
say(`  music bus gain still staged: ${JSON.stringify(busGains(gainsAfterToggle))}`);
musicEvents.push(...afterToggle.events);
await releasePointerLock(page);
await page.locator('.eh-settings-dialog .eh-settings-toggle').click();
await page.waitForTimeout(250);
const backOn = await page.evaluate(() => ({
  text: document.querySelector('.eh-settings-toggle')?.textContent ?? '',
  stored: window.localStorage.getItem('eh.audio'),
}));
say(`  after second click: "${backOn.text}" localStorage=${backOn.stored}`);

say('');
say('=== SETTINGS: the volume slider, and the music staging it must not undo ===');
await releasePointerLock(page);
await page.locator('.eh-settings-dialog input[type="range"]').fill('20');
await page.locator('.eh-settings-dialog input[type="range"]').dispatchEvent('input');
await page.waitForTimeout(400);
const afterSlider = await page.evaluate(() => {
  const root = document.querySelector<HTMLElement>('.eh-settings-dialog .eh-dialog');
  const slider = root?.querySelector<HTMLInputElement>('input[type="range"]');
  const value = root?.querySelector<HTMLElement>('.eh-settings-value');
  return {
    slider: slider?.value ?? null,
    readout: value?.textContent ?? '',
    stored: window.localStorage.getItem('eh.audio'),
    events: ((window as any).__EH_MUSIC__ ?? []) as Array<{ enabled: boolean; volume: number }>,
  };
});
const gainsAfterSlider = await readAudioProbe(page);
say(
  `  slider=${afterSlider.slider} readout="${afterSlider.readout}" localStorage=${afterSlider.stored}`,
);
say(`  every non-envelope gain value so far: ${JSON.stringify(busGains(gainsAfterSlider))}`);
say(
  `  music bus staging (3rd value) still 0.35: ${gainsAfterSlider.gains[2]?.value === 0.35}; ` +
    `the user volume lands on separate later nodes: ${JSON.stringify(busGains(gainsAfterSlider).slice(3))}`,
);

say('');
say('=== INPUT: hotkeys survive a focused slider ===');
const keysWhileSliderFocused = await page.evaluate(() => {
  const slider = document.querySelector<HTMLInputElement>(
    '.eh-settings-dialog input[type="range"]',
  );
  if (!slider) return null;
  slider.focus();
  return { focused: document.activeElement === slider };
});
await page.keyboard.press('k');
await page.waitForTimeout(300);
const afterKWithSliderFocus = await page.evaluate(() => ({
  settingsOpen:
    document.querySelector('.eh-settings-dialog')?.classList.contains('is-open') ?? false,
  focused: document.activeElement?.getAttribute('type') ?? document.activeElement?.tagName ?? '',
}));
say(
  `  slider focused=${keysWhileSliderFocused?.focused}; K pressed while it held focus -> ` +
    `settings open=${afterKWithSliderFocus.settingsOpen} (must be false: K still works), focus now on ${afterKWithSliderFocus.focused}`,
);

say('');
say('=== SETTINGS: K toggles in both directions ===');
await releasePointerLock(page);
await page.keyboard.press('k');
await page.waitForTimeout(300);
const reopened = await page.evaluate(() => ({
  open: document.querySelector('.eh-settings-dialog')?.classList.contains('is-open') ?? false,
  anyOpen: [...document.querySelectorAll('.eh-dialog-backdrop.is-open')].length,
}));
await releasePointerLock(page);
await page.keyboard.press('k');
await page.waitForTimeout(300);
const closed = await page.evaluate(() => ({
  open: document.querySelector('.eh-settings-dialog')?.classList.contains('is-open') ?? false,
  anyOpen: [...document.querySelectorAll('.eh-dialog-backdrop.is-open')].length,
}));
say(`  after K: open=${reopened.open}, open dialogs=${reopened.anyOpen} (expect true/1)`);
say(`  after K again: open=${closed.open}, open dialogs=${closed.anyOpen} (expect false/0)`);

say('');
say('=== JOURNAL: J dialog, tabs and rows ===');
await openPanel(page, 'j');
dialogs = await readDialog(page);
for (const d of dialogs.filter((x) => x.open))
  say(`  open dialog [${d.classes}] title="${d.title}" ${d.w}x${d.h} fits=${d.fitsViewport}`);
const journalTabs = await page.evaluate(() => {
  const root = document.querySelector<HTMLElement>('.eh-journal-dialog');
  if (!root) return null;
  const tabs = [...root.querySelectorAll<HTMLButtonElement>('.eh-tab')].map((t) => ({
    label: t.textContent ?? '',
    selected: t.getAttribute('aria-selected') === 'true',
  }));
  const bodies = [...root.querySelectorAll<HTMLElement>('.eh-tab-body')].map((b) => ({
    hidden: b.hidden,
    height: Math.round(b.getBoundingClientRect().height),
    rows: b.querySelectorAll('.eh-journal-row').length,
    hearts: b.querySelectorAll('.eh-journal-hearts').length,
  }));
  return { tabs, bodies, rows: root.querySelectorAll('.eh-journal-row').length };
});
say(`  tabs: ${JSON.stringify(journalTabs?.tabs)}`);
say(`  rows in the DOM across all tabs: ${journalTabs?.rows}`);
for (const b of journalTabs?.bodies ?? []) {
  say(`    body hidden=${b.hidden} height=${b.height} rows=${b.rows} hearts=${b.hearts}`);
}
await page.locator('.eh-journal-dialog').screenshot({ path: 'artifacts/t0503-journal-quests.png' });
for (let i = 1; i < (journalTabs?.tabs.length ?? 0); i++) {
  await releasePointerLock(page);
  await page.locator('.eh-journal-dialog .eh-tab').nth(i).click();
  await page.waitForTimeout(300);
  const tab = await page.evaluate((idx) => {
    const root = document.querySelector<HTMLElement>('.eh-journal-dialog');
    const bodies = [...(root?.querySelectorAll<HTMLElement>('.eh-tab-body') ?? [])];
    const body = bodies.find((b) => !b.hidden);
    return {
      label: root?.querySelectorAll<HTMLElement>('.eh-tab')[idx]?.textContent ?? '',
      selected:
        root?.querySelectorAll<HTMLElement>('.eh-tab')[idx]?.getAttribute('aria-selected') ?? null,
      shownBodies: bodies.filter((b) => !b.hidden).length,
      rows: body ? body.querySelectorAll('.eh-journal-row').length : 0,
      hearts: body ? body.querySelectorAll('.eh-journal-hearts').length : 0,
      text: (body?.textContent ?? '').replace(/\s+/g, ' ').trim().slice(0, 130),
    };
  }, i);
  say(
    `  tab "${tab.label}" selected=${tab.selected} shown bodies=${tab.shownBodies} (must be 1) rows=${tab.rows} hearts=${tab.hearts}`,
  );
  say(`    ${tab.text}`);
  await page.locator('.eh-journal-dialog').screenshot({ path: `artifacts/t0503-journal-${i}.png` });
}
await releasePointerLock(page);
await page.keyboard.press('j');
await page.waitForTimeout(250);
const journalClosed = await page.evaluate(
  () => document.querySelectorAll('.eh-dialog-backdrop.is-open').length,
);
say(`  open dialogs after J: ${journalClosed} (expect 0)`);

say('');
say('=== MODAL: opening one panel closes the other ===');
await openPanel(page, 'k');
await openPanel(page, 'j');
const bothOpen = await page.evaluate(() => ({
  settings: document.querySelector('.eh-settings-dialog')?.classList.contains('is-open') ?? false,
  journal: document.querySelector('.eh-journal-dialog')?.classList.contains('is-open') ?? false,
  open: document.querySelectorAll('.eh-dialog-backdrop.is-open').length,
}));
say(
  `  settings=${bothOpen.settings} journal=${bothOpen.journal} open dialogs=${bothOpen.open} (expect false/true/1)`,
);

say('');
say('=== HOTKEY TOGGLES: k, j, c, f all open then close ===');
for (const [key, sel] of [
  ['k', '.eh-settings-dialog'],
  ['j', '.eh-journal-dialog'],
  ['c', '.eh-crafting-dialog'],
  ['f', '.eh-shop-dialog'],
] as const) {
  await openPanel(page, key);
  const first = await page.evaluate(
    (s) => document.querySelector(s)?.classList.contains('is-open') ?? false,
    sel,
  );
  await releasePointerLock(page);
  await page.keyboard.press(key);
  await page.waitForTimeout(300);
  const second = await page.evaluate((s) => {
    const el = document.querySelector(s);
    return {
      isOpen: el?.classList.contains('is-open') ?? false,
      stillInDom: Boolean(el),
      open: document.querySelectorAll('.eh-dialog-backdrop.is-open').length,
    };
  }, sel);
  say(
    `  ${key} -> ${sel}: first press open=${first} (expect true), second press open=${second.isOpen} ` +
      `(expect false), node left in the DOM=${second.stillInDom} (expect false), open dialogs=${second.open} (expect 0)`,
  );
}

say('');
say('=== MUSIC MIX: cues vs bed ===');
const mix = await page.evaluate(() => {
  const g = (window as any).__EH_AUDIO__.gains as Array<{ value: number; via: string }>;
  return {
    total: g.length,
    values: g
      .filter((x, i) => i < 3 || x.value > 0.001)
      .map((x) => ({ value: x.value, via: x.via })),
  };
});
say(`  every non-envelope gain value the page ever set: ${JSON.stringify(mix.values)}`);
say('  the 3rd value is the music bus staging (0.35) and must never be a user volume');

say('');
say('=== FINAL CONSOLE ERROR COUNT ===');
say(`${errors.length}`);
for (const e of errors.slice(0, 10)) say(`  ${e}`);

await browser.close();

const { writeFile, mkdir } = await import('node:fs/promises');
await mkdir('artifacts', { recursive: true });
await writeFile('artifacts/t0503-transcript.txt', out.join('\n'), 'utf8');
say('');
say('transcript written to artifacts/t0503-transcript.txt');
