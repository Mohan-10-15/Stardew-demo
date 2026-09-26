/**
 * crafting:ui — crafting/cooking dialog (WORKER-3 lane). Opens when the bus
 * emits `ui:open-crafting` (dispatched by input:ui on the data-driven C key).
 * Shows every authored recipe split into a Crafting section and a Cooking
 * section: unlocked rows dispatch `crafting:craft {recipeId}`; locked rows are
 * muted with the skill requirement. Rows re-render on `state:changed`. DOM is
 * only touched from the render path, which no-ops without a document (headless
 * tests cover the pure format layer instead).
 */
import { defineFeature, type FeatureContext, type UiHandle } from '../../core/feature';
import { createUiKit, type DialogHandle, type UiKit } from '../ui-kit';
import { MESSAGES, type Messages } from '../ui-kit/i18n/en';
import {
  buildRecipeRows,
  buffLabel,
  foodLabel,
  ingredientLabel,
  lockLabel,
  type RecipeRow,
} from './format';

export function createCraftingUi(ctx: FeatureContext): UiHandle {
  const messages: Messages = MESSAGES;

  let root: HTMLElement | null = null;
  let kit: UiKit | null = null;
  let dialog: DialogHandle | null = null;
  let body: HTMLElement | null = null;
  let offOpen: (() => void) | null = null;
  let offState: (() => void) | null = null;
  let open = false;

  function make<K extends keyof HTMLElementTagNameMap>(
    tag: K,
    className: string,
  ): HTMLElementTagNameMap[K] | null {
    if (typeof document === 'undefined') return null;
    const node = document.createElement(tag);
    node.className = className;
    return node;
  }

  function line(text: string, className = 'eh-crafting-line'): HTMLElement | null {
    const el = make('div', className);
    if (!el) return null;
    el.textContent = text;
    return el;
  }

  function sectionTitle(title: string): HTMLElement | null {
    return line(title, 'eh-crafting-section-title');
  }

  function metaFor(row: RecipeRow): string {
    const parts = [ingredientLabel(row.ingredients, messages)];
    const stats = foodLabel(row.energy, row.health, messages);
    if (stats) parts.push(stats);
    for (const buff of row.buffs) parts.push(buffLabel(buff, messages));
    return parts.join(' · ');
  }

  function renderRow(row: RecipeRow): HTMLElement | null {
    const rowEl = make('div', 'eh-crafting-row');
    if (!rowEl) return null;
    if (!row.unlocked) rowEl.classList.add('is-locked');

    const info = make('div', 'eh-crafting-info');
    if (info) {
      const name = make('span', 'eh-crafting-item');
      if (name) name.textContent = row.name;
      const meta = make('span', 'eh-crafting-meta');
      if (meta)
        meta.textContent = row.unlocked
          ? metaFor(row)
          : lockLabel(row.lockSkill, row.lockLevel, messages);
      if (name) info.appendChild(name);
      if (meta) info.appendChild(meta);
      rowEl.appendChild(info);
    }

    const side = make('div', 'eh-crafting-side');
    if (side) {
      const craft = document.createElement('button');
      craft.type = 'button';
      craft.className = 'eh-button eh-crafting-craft';
      craft.textContent = messages.crafting.craft;
      craft.disabled = !row.canCraft;
      craft.addEventListener('click', () => {
        if (!row.canCraft) return;
        ctx.store.dispatch({ type: 'crafting:craft', payload: { recipeId: row.recipeId } });
      });
      side.appendChild(craft);
      rowEl.appendChild(side);
    }
    return rowEl;
  }

  function renderSection(title: string, rows: RecipeRow[]): void {
    if (!body) return;
    if (rows.length === 0) return;
    const header = sectionTitle(title);
    if (header) body.appendChild(header);
    for (const row of rows) {
      const el = renderRow(row);
      if (el) body.appendChild(el);
    }
  }

  function render(): void {
    if (!body) return;
    body.replaceChildren();
    const rows = buildRecipeRows(ctx.content, ctx.store.state, messages);
    const crafts = rows.filter((r) => r.kind === 'crafting');
    const cooking = rows.filter((r) => r.kind === 'cooking');
    renderSection(messages.crafting.sectionCrafts, crafts);
    renderSection(messages.crafting.sectionCooking, cooking);
    if (crafts.length === 0 && cooking.length === 0) {
      const empty = line(messages.crafting.noRecipes);
      if (empty) body.appendChild(empty);
    }
  }

  function closePanel(): void {
    dialog?.close();
    dialog?.dispose();
    dialog = null;
    open = false;
    body = null;
  }

  function openPanel(): void {
    if (!kit || !root) return;
    if (open) {
      // The hotkey is a toggle, the same as the settings dialog: pressing C
      // with the panel up must close it, not silently rebuild it.
      closePanel();
      return;
    }
    if (dialog) {
      dialog.dispose();
      dialog = null;
    }
    dialog = kit.dialog({
      title: messages.crafting.title,
      className: 'eh-crafting-dialog',
      onClose: () => {
        open = false;
        body = null;
      },
    });
    body = make('div', 'eh-crafting');
    if (body && dialog) {
      dialog.setContent(body);
      render();
      dialog.open();
      open = true;
    }
  }

  return {
    mount(mountRoot: HTMLElement): void {
      if (typeof document === 'undefined') return;
      if (root || !mountRoot) return;
      root = mountRoot;
      kit = createUiKit(root);
      offOpen = ctx.bus.on('ui:open-crafting', () => openPanel());
      offState = ctx.bus.on('state:changed', () => {
        if (open) render();
      });
    },
    dispose(): void {
      if (typeof document === 'undefined') return;
      offOpen?.();
      offOpen = null;
      offState?.();
      offState = null;
      dialog?.dispose();
      dialog = null;
      body = null;
      open = false;
      kit = null;
      root = null;
    },
  };
}

let craftingCtx: FeatureContext | null = null;

export const craftingUi = defineFeature({
  id: 'crafting:ui',
  lane: 'ui',
  setup(ctx: FeatureContext): void {
    craftingCtx = ctx;
  },
  ui(): UiHandle {
    if (!craftingCtx) throw new Error('[crafting:ui] ui() called before setup()');
    return createCraftingUi(craftingCtx);
  },
});
