/**
 * day-loop:ui — the keyboard day loop made visible (WORKER-3 lane, T-0511).
 *
 * Three surfaces, one feature, all fed from format.ts so the rules stay
 * testable without a DOM:
 *
 *  - the action bar (bottom-left): the key legend and what the selected stack
 *    can do, plus the two-press sleep confirmation. Key glyphs are read from the
 *    keymap, so the printed instruction is always the real binding.
 *  - the farm dialog (B, and the bar's buttons): Animals / Machines / Shipping
 *    tabs carrying the barn state, every machine's status and countdown, and
 *    the bin's contents with the gold it will pay at sleep.
 *  - the toast stack (top-right): one friendly sentence per sim denial, so a
 *    refusal explains itself instead of failing silently.
 *
 * Dialogs are modal one layer deep, same as the shop/journal/crafting panels:
 * the ui-kit closes any other open dialog when this one opens.
 */
import { defineFeature, type FeatureContext, type UiHandle } from '../../core/feature';
import type { GameState } from '../../core/types';
import { createUiKit, type DialogHandle, type TabHandle, type UiKit } from '../ui-kit';
import { MESSAGES, type Messages } from '../ui-kit/i18n/en';
import { replaceTokens } from '../ui-kit/template';
import { keyGlyph, normalizeKey } from '../input/keymap';
import { shouldSwallowKey } from '../input/input';
import { formatMoney } from '../hud/format';
import {
  animalProductText,
  buildAnimalBuyRows,
  buildAnimalRows,
  buildMachineRows,
  BARN_ACTION_LABELS,
  barnActionForKey,
  barnRowHint,
  contextActionText,
  denialText,
  facedContextAction,
  moveBarnSelection,
  pressSleep,
  selectedStackActions,
  shippingBinModel,
  shippingRowText,
  sleepArmed,
  type AnimalRow,
  type BarnAction,
  type DenialTokens,
  type MachineRow,
} from './format';

/** How long a refusal stays on screen. */
export const TOAST_MS = 3200;
/** Most toasts shown at once; older ones drop off the top. */
export const TOAST_LIMIT = 3;

export type FarmTab = 'animals' | 'machines' | 'shipping';

export function createDayLoopUi(ctx: FeatureContext): UiHandle {
  const messages: Messages = MESSAGES;
  // Glyphs are derived from the keymap, never typed into the copy, so the
  // printed instruction is always the key the game actually listens for.
  const keys = {
    ship: keyGlyph('ship'),
    eat: keyGlyph('eat'),
    sleep: keyGlyph('sleep'),
    barn: keyGlyph('barn'),
    interact: keyGlyph('interact'),
    use: keyGlyph('use'),
    crafting: keyGlyph('crafting'),
  };

  let root: HTMLElement | null = null;
  let kit: UiKit | null = null;
  let offs: Array<() => void> = [];

  // --- action bar ---
  let barEl: HTMLElement | null = null;
  let barTitle: HTMLElement | null = null;
  let barActions: HTMLElement | null = null;
  let barContext: HTMLElement | null = null;
  let barLegend: HTMLElement | null = null;
  let barPrompt: HTMLElement | null = null;
  let barButtons: HTMLButtonElement[] = [];

  // --- toasts ---
  let toastEl: HTMLElement | null = null;
  const toastTimers = new Set<number>();

  // --- farm dialog ---
  let dialog: DialogHandle | null = null;
  let tabs: TabHandle | null = null;
  let farmOpen = false;
  let activeTab: FarmTab = 'animals';
  /** Highlighted barn row, driven by the arrow keys while the panel is open. */
  let barnSelected = 0;
  let barnRows: AnimalRow[] = [];

  let armedAt: number | null = null;
  let armedTimer: number | null = null;

  // The bus replays its buffer to every new subscriber, so denials from before
  // mount (and from any other feature's own test) must not pop a stale toast.
  let live = false;

  function make<K extends keyof HTMLElementTagNameMap>(
    tag: K,
    className: string,
  ): HTMLElementTagNameMap[K] | null {
    if (typeof document === 'undefined') return null;
    const node = document.createElement(tag);
    node.className = className;
    return node;
  }

  function line(text: string, className: string): HTMLElement | null {
    const el = make('div', className);
    if (el) el.textContent = text;
    return el;
  }

  /** Append a list of possibly-null children; DOM helpers here never throw. */
  function appendAll(parent: HTMLElement, children: Array<HTMLElement | null>): void {
    for (const child of children) {
      if (child) parent.appendChild(child);
    }
  }

  // ------------------------------------------------------------------ toasts

  function showToast(text: string): void {
    if (!toastEl || !text) return;
    const el = make('div', 'eh-toast');
    if (!el) return;
    el.textContent = text;
    el.setAttribute('role', 'status');
    while (toastEl.children.length >= TOAST_LIMIT) {
      const first = toastEl.firstElementChild;
      if (!first) break;
      toastEl.removeChild(first);
    }
    toastEl.appendChild(el);
    const id = window.setTimeout(() => {
      toastTimers.delete(id);
      if (el.parentElement) el.parentElement.removeChild(el);
    }, TOAST_MS);
    toastTimers.add(id);
  }

  function clearToasts(): void {
    for (const id of toastTimers) window.clearTimeout(id);
    toastTimers.clear();
    if (toastEl) toastEl.replaceChildren();
  }

  // -------------------------------------------------------------- action bar

  function buildBar(): void {
    if (!kit || !root) return;
    barEl = make('div', 'eh-actionbar');
    if (!barEl) return;
    barTitle = make('div', 'eh-actionbar-title');
    barActions = make('div', 'eh-actionbar-actions');
    barContext = make('div', 'eh-actionbar-context');
    barPrompt = make('div', 'eh-actionbar-prompt');
    barButtons = [];
    for (const [tab, label] of [
      ['animals', messages.actions.barn],
      ['machines', messages.farm.tabMachines],
      ['shipping', messages.farm.tabShipping],
    ] as const) {
      const button = make('button', 'eh-button eh-actionbar-btn');
      if (!button) continue;
      button.type = 'button';
      button.textContent =
        tab === 'animals' ? `${keys.barn} ${label}` : label;
      button.setAttribute('aria-label', replaceTokens(messages.farm.openTab, { tab: label }));
      button.addEventListener('click', () => openFarm(tab));
      barActions?.appendChild(button);
      barButtons.push(button);
    }
    if (barTitle) barEl.appendChild(barTitle);
    if (barActions) barEl.appendChild(barActions);
    if (barContext) barEl.appendChild(barContext);
    if (barPrompt) barEl.appendChild(barPrompt);
    barLegend = line(
      replaceTokens(messages.actions.legend, {
        ship: keys.ship,
        eat: keys.eat,
        interact: keys.interact,
        use: keys.use,
        barn: keys.barn,
        sleep: keys.sleep,
      }),
      'eh-actionbar-legend',
    );
    if (barLegend) barEl.appendChild(barLegend);
    kit.container?.appendChild(barEl);
  }

  function renderBar(state: GameState): void {
    const selected = selectedStackActions(state, ctx.content, { ship: keys.ship, eat: keys.eat }, messages);
    if (barTitle) {
      barTitle.textContent = selected
        ? replaceTokens(messages.actions.selectedTitle, {}) + ': ' + selected.name
        : messages.hud.selected.empty;
      barTitle.classList.toggle('is-empty', !selected);
    }
    if (barActions) {
      barActions.replaceChildren();
      for (const action of selected?.actions ?? []) {
        const chip = make('span', `eh-actionbar-chip eh-action-${action.kind}`);
        if (!chip) continue;
        chip.textContent = `${action.key} ${action.label}`;
        barActions.appendChild(chip);
      }
      if (selected && selected.actions.length === 0) {
        const none = make('span', 'eh-actionbar-chip is-none');
        if (none) {
          none.textContent = messages.actions.none;
          barActions.appendChild(none);
        }
      }
    }
    renderContext(state);
    renderPrompt();
  }

  /**
   * The contextual use key, shown only while there is a machine in front of the
   * player. Advertising it over bare grass would be a promise the sim refuses,
   * and a chip that lies is worse than no chip at all.
   */
  function renderContext(state: GameState): void {
    if (!barContext) return;
    barContext.replaceChildren();
    const action = facedContextAction(state, ctx.content, { use: keys.use }, messages);
    if (!action) {
      barContext.classList.remove('is-visible');
      return;
    }
    const chip = make('span', `eh-actionbar-chip eh-action-use is-${action.kind}`);
    if (chip) {
      chip.textContent = contextActionText(action, messages);
      barContext.appendChild(chip);
    }
    barContext.classList.add('is-visible');
  }

  /**
   * While sleep is armed the prompt also states what the bin will pay, so the
   * confirmation is the last place a player can see the day's earnings before
   * they commit to ending it.
   */
  function renderPrompt(): void {
    if (!barPrompt) return;
    if (armedAt !== null && sleepArmed(armedAt, Date.now())) {
      const payout = shippingBinModel(ctx.store.state, ctx.content).totalGold;
      barPrompt.textContent =
        payout > 0
          ? replaceTokens(messages.actions.sleepArmedPayout, {
              key: keys.sleep,
              gold: formatMoney(payout, messages),
            })
          : replaceTokens(messages.actions.sleepArmed, { key: keys.sleep });
      barPrompt.classList.add('is-visible');
    } else {
      barPrompt.textContent = '';
      barPrompt.classList.remove('is-visible');
    }
  }

  // ------------------------------------------------------------ farm dialog

  function animalRow(row: AnimalRow, index: number): HTMLElement | null {
    const selected = index === barnSelected;
    const el = make('div', `eh-farm-row eh-animal-row${selected ? ' is-selected' : ''}`);
    if (!el) return null;
    const info = make('div', 'eh-farm-info');
    if (info) {
      const name = make('span', 'eh-farm-item');
      if (name) name.textContent = row.name;
      const hearts = make('span', 'eh-farm-meta');
      if (hearts) {
        hearts.textContent = replaceTokens(messages.barn.hearts, {
          hearts: row.hearts.toFixed(1),
          heartsMax: String(row.heartsMax),
        });
      }
      const happy = make('span', 'eh-farm-meta');
      if (happy) {
        happy.textContent = replaceTokens(messages.barn.happy, { happy: String(Math.round(row.happy)) });
      }
      const state = make('span', 'eh-farm-meta');
      if (state) {
        state.textContent = [
          row.fed ? messages.barn.fed : messages.barn.notFed,
          row.petted ? messages.barn.petted : messages.barn.notPetted,
        ].join(' · ');
      }
      const product = make('span', `eh-farm-product${row.productReady ? ' is-ready' : ''}`);
      if (product) {
        product.textContent = animalProductText(row, ctx.store.state.world.dayCount, messages);
      }
      const feed = make('span', 'eh-farm-meta');
      if (feed) {
        feed.textContent = replaceTokens(row.canFeed ? messages.barn.feedHave : messages.barn.feedMissing, {
          name: row.feedName,
          have: String(row.feedHave),
        });
      }
      appendAll(info, [name, hearts, happy, state, product, feed]);
      el.appendChild(info);
    }
    const side = make('div', 'eh-farm-side');
    if (side) {
      // The key hint rides with the row so the numbers that drive it are only
      // printed on the row they act on.
      if (selected) {
        const hint = make('span', 'eh-farm-keyhint');
        if (hint) {
          hint.textContent = barnRowHint(row, BARN_ACTION_LABELS, messages);
          side.appendChild(hint);
        }
      }
      const feedBtn = button(`${BARN_ACTION_LABELS.feed} ${messages.barn.feed}`, row.canFeed, () =>
        ctx.store.dispatch({ type: 'animals:feed', payload: { animalId: row.id } }),
      );
      const petBtn = button(`${BARN_ACTION_LABELS.pet} ${messages.barn.pet}`, row.canPet, () =>
        ctx.store.dispatch({ type: 'animals:pet', payload: { animalId: row.id } }),
      );
      const collectBtn = button(`${BARN_ACTION_LABELS.collect} ${messages.barn.collect}`, row.canCollect, () =>
        ctx.store.dispatch({ type: 'animals:collect', payload: { animalId: row.id } }),
      );
      appendAll(side, [feedBtn, petBtn, collectBtn]);
      el.appendChild(side);
    }
    return el;
  }

  function buyRow(): HTMLElement | null {
    const wrapper = make('div', 'eh-farm-section');
    if (!wrapper) return null;
    const title = line(messages.barn.sectionBuy, 'eh-farm-section-title');
    if (title) wrapper.appendChild(title);
    for (const buy of buildAnimalBuyRows(ctx.store.state, ctx.content)) {
      const el = make('div', 'eh-farm-row');
      if (!el) continue;
      const info = make('div', 'eh-farm-info');
      if (info) {
        const name = make('span', 'eh-farm-item');
        if (name) name.textContent = buy.name;
        const meta = make('span', 'eh-farm-meta');
        if (meta) {
          meta.textContent = `${formatMoney(buy.price, messages)} · ${buy.productName}`;
        }
        appendAll(info, [name, meta]);
        el.appendChild(info);
      }
      const side = make('div', 'eh-farm-side');
      if (side) {
        const price = make('span', 'eh-farm-meta');
        if (price) price.textContent = formatMoney(buy.price, messages);
        const buyButton = button(messages.barn.buy, buy.affordable, () =>
          ctx.store.dispatch({ type: 'animals:buy', payload: { species: buy.species, qty: 1 } }),
        );
        appendAll(side, [price, buyButton]);
        el.appendChild(side);
      }
      wrapper.appendChild(el);
    }
    return wrapper;
  }

  function machineRow(row: MachineRow): HTMLElement | null {
    const el = make('div', `eh-farm-row eh-machine-${row.status}`);
    if (!el) return null;
    const info = make('div', 'eh-farm-info');
    if (info) {
      const name = make('span', 'eh-farm-item');
      if (name) name.textContent = row.name;
      const status = make('span', `eh-farm-status is-${row.status}`);
      if (status) status.textContent = machineStatusText(row);
      const io = make('span', 'eh-farm-meta');
      if (io) io.textContent = `${row.inputText} → ${row.outputText}`;
      const where = make('span', 'eh-farm-meta');
      if (where) where.textContent = `${row.mapId} ${row.x},${row.y}`;
      appendAll(info, [name, status, io, where]);
      el.appendChild(info);
    }
    return el;
  }

  function machineStatusText(row: MachineRow): string {
    if (row.status === 'busy') {
      return replaceTokens(messages.farm.machineBusy, { time: row.remainingText });
    }
    if (row.status === 'ready') {
      return replaceTokens(messages.farm.machineReady, { key: keys.interact });
    }
    return replaceTokens(messages.farm.machineEmpty, { key: keys.interact });
  }

  function shippingBody(target: HTMLElement): void {
    target.replaceChildren();
    const model = shippingBinModel(ctx.store.state, ctx.content);
    if (model.rows.length === 0) {
      const empty = line(
        replaceTokens(messages.shippingPanel.empty, { key: keys.ship }),
        'eh-farm-line',
      );
      if (empty) target.appendChild(empty);
      return;
    }
    for (const row of model.rows) {
      const el = make('div', 'eh-farm-row');
      if (!el) continue;
      const info = make('div', 'eh-farm-info');
      if (info) {
        const text = make('span', 'eh-farm-item');
        if (text) text.textContent = shippingRowText(row, messages);
        appendAll(info, [text]);
        el.appendChild(info);
      }
      const side = make('div', 'eh-farm-side');
      if (side) {
        const gold = make('span', 'eh-farm-meta');
        if (gold) gold.textContent = formatMoney(row.gold, messages);
        appendAll(side, [gold]);
        el.appendChild(side);
      }
      target.appendChild(el);
    }
    const items = line(
      replaceTokens(messages.shippingPanel.totalItems, { count: String(model.totalQty) }),
      'eh-farm-line',
    );
    const total = line(
      replaceTokens(messages.shippingPanel.totalGold, {
        gold: formatMoney(model.totalGold, messages),
      }),
      'eh-farm-line eh-farm-total',
    );
    appendAll(target, [items, total]);
  }

  function button(label: string, enabled: boolean, onClick: () => void): HTMLButtonElement | null {
    const el = make('button', 'eh-button eh-farm-btn');
    if (!el) return null;
    el.type = 'button';
    el.textContent = label;
    el.disabled = !enabled;
    el.addEventListener('click', onClick);
    return el;
  }

  function renderFarm(): void {
    if (!farmOpen || !tabs) return;
    const animalsBody = tabs.body('animals').el;
    if (animalsBody) {
      animalsBody.replaceChildren();
      barnRows = buildAnimalRows(ctx.store.state, ctx.content);
      if (barnSelected >= barnRows.length) barnSelected = 0;
      if (barnRows.length === 0) {
        const empty = line(messages.barn.empty, 'eh-farm-line');
        if (empty) animalsBody.appendChild(empty);
      } else {
        const title = line(messages.barn.sectionHerd, 'eh-farm-section-title');
        if (title) animalsBody.appendChild(title);
        const nav = line(
          replaceTokens(messages.barn.rowNav, { count: String(barnRows.length) }),
          'eh-farm-line eh-farm-nav',
        );
        if (nav) animalsBody.appendChild(nav);
        for (const [index, row] of barnRows.entries()) {
          const el = animalRow(row, index);
          if (el) animalsBody.appendChild(el);
        }
      }
      const buy = buyRow();
      if (buy) animalsBody.appendChild(buy);
    }

    const machinesBody = tabs.body('machines').el;
    if (machinesBody) {
      machinesBody.replaceChildren();
      const rows = buildMachineRows(ctx.store.state, ctx.content);
      if (rows.length === 0) {
        const empty = line(messages.farm.noMachines, 'eh-farm-line');
        if (empty) machinesBody.appendChild(empty);
      } else {
        for (const row of rows) {
          const el = machineRow(row);
          if (el) machinesBody.appendChild(el);
        }
      }
    }

    const shippingTab = tabs.body('shipping').el;
    if (shippingTab) shippingBody(shippingTab);
  }

  function openFarm(tab: FarmTab = activeTab): void {
    if (!kit || typeof document === 'undefined') return;
    if (farmOpen && tab === activeTab) {
      closeFarm();
      return;
    }
    activeTab = tab;
    if (dialog) {
      dialog.dispose();
      dialog = null;
    }
    dialog = kit.dialog({
      title: messages.farm.title,
      className: 'eh-farm-dialog',
      onClose: () => {
        farmOpen = false;
      },
    });
    tabs = kit.tab({
      tabs: [
        { id: 'animals', label: messages.farm.tabAnimals },
        { id: 'machines', label: messages.farm.tabMachines },
        { id: 'shipping', label: messages.farm.tabShipping },
      ],
      active: tab,
      className: 'eh-farm-tabs',
    });
    const body = make('div', 'eh-farm');
    if (!body || !tabs.el || !dialog) return;
    body.appendChild(tabs.el);
    dialog.setContent(body);
    // farmOpen first: renderFarm() is the guard against painting a dialog that
    // is not on screen, so it has to already see the dialog as open or the
    // first paint is skipped and the tabs come up blank.
    farmOpen = true;
    renderFarm();
    dialog.open();
  }

  function closeFarm(): void {
    dialog?.close();
    dialog?.dispose();
    dialog = null;
    tabs = null;
    farmOpen = false;
    barnRows = [];
    barnSelected = 0;
  }

  /**
   * Dispatch a barn action for the highlighted row.
   *
   * Deliberately NOT gated on `canBarnAction`: the row's buttons are disabled
   * when an action is unavailable, but a keypress cannot be disabled, and a key
   * that silently does nothing is the one thing the player cannot debug. The
   * sim refuses the same way the button would, and the refusal arrives as a
   * sentence ("You have no feed left. Buy hay, or make more."), so pressing 1
   * with no hay in the bag teaches the player why instead of ignoring them.
   */
  function runBarnAction(action: BarnAction): void {
    const row = barnRows[barnSelected];
    if (!row) return;
    if (action === 'feed') ctx.store.dispatch({ type: 'animals:feed', payload: { animalId: row.id } });
    else if (action === 'pet') ctx.store.dispatch({ type: 'animals:pet', payload: { animalId: row.id } });
    else ctx.store.dispatch({ type: 'animals:collect', payload: { animalId: row.id } });
  }

  /**
   * The farm panel owns the keyboard while it is open, the way a modal should.
   *
   * Registered in the capture phase (the same pattern the dialogue box uses) so
   * it runs before the global input layer and can stop the event reaching it:
   * otherwise pressing 2 to pet a chicken would also select hotbar slot 2 and
   * swap the tool out from under the player mid-panel. Typing in a text field
   * still wins, because a focused field is checked before any of this.
   *
   * The `farmOpen` guard is load-bearing: a capture-phase listener that claims
   * Escape while no panel is open would silently break Escape in every other
   * dialog, since stopping propagation here means they never see the key.
   */
  function onFarmKeyDown(event: KeyboardEvent): void {
    if (!farmOpen) return;
    if (shouldSwallowKey(event.target, normalizeKey(event.key))) return;
    const key = normalizeKey(event.key);
    if (key === 'escape') {
      event.preventDefault();
      event.stopPropagation();
      closeFarm();
      return;
    }
    if (activeTab !== 'animals' || barnRows.length === 0) return;
    if (key === 'arrowdown' || key === 'arrowup') {
      event.preventDefault();
      event.stopPropagation();
      barnSelected = moveBarnSelection(barnSelected, key === 'arrowdown' ? 1 : -1, barnRows.length);
      renderFarm();
      return;
    }
    const action = barnActionForKey(key);
    if (!action) return;
    event.preventDefault();
    event.stopPropagation();
    runBarnAction(action);
  }

  // ------------------------------------------------------------------- sleep

  function armSleep(): void {
    if (armedTimer !== null) window.clearTimeout(armedTimer);
    armedTimer = window.setTimeout(() => {
      armedTimer = null;
      armedAt = null;
      renderPrompt();
    }, 2600);
  }

  function onToggleSleep(): void {
    const result = pressSleep(armedAt, Date.now());
    armedAt = result.armedAt;
    if (result.press === 'slept') {
      if (armedTimer !== null) {
        window.clearTimeout(armedTimer);
        armedTimer = null;
      }
      closeFarm();
      ctx.store.dispatch({ type: 'player:sleep', payload: null });
      return;
    }
    armSleep();
    renderPrompt();
  }

  // ----------------------------------------------------------------- denials

  /** Reason codes carry an item/slot; name the thing so the line is specific. */
  function denialTokens(scope: string, payload: unknown): DenialTokens {
    const p = (payload ?? {}) as Record<string, unknown>;
    // The `{key}` in a refusal names the key that WOULD have worked, which is
    // not the same key in every scope: "not food" points at the crafting key
    // and "not loaded" at the contextual use key. Defaulting both to the
    // interact key printed "Cook something with Space first", which is a lie.
    const tokens: DenialTokens = { key: scope === 'crafting' ? keys.crafting : keys.use, time: '' };
    if (scope === 'animals' && typeof p['gold'] === 'number') tokens.gold = p['gold'];
    if (scope === 'animals' && typeof p['species'] === 'string') {
      tokens.name = ctx.content.animals.get(p['species'])?.name ?? String(p['species']);
    }
    if (scope === 'shipping' && typeof p['itemId'] === 'string') {
      const item = ctx.content.items.get(p['itemId']);
      tokens.name = item?.name ?? String(p['itemId']);
    }
    if (scope === 'machines' && typeof p['machineId'] === 'string') {
      const machine = ctx.content.machines.get(p['machineId']);
      tokens.name = machine?.name ?? String(p['machineId']);
    }
    if (scope === 'machines' && typeof p['itemId'] === 'string') {
      tokens.name = ctx.content.items.get(p['itemId'])?.name ?? String(p['itemId']);
    }
    return tokens;
  }

  function onDenial(scope: string, payload: unknown): void {
    if (!live) return;
    const p = (payload ?? {}) as Record<string, unknown>;
    const reason = typeof p['reason'] === 'string' ? p['reason'] : undefined;
    const tokens = denialTokens(scope, payload);
    if (scope === 'machines' && reason === 'busy' && typeof p['machineId'] === 'string') {
      const row = buildMachineRows(ctx.store.state, ctx.content).find(
        (m) => m.machineId === p['machineId'] && m.status === 'busy',
      );
      if (row) tokens.time = row.remainingText;
    }
    showToast(denialText(scope, reason, tokens, messages));
  }

  return {
    mount(mountRoot: HTMLElement): void {
      if (typeof document === 'undefined') return;
      if (!mountRoot || root) return;
      root = mountRoot;
      kit = createUiKit(root);
      buildBar();
      window.addEventListener('keydown', onFarmKeyDown, true);
      toastEl = make('div', 'eh-toasts');
      if (toastEl) root.appendChild(toastEl);
      renderBar(ctx.store.state);

      offs.push(ctx.bus.on('state:changed', (state: GameState) => {
        renderBar(state);
        renderPrompt();
        if (farmOpen) renderFarm();
      }));
      offs.push(ctx.bus.on('ui:toggle-sleep', () => onToggleSleep()));
      offs.push(ctx.bus.on('ui:open-barn', () => openFarm('animals')));
      offs.push(ctx.bus.on('ui:open-farm', (payload: unknown) => {
        const tab = (payload as { tab?: FarmTab } | null)?.tab;
        openFarm(tab === 'machines' || tab === 'shipping' ? tab : 'animals');
      }));
      offs.push(
        ctx.bus.on('shipping:denied', (p) => onDenial('shipping', p)),
        ctx.bus.on('crafting:denied', (p) => onDenial('crafting', p)),
        ctx.bus.on('animals:denied', (p) => onDenial('animals', p)),
        ctx.bus.on('machines:denied', (p) => onDenial('machines', p)),
        ctx.bus.on('farming:blocked', (p) => onDenial('farming', p)),
        ctx.bus.on('player:exhausted', (p) => onDenial('farming', { ...(p as object), reason: 'exhausted' })),
        ctx.bus.on('inventory:full', (p) => onDenial('inventory', p)),
      );
      offs.push(
        ctx.bus.on('day:started', () => {
          armedAt = null;
          if (armedTimer !== null) {
            window.clearTimeout(armedTimer);
            armedTimer = null;
          }
        }),
      );
      live = true;
    },
    dispose(): void {
      for (const off of offs) off();
      offs = [];
      window.removeEventListener('keydown', onFarmKeyDown, true);
      clearToasts();
      closeFarm();
      if (armedTimer !== null) {
        window.clearTimeout(armedTimer);
        armedTimer = null;
      }
      armedAt = null;
      if (barEl?.parentElement) barEl.parentElement.removeChild(barEl);
      if (toastEl?.parentElement) toastEl.parentElement.removeChild(toastEl);
      barEl = null;
      barTitle = null;
      barActions = null;
      barLegend = null;
      barPrompt = null;
      barButtons = [];
      toastEl = null;
      live = false;
      kit = null;
      root = null;
    },
  };
}

let dayLoopCtx: FeatureContext | null = null;

export const dayLoopUi = defineFeature({
  id: 'day-loop:ui',
  lane: 'ui',
  setup(ctx: FeatureContext): void {
    dayLoopCtx = ctx;
  },
  ui(): UiHandle {
    if (!dayLoopCtx) throw new Error('[day-loop:ui] ui() called before setup()');
    return createDayLoopUi(dayLoopCtx);
  },
});
