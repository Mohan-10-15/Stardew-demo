/**
 * hud:ui — in-game HUD (WORKER-3 lane). Reads game state on every
 * `state:changed` and dispatches sim actions for hotbar clicks / drag-drop.
 * All display strings come from the i18n table; the DOM is only ever touched
 * from `mount()`, which guards for a missing `document` (headless tests).
 */
import { defineFeature, type FeatureContext, type UiHandle } from '../../core/feature';
import { createUiKit, type TooltipHandle, type UiKit } from '../ui-kit';
import { MESSAGES, type Messages } from '../ui-kit/i18n/en';
import { SEASON_NAMES, type GameState, type ItemStack } from '../../core/types';
import {
  activeBuffRows,
  barPercent,
  formatBarAmount,
  formatClock,
  formatDate,
  formatHotbarSlotQty,
  formatMoney,
  interactionHint,
  itemTooltipLines,
  replaceTokens,
  shippingBoxCount,
} from './format';
import { tileInFront } from '../engine/sim/PlayerPosition';

export const HOTBAR_SLOTS = 12;

function isSlotIndex(value: number): boolean {
  return Number.isInteger(value) && value >= 0 && value < HOTBAR_SLOTS;
}

function slotIndexFrom(el: HTMLElement): number {
  const raw = Number(el.dataset.slot);
  return isSlotIndex(raw) ? raw : -1;
}

export function createHudUi(ctx: FeatureContext): UiHandle {
  const messages: Messages = MESSAGES;
  const items = ctx.content.items;

  let doc: Document | null = null;
  let root: HTMLDivElement | null = null;
  let off: (() => void) | null = null;
  let lastState: GameState | null = null;
  let dragIndex: number | null = null;
  let dragEl: HTMLElement | null = null;

  let dateEl: HTMLElement | null = null;
  let clockEl: HTMLElement | null = null;
  let weatherEl: HTMLElement | null = null;
  let moneyEl: HTMLElement | null = null;
  let energyBarEl: HTMLElement | null = null;
  let energyFill: HTMLElement | null = null;
  let energyText: HTMLElement | null = null;
  let healthBarEl: HTMLElement | null = null;
  let healthFill: HTMLElement | null = null;
  let healthText: HTMLElement | null = null;
  let shippingEl: HTMLElement | null = null;
  let buffsEl: HTMLElement | null = null;
  let hintEl: HTMLElement | null = null;
  let tooltip: TooltipHandle | null = null;
  const slotEls: HTMLElement[] = [];

  function make<K extends keyof HTMLElementTagNameMap>(
    tag: K,
    className: string,
  ): HTMLElementTagNameMap[K] | null {
    if (!doc) return null;
    const node = doc.createElement(tag);
    node.className = className;
    return node;
  }

  function selectSlot(slot: number): void {
    if (!isSlotIndex(slot)) return;
    ctx.store.dispatch({ type: 'player:select-slot', payload: { slot } });
  }

  function moveStack(from: number, to: number): void {
    if (!isSlotIndex(from) || !isSlotIndex(to) || from === to) return;
    ctx.store.dispatch({ type: 'inventory:move', payload: { from, to } });
  }

  function showTooltip(anchor: HTMLElement, stack: ItemStack): void {
    if (!tooltip?.el) return;
    const item = items.get(stack.id);
    const lines = itemTooltipLines(stack, item, messages);
    tooltip.setText(lines.join('\n'));
    tooltip.show();
    const rect = anchor.getBoundingClientRect();
    const height = tooltip.el.offsetHeight || 0;
    let y = rect.top - height - 8;
    if (y < 8) y = rect.bottom + 8;
    tooltip.position(rect.left, y);
  }

  function hideTooltip(): void {
    tooltip?.hide();
  }

  function buildBar(kind: 'energy' | 'health'): HTMLElement | null {
    const bar = make('div', `eh-bar eh-bar-${kind}`);
    if (!bar) return null;
    const label = make('span', 'eh-bar-label');
    if (label) label.textContent = kind === 'energy' ? messages.hud.energy.label : messages.hud.health.label;
    const track = make('div', 'eh-bar-track');
    const fill = make('div', 'eh-bar-fill');
    const amount = make('span', 'eh-bar-amount');
    if (label) bar.appendChild(label);
    if (track) {
      if (fill) track.appendChild(fill);
      bar.appendChild(track);
    }
    if (amount) bar.appendChild(amount);
    if (kind === 'energy') {
      energyBarEl = bar;
      energyFill = fill;
      energyText = amount;
    } else {
      healthBarEl = bar;
      healthFill = fill;
      healthText = amount;
    }
    return bar;
  }

  function buildSlot(index: number, kit: UiKit): HTMLElement | null {
    const slot = kit.button({ label: '', ariaLabel: '', className: 'eh-slot', append: false });
    const el = slot.el;
    if (!el) return null;
    el.dataset.slot = String(index);
    const name = make('span', 'eh-slot-name');
    const count = make('span', 'eh-slot-count');
    if (name) el.appendChild(name);
    if (count) el.appendChild(count);
    el.addEventListener('pointerenter', () => {
      const stack = lastState?.player.inventory.slots[index];
      if (stack) showTooltip(el, stack);
    });
    el.addEventListener('pointerleave', hideTooltip);
    return el;
  }

  function buildDom(): void {
    if (!doc || !root) return;
    const kit = createUiKit(root);

    const info = kit.panel({ className: 'eh-hud-info' });
    dateEl = make('div', 'eh-hud-date');
    clockEl = make('div', 'eh-hud-clock');
    weatherEl = make('div', 'eh-hud-weather');
    moneyEl = make('div', 'eh-hud-money');
    if (dateEl) info.append(dateEl);
    if (clockEl) info.append(clockEl);
    if (weatherEl) info.append(weatherEl);
    if (moneyEl) info.append(moneyEl);

    const vitals = kit.panel({ className: 'eh-hud-vitals' });
    const energyBar = buildBar('energy');
    const healthBar = buildBar('health');
    shippingEl = make('div', 'eh-hud-shipping');
    if (energyBar) vitals.append(energyBar);
    if (healthBar) vitals.append(healthBar);
    if (shippingEl) vitals.append(shippingEl);

    const status = kit.panel({ className: 'eh-hud-status' });
    buffsEl = make('div', 'eh-hud-buffs');
    hintEl = make('div', 'eh-hud-hint');
    if (buffsEl) status.append(buffsEl);
    if (hintEl) status.append(hintEl);

    const hotbarPanel = kit.panel({ className: 'eh-hud-hotbar' });
    const hotbarLabel = make('span', 'eh-hud-hotbar-label');
    const hotbar = make('div', 'eh-hud-hotbar-slots');
    if (hotbarLabel) {
      hotbarLabel.textContent = messages.hud.hotbar.label;
      hotbarPanel.append(hotbarLabel);
    }
    if (hotbar) {
      hotbar.setAttribute('role', 'toolbar');
      hotbar.setAttribute('aria-label', messages.hud.hotbar.label);
      hotbarPanel.append(hotbar);
      for (let i = 0; i < HOTBAR_SLOTS; i++) {
        const slot = buildSlot(i, kit);
        if (slot) {
          hotbar.appendChild(slot);
          slotEls.push(slot);
        }
      }
      hotbar.addEventListener('pointerdown', (event) => {
        const target = event.target as Element | null;
        const slotEl = target?.closest<HTMLElement>('.eh-slot') ?? null;
        if (!slotEl) return;
        const index = slotIndexFrom(slotEl);
        if (index < 0) return;
        selectSlot(index);
        dragIndex = index;
        dragEl = slotEl;
        slotEl.classList.add('eh-slot-dragging');
      });
    }

    tooltip = kit.tooltip();
  }

  function renderHotbar(state: GameState): void {
    const inventory = state.player.inventory;
    for (let i = 0; i < HOTBAR_SLOTS; i++) {
      const slotEl = slotEls[i];
      if (!slotEl) continue;
      const stack = inventory.slots[i];
      const selected = inventory.selected === i;
      slotEl.classList.toggle('is-selected', selected);
      slotEl.setAttribute('aria-pressed', String(selected));

      const nameEl = slotEl.querySelector<HTMLElement>('.eh-slot-name');
      const countEl = slotEl.querySelector<HTMLElement>('.eh-slot-count');
      const parts: string[] = [replaceTokens(messages.hud.hotbar.slotAria, { number: String(i + 1) })];

      if (stack) {
        const item = items.get(stack.id);
        const displayName =
          item?.name ?? `${replaceTokens(messages.hud.tooltip.unknownItem, {})} (${stack.id})`;
        if (nameEl) nameEl.textContent = displayName;
        if (countEl) {
          countEl.textContent = stack.qty > 1 ? formatHotbarSlotQty(stack.qty, messages) : '';
          countEl.style.display = stack.qty > 1 ? '' : 'none';
        }
        parts.push(replaceTokens(messages.hud.hotbar.itemAria, { name: displayName, qty: String(stack.qty) }));
      } else {
        if (nameEl) nameEl.textContent = '';
        if (countEl) {
          countEl.textContent = '';
          countEl.style.display = 'none';
        }
        parts.push(messages.hud.hotbar.emptySlot);
      }

      if (selected) parts.push(messages.hud.hotbar.selectedAria);
      slotEl.setAttribute('aria-label', parts.join(messages.hud.hotbar.ariaSeparator));
    }
  }

  function render(state: GameState): void {
    lastState = state;
    if (!dateEl || !clockEl || !weatherEl || !moneyEl || !shippingEl) return;

    const calendar = state.world.calendar;
    dateEl.textContent = formatDate(calendar, SEASON_NAMES, messages);
    dateEl.setAttribute(
      'aria-label',
      replaceTokens(messages.hud.date.aria, {
        season: SEASON_NAMES[calendar.seasonIndex] ?? String(calendar.seasonIndex),
        day: String(calendar.dayOfMonth),
        year: String(calendar.year),
      }),
    );

    clockEl.textContent = formatClock(state.world.clock, messages.hud.clock);
    clockEl.setAttribute('aria-label', messages.hud.clock.aria);

    const weatherName = messages.hud.weather.label[state.world.weather];
    weatherEl.textContent = weatherName;
    weatherEl.className = `eh-hud-weather eh-weather-${state.world.weather}`;
    weatherEl.setAttribute('aria-label', replaceTokens(messages.hud.weather.aria, { weather: weatherName }));

    moneyEl.textContent = formatMoney(state.player.money, messages);
    moneyEl.setAttribute(
      'aria-label',
      replaceTokens(messages.hud.money.aria, { amount: String(Math.max(0, Math.round(state.player.money))) }),
    );

    if (energyBarEl && energyFill && energyText) {
      energyFill.style.width = `${barPercent(state.player.energy, state.player.energyMax)}%`;
      energyText.textContent = formatBarAmount(state.player.energy, state.player.energyMax, messages);
      energyBarEl.setAttribute(
        'aria-label',
        replaceTokens(messages.hud.energy.aria, {
          current: String(Math.round(state.player.energy)),
          max: String(state.player.energyMax),
        }),
      );
    }

    if (healthBarEl && healthFill && healthText) {
      healthFill.style.width = `${barPercent(state.player.health, state.player.healthMax)}%`;
      healthText.textContent = formatBarAmount(state.player.health, state.player.healthMax, messages);
      healthBarEl.setAttribute(
        'aria-label',
        replaceTokens(messages.hud.health.aria, {
          current: String(Math.round(state.player.health)),
          max: String(state.player.healthMax),
        }),
      );
    }

    const shipped = shippingBoxCount(state.extensions.farming?.shippingBox);
    shippingEl.textContent = replaceTokens(messages.hud.shipping.count, { count: String(shipped) });
    shippingEl.setAttribute('aria-label', replaceTokens(messages.hud.shipping.aria, { count: String(shipped) }));

    if (buffsEl) {
      const rows = activeBuffRows(state, messages);
      if (rows.length > 0) {
        buffsEl.textContent = rows
          .map((r) => replaceTokens(messages.hud.buffs.row, { stat: r.statLabel, amount: String(r.amount), time: r.remaining }))
          .join(' · ');
        buffsEl.classList.add('is-visible');
        buffsEl.setAttribute(
          'aria-label',
          replaceTokens(messages.hud.buffs.aria, {
            text: rows
              .map((r) => replaceTokens(messages.hud.buffs.row, { stat: r.statLabel, amount: String(r.amount), time: r.remaining }))
              .join('. '),
          }),
        );
      } else {
        buffsEl.textContent = '';
        buffsEl.classList.remove('is-visible');
        buffsEl.setAttribute('aria-label', '');
      }
    }

    if (hintEl) {
      const front = tileInFront(state.player.position, state.player.facing);
      const hint = interactionHint(state, ctx.content, { ...front, mapId: state.player.position.mapId });
      if (hint) {
        const action = messages.hud.hint.action[hint.action];
        hintEl.textContent = replaceTokens(messages.hud.hint.line, { action, name: hint.name });
        hintEl.classList.add('is-visible');
        hintEl.setAttribute('aria-label', replaceTokens(messages.hud.hint.aria, { action, name: hint.name }));
      } else {
        hintEl.textContent = '';
        hintEl.classList.remove('is-visible');
        hintEl.setAttribute('aria-label', '');
      }
    }

    renderHotbar(state);
  }

  function onPointerUp(event: PointerEvent): void {
    if (dragIndex === null) return;
    const target = event.target as Element | null;
    const slotEl = target?.closest<HTMLElement>('.eh-slot') ?? null;
    const to = slotEl ? slotIndexFrom(slotEl) : -1;
    if (isSlotIndex(to) && to !== dragIndex) moveStack(dragIndex, to);
    if (dragEl) dragEl.classList.remove('eh-slot-dragging');
    dragEl = null;
    dragIndex = null;
  }

  return {
    mount(mountRoot: HTMLElement): void {
      if (typeof document === 'undefined') return;
      if (!mountRoot || root) return;
      doc = document;
      root = doc.createElement('div');
      root.className = 'eh-hud';
      root.style.pointerEvents = 'none';
      mountRoot.appendChild(root);
      buildDom();
      render(ctx.store.state);
      off = ctx.bus.on<GameState>('state:changed', (state) => render(state));
      window.addEventListener('pointerup', onPointerUp);
    },
    dispose(): void {
      off?.();
      off = null;
      window.removeEventListener('pointerup', onPointerUp);
      if (root?.parentElement) root.parentElement.removeChild(root);
      root = null;
      doc = null;
      slotEls.length = 0;
      dragIndex = null;
      dragEl = null;
      tooltip = null;
    },
  };
}

let hudCtx: FeatureContext | null = null;

export const hudUi = defineFeature({
  id: 'hud:ui',
  lane: 'ui',
  setup(ctx: FeatureContext): void {
    hudCtx = ctx;
  },
  ui(): UiHandle {
    if (!hudCtx) throw new Error('[hud:ui] ui() called before setup()');
    return createHudUi(hudCtx);
  },
});