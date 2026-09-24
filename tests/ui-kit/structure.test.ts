/**
 * T-0109 WORKER-3: headless structure tests for the UI kit, HUD helpers and
 * input mapping module. All module imports must be safe in Node — no document/
 * canvas/three access at import or setup time; only mount() touches the DOM and
 * that is guarded for a missing document.
 */
import { describe, expect, it } from 'vitest';
import { createUiKit } from '@game/features/ui-kit';
import { MESSAGES } from '@game/features/ui-kit/i18n/en';
import {
  barPercent,
  formatBarAmount,
  formatClock,
  formatDate,
  formatHotbarSlotQty,
  formatMoney,
  itemTooltipLines,
  pad2,
  replaceTokens,
  shippingBoxCount,
} from '@game/features/hud/format';
import { HOTBAR_SLOTS } from '@game/features/hud';
import {
  DEFAULT_KEYMAP,
  HOTBAR_SLOT_KEYS,
  actionToSim,
  findBinding,
  normalizeKey,
} from '@game/features/input/keymap';
import { getFeatures } from '@game/core/registry';
import { SEASON_NAMES } from '@game/core/types';
import type { FeatureContext } from '@game/core/feature';
import { EventBus } from '@game/core/events';
import '@game/features/hud';
import '@game/features/input';
import '@game/features/summary';
import '@game/features/shop-ui';
import {
  buildSummaryModel,
  formatGold,
  groupCountsByIdentifier,
  groupSoldByItem,
  resolveDisplayName,
  skillLabel,
  weatherLabel,
} from '@game/features/summary/format';
import {
  remainingDisplayQty,
  resolveBuyPrice,
  sellableInventory,
  stockLabel,
  trackedRemaining,
} from '@game/features/shop-ui/format';

describe('structured exports', () => {
  it('exposes the i18n table and season names', () => {
    expect(MESSAGES.hud.date.format).toContain('{season}');
    expect(MESSAGES.hud.money.format).toBe('{amount}g');
    expect(Object.keys(MESSAGES.hud.weather.label).sort()).toEqual(['rain', 'snow', 'storm', 'sun', 'wind']);
    expect(SEASON_NAMES).toEqual(['Spring', 'Summer', 'Fall', 'Winter']);
  });

  it('registers hud:ui and input:ui via registerFeature', () => {
    const ids = getFeatures().map((f) => f.id);
    expect(ids).toContain('hud:ui');
    expect(ids).toContain('input:ui');
    for (const id of ['hud:ui', 'input:ui']) {
      const mod = getFeatures().find((f) => f.id === id);
      expect(mod?.lane).toBe('ui');
      expect(typeof mod?.ui).toBe('function');
    }
  });

  it('registers summary:ui and shop:ui via registerFeature', () => {
    const ids = getFeatures().map((f) => f.id);
    expect(ids).toContain('summary:ui');
    expect(ids).toContain('shop:ui');
    for (const id of ['summary:ui', 'shop:ui']) {
      const mod = getFeatures().find((f) => f.id === id);
      expect(mod?.lane).toBe('ui');
      expect(typeof mod?.ui).toBe('function');
    }
  });
});

describe('ui-kit headless safety', () => {
  it('constructs without touching document', () => {
    expect(typeof document).toBe('undefined');
    const kit = createUiKit();
    expect(kit.container).toBeNull();
    expect(() => {
      expect(kit.panel().el).toBeNull();
      expect(kit.button({ label: 'Go' }).el).toBeNull();
      expect(kit.icon({ name: 'sun' }).el).toBeNull();
      expect(kit.tooltip().el).toBeNull();
      expect(kit.tab({ tabs: [{ id: 'a', label: 'A' }] }).el).toBeNull();
      expect(kit.slider({ label: 'S', min: 0, max: 10 }).el).toBeNull();
      expect(kit.dialog().el).toBeNull();
    }).not.toThrow();
  });

  it('factory handles are working-but-unmounted', () => {
    const kit = createUiKit();
    const panel = kit.panel({ className: 'x' });
    panel.addClass('y').setText('hi').attr('data-k', 'v').show().hide();

    const btn = kit.button({ label: 'Go' });
    btn.setText('G').append(kit.panel()).toggleClass('z', true).style('color', 'red');

    const tip = kit.tooltip();
    tip.setText('tip').show();
    tip.position(4, 5).hide();

    const tab = kit.tab({ tabs: [{ id: 'a', label: 'A' }] });
    tab.select('a');
    tab.body('a').setText('');

    const slider = kit.slider({ label: 'S', min: 0, max: 10, value: 5 });
    slider.setValue(7);

    const dlg = kit.dialog();
    dlg.open();
    dlg.setContent('hello');
    dlg.close();

    expect(panel.el).toBeNull();
    expect(btn.el).toBeNull();
    expect(kit.clear).toBeTypeOf('function');
    kit.clear();
  });

  it('mounts summary and shop ui without a document without throwing', () => {
    const stub = {
      store: { state: null, dispatch: () => undefined },
      bus: new EventBus(),
      rng: null,
      content: null,
      headless: true,
      getRenderer: () => undefined,
      getConfig: () => ({}),
      persist: async () => undefined,
    } as unknown as FeatureContext;
    for (const id of ['summary:ui', 'shop:ui']) {
      const mod = getFeatures().find((f) => f.id === id);
      expect(mod, id).toBeDefined();
      expect(() => mod!.setup?.(stub)).not.toThrow();
      expect(mod!.ui).toBeTypeOf('function');
      const handle = mod!.ui!();
      expect(() => handle.mount({} as HTMLElement)).not.toThrow();
      expect(() => handle.dispose()).not.toThrow();
    }
  });
});

describe('summary format helpers', () => {
  it('groups sold rows by item summing qty and gold', () => {
    expect(
      groupSoldByItem([
        { itemId: 'parsnip', qty: 2, gold: 70 },
        { itemId: 'parsnip', qty: 1, gold: 35 },
        { itemId: 'strawberry', qty: 3, gold: 360 },
      ]),
    ).toEqual([
      { itemId: 'parsnip', qty: 3, gold: 105 },
      { itemId: 'strawberry', qty: 3, gold: 360 },
    ]);
    expect(groupSoldByItem([])).toEqual([]);
  });

  it('groups count rows by identifier', () => {
    expect(
      groupCountsByIdentifier([
        { itemId: 'daffodil', qty: 1 },
        { itemId: 'daffodil', qty: 2 },
      ]),
    ).toEqual([{ itemId: 'daffodil', qty: 3 }]);
  });

  it('reuses the hud gold formatter', () => {
    expect(formatGold(175)).toBe('175g');
    expect(formatGold(-4)).toBe('0g');
  });

  it('resolves display names with an i18n fallback', () => {
    const items = new Map([['parsnip', { name: 'Parsnip' }]]);
    const crops = new Map([['parsnip', { name: 'Parsnip' }]]);
    expect(resolveDisplayName('parsnip', items, crops)).toBe('Parsnip');
    expect(resolveDisplayName('parsnip', undefined, crops)).toBe('Parsnip');
    expect(resolveDisplayName('ghost-stone', items, crops)).toMatch(/ghost-stone/);
    expect(resolveDisplayName('ghost-stone', new Map(), new Map())).toContain('Unknown item');
  });

  it('maps weather and skill names with fallbacks', () => {
    expect(weatherLabel('rain')).toBe('Rain');
    expect(weatherLabel('storm')).toBe('Storm');
    expect(weatherLabel('haze')).toBe('haze');
    expect(skillLabel('farming')).toBe('Farming');
    expect(skillLabel('combat')).toBe('Combat');
    expect(skillLabel('martial-arts')).toBe('martial-arts');
  });

  it('builds a full summary display model', () => {
    const payload = {
      dayCount: 3,
      date: { year: 1, seasonIndex: 0 as const, dayOfMonth: 3 },
      weather: 'rain',
      forecast: ['sun'],
      goldEarned: 175,
      itemsSold: [{ itemId: 'parsnip', qty: 5, gold: 175 }],
      cropsHarvested: [{ cropId: 'parsnip', qty: 5 }],
      collectedForage: [],
      xpEarned: [{ skill: 'farming', amount: 12 }],
    };
    const items = new Map([['parsnip', { name: 'Parsnip' }]]);
    const crops = new Map([['parsnip', { name: 'Parsnip' }]]);
    const model = buildSummaryModel(payload, items, crops);
    expect(model.date).toBe('Spring 3, Year 1');
    expect(model.weather).toBe('Rain');
    expect(model.goldEarned).toBe('175g');
    expect(model.shipping).toEqual([{ label: 'Parsnip', qty: 5, gold: '175g' }]);
    expect(model.harvest).toEqual([{ label: 'Parsnip', qty: 5 }]);
    expect(model.forage).toEqual([]);
    expect(model.experience).toEqual([{ label: 'Farming', qty: 12 }]);
    expect(model.isEmpty).toBe(false);
  });

  it('marks an empty day as empty in the model', () => {
    const payload = {
      dayCount: 1,
      date: { year: 1, seasonIndex: 0 as const, dayOfMonth: 1 },
      weather: 'sun',
      forecast: [],
      goldEarned: 0,
      itemsSold: [],
      cropsHarvested: [],
      collectedForage: [],
      xpEarned: [],
    };
    const model = buildSummaryModel(payload, new Map(), new Map());
    expect(model.isEmpty).toBe(true);
    expect(model.shipping).toEqual([]);
    expect(model.goldEarned).toBe('0g');
  });
});

describe('shop format helpers', () => {
  it('resolves buy prices with entry override winning', () => {
    const item = { name: 'Parsnip Seeds', price: { base: 2, buy: 20 } };
    expect(resolveBuyPrice({ itemId: 'parsnip-seed' }, item)).toBe(20);
    expect(resolveBuyPrice({ itemId: 'parsnip-seed', price: 15 }, item)).toBe(15);
    expect(resolveBuyPrice({ itemId: 'x' }, undefined)).toBe(0);
  });

  it('reads tracked shop stock defensively', () => {
    const ext = { stock: { 'seed-shop': { 'parsnip-seed': 3 } } };
    expect(trackedRemaining('seed-shop', 'parsnip-seed', ext)).toBe(3);
    expect(trackedRemaining('seed-shop', 'parsnip-seed', undefined)).toBeNull();
    expect(trackedRemaining('other-shop', 'parsnip-seed', ext)).toBeNull();
    expect(trackedRemaining('seed-shop', 'strawberry-seed', ext)).toBeNull();
    expect(trackedRemaining('seed-shop', 'parsnip-seed', 'nope')).toBeNull();
  });

  it('falls back to content qty, and null means infinite', () => {
    expect(remainingDisplayQty('seed-shop', 'parsnip-seed', 40, undefined)).toBe(40);
    expect(remainingDisplayQty('seed-shop', 'hoe-t0', undefined, undefined)).toBeNull();
    expect(
      remainingDisplayQty('seed-shop', 'parsnip-seed', 40, { stock: { 'seed-shop': { 'parsnip-seed': 2 } } }),
    ).toBe(2);
  });

  it('labels remaining stock from i18n', () => {
    expect(stockLabel(null)).toBe('Unlimited');
    expect(stockLabel(7)).toBe('Left: 7');
  });

  it('lists sellable inventory grouped by item, base price > 0 only', () => {
    const items = new Map([
      ['parsnip', { name: 'Parsnip', price: { base: 35 } }],
      ['hoe-t0', { name: 'Basic Hoe', price: { base: 15 } }],
      ['old-ring', { name: 'Old Ring', price: { base: 0 } }],
    ]);
    const slots = [
      { id: 'parsnip', qty: 2, quality: 0 as const },
      { id: 'parsnip', qty: 1, quality: 1 as const },
      { id: 'hoe-t0', qty: 1, quality: 0 as const },
      { id: 'old-ring', qty: 1, quality: 0 as const },
      null,
    ];
    expect(sellableInventory(slots, items)).toEqual([
      { itemId: 'hoe-t0', name: 'Basic Hoe', qty: 1, price: 15 },
      { itemId: 'parsnip', name: 'Parsnip', qty: 3, price: 35 },
    ]);
  });
});

describe('HUD format helpers', () => {
  it('zero-pads numbers', () => {
    expect(pad2(6)).toBe('06');
    expect(pad2(10)).toBe('10');
  });

  it('formats the clock 24h padded by default', () => {
    expect(formatClock({ hour: 6, minute: 0 })).toBe('06:00');
    expect(formatClock({ hour: 23, minute: 50 })).toBe('23:50');
    expect(formatClock({ hour: 0, minute: 10 })).toBe('00:10');
  });

  it('formats a 12h clock from the i18n config', () => {
    const fmt = { hour12: true, padHour: false, am: 'AM', pm: 'PM' };
    expect(formatClock({ hour: 6, minute: 0 }, fmt)).toBe('6:00 AM');
    expect(formatClock({ hour: 13, minute: 5 }, fmt)).toBe('1:05 PM');
    expect(formatClock({ hour: 0, minute: 0 }, fmt)).toBe('12:00 AM');
    expect(formatClock({ hour: 12, minute: 0 }, fmt)).toBe('12:00 PM');
  });

  it('formats money with the gold suffix', () => {
    expect(formatMoney(500)).toBe('500g');
    expect(formatMoney(0)).toBe('0g');
  });

  it('formats the calendar date', () => {
    expect(formatDate({ year: 1, seasonIndex: 0, dayOfMonth: 1 })).toBe('Spring 1, Year 1');
    expect(formatDate({ year: 2, seasonIndex: 3, dayOfMonth: 28 })).toBe('Winter 28, Year 2');
  });

  it('formats hotbar quantities', () => {
    expect(formatHotbarSlotQty(15)).toBe('15');
    expect(formatHotbarSlotQty(1)).toBe('1');
  });

  it('computes bar percentages', () => {
    expect(barPercent(135, 270)).toBe(50);
    expect(barPercent(270, 270)).toBe(100);
    expect(barPercent(0, 270)).toBe(0);
    expect(barPercent(10, 270)).toBe(4);
    expect(barPercent(10, 0)).toBe(0);
  });

  it('formats bar amounts', () => {
    expect(formatBarAmount(270, 270)).toBe('270/270');
    expect(formatBarAmount(269.98, 270)).toBe('270/270');
  });

  it('replaces named tokens', () => {
    expect(replaceTokens('{a}-{b}', { a: '1', b: '2' })).toBe('1-2');
    expect(replaceTokens('plain', {})).toBe('plain');
    expect(replaceTokens('{a}', { b: 'x' })).toBe('{a}');
  });

  it('sums shipping-box quantities defensively', () => {
    expect(shippingBoxCount(undefined)).toBe(0);
    expect(shippingBoxCount([])).toBe(0);
    expect(shippingBoxCount([{ id: 'parsnip', qty: 3, quality: 0 }, { qty: 2 }])).toBe(5);
    expect(shippingBoxCount([{ qty: 'x' }, null])).toBe(0);
  });

  it('builds item tooltip lines', () => {
    expect(
      itemTooltipLines({ id: 'parsnip', qty: 2, quality: 0 }, {
        name: 'Parsnip',
        description: 'A crisp spring root vegetable.',
      }),
    ).toEqual(['Parsnip', 'A crisp spring root vegetable.', 'Count: 2']);
    expect(itemTooltipLines({ id: 'nope', qty: 1, quality: 0 }, null)[0]).toContain('nope');
  });
});

describe('input keymap', () => {
  it('normalizes keys', () => {
    expect(normalizeKey(' ')).toBe('space');
    expect(normalizeKey('ArrowUp')).toBe('arrowup');
    expect(normalizeKey('W')).toBe('w');
    expect(normalizeKey('e')).toBe('e');
  });

  it('maps default move/interact/select bindings', () => {
    expect(findBinding('w')?.action).toEqual({ type: 'move', dx: 0, dy: -1 });
    expect(findBinding('arrowdown')?.action).toEqual({ type: 'move', dx: 0, dy: 1 });
    expect(findBinding('a')?.action).toEqual({ type: 'move', dx: -1, dy: 0 });
    expect(findBinding('d')?.action).toEqual({ type: 'move', dx: 1, dy: 0 });
    expect(findBinding('space')?.action).toEqual({ type: 'interact' });
    expect(findBinding('e')?.action).toEqual({ type: 'interact' });
    expect(findBinding('1')?.action).toEqual({ type: 'select-slot', slot: 0 });
    expect(findBinding('9')?.action).toEqual({ type: 'select-slot', slot: 8 });
    expect(findBinding('0')).toBeUndefined();
  });

  it('marks only movement bindings as hold-repeat', () => {
    const moveBindings = DEFAULT_KEYMAP.filter((b) => b.holdRepeat);
    expect(moveBindings).toHaveLength(4);
    expect(moveBindings.every((b) => b.action.type === 'move')).toBe(true);
  });

  it('binds one hotbar slot per digit 1-9', () => {
    expect(HOTBAR_SLOT_KEYS).toHaveLength(9);
    for (let i = 0; i < HOTBAR_SLOT_KEYS.length; i++) {
      expect(findBinding(HOTBAR_SLOT_KEYS[i]!)?.action).toEqual({ type: 'select-slot', slot: i });
    }
  });

  it('translates input actions to sim actions', () => {
    expect(actionToSim({ type: 'move', dx: -1, dy: 0 })).toEqual({ type: 'player:move', payload: { dx: -1, dy: 0 } });
    expect(actionToSim({ type: 'interact' })).toEqual({ type: 'player:interact', payload: {} });
    expect(actionToSim({ type: 'select-slot', slot: 3 })).toEqual({ type: 'player:select-slot', payload: { slot: 3 } });
  });

  it('binds the shop action to f and resolves no sim action for it', () => {
    expect(findBinding('f')?.action).toEqual({ type: 'shop' });
    expect(normalizeKey('F')).toBe('f');
    expect(actionToSim({ type: 'shop' })).toBeNull();
  });
});

describe('HUD constants', () => {
  it('exposes a 12-slot hotbar', () => {
    expect(HOTBAR_SLOTS).toBe(12);
  });
});