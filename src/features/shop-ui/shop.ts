/**
 * shop:ui — shop dialog (WORKER-3 lane). Opens when the bus emits
 * `ui:open-shop` (dispatched by input:ui on the data-driven F key). MVP
 * discovery: the 'seed-shop' content entry, else the first shop in the content
 * table. Buy rows dispatch `shop:buy`; a sell section (when the shop buys)
 * dispatches `shop:sell`. Rows re-render on `state:changed`. DOM is only
 * touched from mount(), which no-ops without a document (headless tests).
 */
import { defineFeature, type FeatureContext, type UiHandle } from '../../core/feature';
import type { ItemDef, ShopDef } from '../../core/schemas';
import { createUiKit, type DialogHandle, type UiKit } from '../ui-kit';
import { MESSAGES, type Messages } from '../ui-kit/i18n/en';
import { replaceTokens } from '../ui-kit/template';
import { formatMoney } from '../hud/format';
import {
  remainingDisplayQty,
  resolveBuyPrice,
  sellableInventory,
  stockLabel,
  unknownItemLabel,
  type SellRow,
} from './format';

export const SHOP_BUY_QTY = 1;
export const SHOP_SELL_QTY = 1;

export function createShopUi(ctx: FeatureContext): UiHandle {
  const messages: Messages = MESSAGES;

  let root: HTMLElement | null = null;
  let kit: UiKit | null = null;
  let dialog: DialogHandle | null = null;
  let body: HTMLElement | null = null;
  let offOpen: (() => void) | null = null;
  let offState: (() => void) | null = null;
  let open = false;
  let currentShop: ShopDef | undefined;

  function make<K extends keyof HTMLElementTagNameMap>(
    tag: K,
    className: string,
  ): HTMLElementTagNameMap[K] | null {
    if (typeof document === 'undefined') return null;
    const node = document.createElement(tag);
    node.className = className;
    return node;
  }

  function line(text: string): HTMLElement | null {
    const el = make('div', 'eh-shop-line');
    if (!el) return null;
    el.textContent = text;
    return el;
  }

  function discoverShop(): ShopDef | undefined {
    return ctx.content.shops.get('seed-shop') ?? ctx.content.shops.values().next().value;
  }

  function shopExtension(): unknown {
    return ctx.store.state.extensions['shop'];
  }

  function itemName(item: ItemDef | undefined, id: string): string {
    return item?.name && item.name.length > 0 ? item.name : unknownItemLabel(id, messages);
  }

  function renderBuyRow(shop: ShopDef, entry: ShopDef['stock'][number]): HTMLElement | null {
    const item = ctx.content.items.get(entry.itemId);
    const price = resolveBuyPrice(entry, item);
    const remaining = remainingDisplayQty(shop.id, entry.itemId, entry.qty, shopExtension());

    const row = make('div', 'eh-shop-row');
    if (!row) return null;

    const info = make('div', 'eh-shop-info');
    if (info) {
      const name = make('span', 'eh-shop-item');
      if (name) name.textContent = itemName(item, entry.itemId);
      const priceEl = make('span', 'eh-shop-price');
      if (priceEl) priceEl.textContent = formatMoney(price, messages);
      if (name) info.appendChild(name);
      if (priceEl) info.appendChild(priceEl);
      row.appendChild(info);
    }

    const side = make('div', 'eh-shop-side');
    if (side) {
      const stock = make('span', 'eh-shop-stock');
      if (stock) stock.textContent = stockLabel(remaining, messages);
      const buy = document.createElement('button');
      buy.type = 'button';
      buy.className = 'eh-button eh-shop-buy';
      buy.textContent = messages.shop.buy;
      buy.disabled = remaining === 0;
      buy.addEventListener('click', () => {
        if (remaining === 0) return;
        ctx.store.dispatch({
          type: 'shop:buy',
          payload: { shopId: shop.id, itemId: entry.itemId, qty: SHOP_BUY_QTY },
        });
      });
      if (stock) side.appendChild(stock);
      side.appendChild(buy);
      row.appendChild(side);
    }
    return row;
  }

  function renderSellRow(shop: ShopDef, entry: SellRow): HTMLElement | null {
    const row = make('div', 'eh-shop-row');
    if (!row) return null;

    const info = make('div', 'eh-shop-info');
    if (info) {
      const name = make('span', 'eh-shop-item');
      if (name) name.textContent = entry.name;
      const qtyEl = make('span', 'eh-shop-qty');
      if (qtyEl) qtyEl.textContent = replaceTokens(messages.shop.qtyBadge, { qty: String(entry.qty) });
      const priceEl = make('span', 'eh-shop-price');
      if (priceEl) priceEl.textContent = formatMoney(entry.price, messages);
      if (name) info.appendChild(name);
      if (qtyEl) info.appendChild(qtyEl);
      if (priceEl) info.appendChild(priceEl);
      row.appendChild(info);
    }

    const side = make('div', 'eh-shop-side');
    if (side) {
      const sell = document.createElement('button');
      sell.type = 'button';
      sell.className = 'eh-button eh-shop-sell';
      sell.textContent = messages.shop.sell;
      sell.addEventListener('click', () => {
        ctx.store.dispatch({
          type: 'shop:sell',
          payload: { shopId: shop.id, itemId: entry.itemId, qty: SHOP_SELL_QTY },
        });
      });
      side.appendChild(sell);
      row.appendChild(side);
    }
    return row;
  }

  function sectionTitle(title: string): HTMLElement | null {
    const el = make('div', 'eh-shop-section-title');
    if (!el) return null;
    el.textContent = title;
    return el;
  }

  function render(): void {
    if (!body || !currentShop) return;
    body.replaceChildren();

    const moneyLine = line(
      replaceTokens(messages.shop.money, { gold: formatMoney(ctx.store.state.player.money, messages) }),
    );
    if (moneyLine) body.appendChild(moneyLine);

    const buyHeader = sectionTitle(messages.shop.buySection);
    if (buyHeader) body.appendChild(buyHeader);
    const buyBody = make('div', 'eh-shop-section');
    if (buyBody) {
      for (const entry of currentShop.stock) {
        const row = renderBuyRow(currentShop, entry);
        if (row) buyBody.appendChild(row);
      }
      body.appendChild(buyBody);
    }

    if (currentShop.buys) {
      const sellHeader = sectionTitle(messages.shop.sellSection);
      if (sellHeader) body.appendChild(sellHeader);
      const rows = sellableInventory(ctx.store.state.player.inventory.slots, ctx.content.items, messages);
      if (rows.length === 0) {
        const empty = line(messages.shop.sellEmpty);
        if (empty) body.appendChild(empty);
      } else {
        const sellBody = make('div', 'eh-shop-section');
        if (sellBody) {
          for (const entry of rows) {
            const row = renderSellRow(currentShop, entry);
            if (row) sellBody.appendChild(row);
          }
          body.appendChild(sellBody);
        }
      }
    }
  }

  function openShop(): void {
    if (!kit || !root) return;
    const shop = discoverShop();
    currentShop = shop;
    if (dialog) {
      dialog.dispose();
      dialog = null;
    }
    dialog = kit.dialog({
      title: shop ? shop.name : messages.shop.noShop,
      className: 'eh-shop-dialog',
      onClose: () => {
        open = false;
        currentShop = undefined;
      },
    });
    body = make('div', 'eh-shop');
    if (body && dialog) {
      dialog.setContent(body);
      if (shop) render();
      else {
        const empty = line(messages.shop.noShop);
        if (empty) body.appendChild(empty);
      }
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
      offOpen = ctx.bus.on('ui:open-shop', () => openShop());
      offState = ctx.bus.on('state:changed', () => {
        if (open && currentShop) render();
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
      currentShop = undefined;
      open = false;
      kit = null;
      root = null;
    },
  };
}

let shopCtx: FeatureContext | null = null;

export const shopUi = defineFeature({
  id: 'shop:ui',
  lane: 'ui',
  setup(ctx: FeatureContext): void {
    shopCtx = ctx;
  },
  ui(): UiHandle {
    if (!shopCtx) throw new Error('[shop:ui] ui() called before setup()');
    return createShopUi(shopCtx);
  },
});